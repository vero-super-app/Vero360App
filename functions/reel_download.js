const os = require('os');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const axios = require('axios');
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { renderBrandedReel } = require('./reel_watermark');

if (!admin.apps.length) {
  admin.initializeApp();
}

/** Bump when the watermark or end card design changes so old cached files are not reused. */
const DESIGN_VERSION = 2;
const MAX_INPUT_BYTES = 80 * 1024 * 1024;
/** A render that hasn't finished in this long is assumed dead and may be retried. */
const LOCK_TTL_MS = 4 * 60 * 1000;
const SERVICE_ACCOUNT = 'vero360app-ca423@appspot.gserviceaccount.com';
const RENDER_OPTIONS = {
  memory: '4GiB',
  cpu: 4,
  timeoutSeconds: 300,
  concurrency: 1,
  maxInstances: 10,
  serviceAccount: SERVICE_ACCOUNT,
};

function downloadUrl(bucket, objectPath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchToFile(url, dest, maxBytes) {
  const res = await axios.get(url, {
    responseType: 'stream',
    timeout: 60000,
    maxContentLength: maxBytes,
  });
  await new Promise((resolve, reject) => {
    let got = 0;
    const out = fs.createWriteStream(dest);
    res.data.on('data', (chunk) => {
      got += chunk.length;
      if (got > maxBytes) {
        res.data.destroy(new Error('Video is too large.'));
      }
    });
    res.data.on('error', reject);
    out.on('error', reject);
    out.on('finish', resolve);
    res.data.pipe(out);
  });
}

async function fetchBuffer(url) {
  if (!/^https?:\/\//i.test(String(url || ''))) return null;
  try {
    const res = await axios.get(url, {
      responseType: 'arraybuffer',
      timeout: 15000,
      maxContentLength: 8 * 1024 * 1024,
    });
    return Buffer.from(res.data);
  } catch (_) {
    return null;
  }
}

function lookFor(reel) {
  const videoUrl = String(reel.videoUrl || '').trim();
  const ownerName = String(reel.ownerName || '').trim() || 'Vero360 member';
  const ownerPhotoUrl = String(reel.ownerPhoto || '').trim();
  const isMerchant = reel.ownerIsMerchant === true;
  const look = crypto
    .createHash('sha1')
    .update(JSON.stringify([DESIGN_VERSION, videoUrl, ownerName, ownerPhotoUrl, isMerchant]))
    .digest('hex')
    .slice(0, 16);
  return { videoUrl, ownerName, ownerPhotoUrl, isMerchant, look };
}

async function cachedUrl(file, bucketName, objectPath) {
  const [exists] = await file.exists();
  if (!exists) return null;
  const [meta] = await file.getMetadata();
  let token = String(meta?.metadata?.firebaseStorageDownloadTokens || '').split(',')[0];
  if (!token) {
    token = crypto.randomUUID();
    await file.setMetadata({ metadata: { firebaseStorageDownloadTokens: token } });
  }
  return downloadUrl(bucketName, objectPath, token);
}

/** Claims the render for this look; false if another instance is already on it. */
async function claimRender(reelId, look) {
  const ref = admin.firestore().collection('reel_download_jobs').doc(reelId);
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data() || {};
    const startedAt = d.startedAt?.toMillis ? d.startedAt.toMillis() : 0;
    if (d.look === look && d.status === 'rendering' && Date.now() - startedAt < LOCK_TTL_MS) {
      return false;
    }
    tx.set(ref, {
      look,
      status: 'rendering',
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * Makes sure the branded copy of a reel exists and returns its download URL.
 * If another instance is rendering it, waits for that instead of rendering twice.
 */
async function ensureBrandedReel(reelId, reel) {
  const { videoUrl, ownerName, ownerPhotoUrl, isMerchant, look } = lookFor(reel);
  if (!/^https?:\/\//i.test(videoUrl)) {
    throw new HttpsError('failed-precondition', 'This video cannot be downloaded.');
  }
  const objectPath = `reel_downloads/${reelId}/${look}.mp4`;
  const bucket = admin.storage().bucket();
  const file = bucket.file(objectPath);

  const ready = await cachedUrl(file, bucket.name, objectPath);
  if (ready) return { url: ready, cached: true };

  if (!(await claimRender(reelId, look))) {
    const until = Date.now() + LOCK_TTL_MS;
    while (Date.now() < until) {
      await sleep(2000);
      const url = await cachedUrl(file, bucket.name, objectPath);
      if (url) return { url, cached: true };
    }
    await claimRender(reelId, look);
  }

  const jobRef = admin.firestore().collection('reel_download_jobs').doc(reelId);
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'reel-'));
  const inputPath = path.join(workDir, 'in.mp4');
  const outputPath = path.join(workDir, 'out.mp4');
  const t0 = Date.now();
  try {
    try {
      await fetchToFile(videoUrl, inputPath, MAX_INPUT_BYTES);
    } catch (e) {
      console.error('brandedReel: fetch failed', reelId, e.message);
      throw new HttpsError('unavailable', 'Could not fetch the video. Try again.');
    }
    const ownerPhoto = await fetchBuffer(ownerPhotoUrl);
    const tFetched = Date.now();
    try {
      await renderBrandedReel({ inputPath, outputPath, workDir, ownerName, ownerPhoto, isMerchant });
    } catch (e) {
      console.error('brandedReel: render failed', reelId, e.message, e.stderr);
      throw new HttpsError('internal', 'Could not prepare the video.');
    }
    const tRendered = Date.now();
    const token = crypto.randomUUID();
    await bucket.upload(outputPath, {
      destination: objectPath,
      resumable: false,
      metadata: {
        contentType: 'video/mp4',
        cacheControl: 'public, max-age=31536000',
        contentDisposition: `attachment; filename="vero360_reel_${reelId}.mp4"`,
        metadata: { firebaseStorageDownloadTokens: token, reelId },
      },
    });
    console.log('brandedReel: done', reelId, {
      fetchMs: tFetched - t0,
      renderMs: tRendered - tFetched,
      uploadMs: Date.now() - tRendered,
    });
    await jobRef.set({ look, status: 'done', doneAt: admin.firestore.FieldValue.serverTimestamp() });
    return { url: downloadUrl(bucket.name, objectPath, token), cached: false };
  } catch (e) {
    await jobRef.set({ look, status: 'failed' }).catch(() => {});
    throw e;
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
  }
}

/**
 * Returns a download URL for a reel with the Vero360 watermark and an end card.
 * Flutter calls: FirebaseFunctions.instance.httpsCallable('prepareReelDownload')
 */
exports.prepareReelDownload = onCall(RENDER_OPTIONS, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to download reels.');
  }
  const reelId = String(request.data?.reelId || '').trim();
  if (!reelId || reelId.includes('/')) {
    throw new HttpsError('invalid-argument', 'Missing reel.');
  }
  const snap = await admin.firestore().collection('reels').doc(reelId).get();
  if (!snap.exists || snap.data()?.hidden === true) {
    throw new HttpsError('not-found', 'This reel is no longer available.');
  }
  return ensureBrandedReel(reelId, snap.data() || {});
});

/** Renders the branded copy as soon as a reel is posted so downloads are instant. */
exports.brandReelOnPost = onDocumentCreated(
  { document: 'reels/{reelId}', ...RENDER_OPTIONS },
  async (event) => {
    const reel = event.data?.data();
    if (!reel || reel.hidden === true) return;
    try {
      await ensureBrandedReel(event.params.reelId, reel);
    } catch (e) {
      console.warn('brandReelOnPost: skipped', event.params.reelId, e.message);
    }
  },
);
