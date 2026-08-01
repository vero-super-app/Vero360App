const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const vision = require('@google-cloud/vision');
const {
  findBlockedTerms,
  findBlockedImageLabels,
  detectCannabisCombo,
} = require('./moderation_blocklist');

if (!admin.apps.length) {
  admin.initializeApp();
}

const ENGAGEMENT_TOPIC = 'vero360_engagement';
const ORDER_PARTY_ALERTS = 'order_party_alerts';
const MAX_GALLERY_IMAGES = 5;
const SAFESEARCH_BLOCK = new Set(['LIKELY', 'VERY_LIKELY']);
// App Engine default SA has Firestore access on Firebase projects; Compute default often does not.
const FUNCTIONS_SERVICE_ACCOUNT =
  'vero360app-ca423@appspot.gserviceaccount.com';

let _visionClient = null;
function getVisionClient() {
  if (!_visionClient) _visionClient = new vision.ImageAnnotatorClient();
  return _visionClient;
}

function listingName(data) {
  return String(data.name || data.title || data.productName || '').trim();
}

function collectImageSources(data) {
  /** @type {{ kind: 'url'|'base64', value: string, key: string }[]} */
  const sources = [];
  const seen = new Set();

  const pushUrl = (v, key) => {
    const u = String(v || '').trim();
    if (!u || !/^https?:\/\//i.test(u) || seen.has(u)) return;
    seen.add(u);
    sources.push({ kind: 'url', value: u, key });
  };

  const pushBase64 = (v, key) => {
    let raw = String(v || '').trim();
    if (!raw || /^https?:\/\//i.test(raw)) return;
    if (raw.includes(',')) raw = raw.split(',').pop().trim();
    // Skip tiny / non-base64 strings
    if (raw.length < 200) return;
    if (!/^[A-Za-z0-9+/=\s]+$/.test(raw)) return;
    const fingerprint = raw.slice(0, 64) + ':' + raw.length;
    if (seen.has(fingerprint)) return;
    seen.add(fingerprint);
    sources.push({ kind: 'base64', value: raw, key });
  };

  pushUrl(data.imageUrl, 'imageUrl');
  pushUrl(data.photo, 'photo');
  pushUrl(data.picture, 'picture');
  pushBase64(data.image, 'image');
  pushBase64(data.photo, 'photo_b64');
  pushBase64(data.picture, 'picture_b64');

  for (const field of ['galleryUrls', 'gallery']) {
    const list = data[field];
    if (!Array.isArray(list)) continue;
    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      const s = String(e || '').trim();
      if (/^https?:\/\//i.test(s)) pushUrl(s, `${field}[${i}]`);
      else pushBase64(s, `${field}[${i}]`);
      if (sources.length >= 1 + MAX_GALLERY_IMAGES) break;
    }
  }
  return sources.slice(0, 1 + MAX_GALLERY_IMAGES);
}

/**
 * SafeSearch (adult/violence/racy) + Label/Object detection (guns, drugs, etc.).
 * @returns {{ blocked: boolean, scores: object, labelHits: object[], error?: string }}
 */
async function checkImagesSafeSearch(sources) {
  const scores = {};
  const labelHits = [];
  if (!sources.length) return { blocked: false, scores, labelHits };

  const client = getVisionClient();
  let blocked = false;
  try {
    for (const src of sources) {
      const image =
        src.kind === 'url'
          ? { source: { imageUri: src.value } }
          : { content: Buffer.from(src.value, 'base64') };

      const [result] = await client.annotateImage({
        image,
        features: [
          { type: 'SAFE_SEARCH_DETECTION' },
          { type: 'LABEL_DETECTION', maxResults: 40 },
          { type: 'OBJECT_LOCALIZATION', maxResults: 20 },
          // Helps catch marijuana/weed product photos via web entities.
          { type: 'WEB_DETECTION', maxResults: 20 },
        ],
      });

      const key = src.kind === 'url' ? src.value : src.key;
      const ann = result.safeSearchAnnotation || {};
      scores[key] = {
        adult: ann.adult || 'UNKNOWN',
        violence: ann.violence || 'UNKNOWN',
        racy: ann.racy || 'UNKNOWN',
        medical: ann.medical || 'UNKNOWN',
        spoof: ann.spoof || 'UNKNOWN',
      };

      if (
        SAFESEARCH_BLOCK.has(scores[key].adult) ||
        SAFESEARCH_BLOCK.has(scores[key].violence) ||
        SAFESEARCH_BLOCK.has(scores[key].racy)
      ) {
        blocked = true;
      }

      const web = result.webDetection || {};
      const webEntities = (web.webEntities || []).map((e) => ({
        description: e.description,
        score: e.score,
      }));
      const bestGuess = (web.bestGuessLabels || []).map((e) => ({
        description: e.label,
        score: 0.85,
      }));

      const labels = [
        ...(result.labelAnnotations || []),
        ...(result.localizedObjectAnnotations || []).map((o) => ({
          description: o.name,
          score: o.score,
        })),
        ...webEntities,
        ...bestGuess,
      ];
      const hits = findBlockedImageLabels(labels);
      // Extra cannabis signal: hemp/plant-like labels often co-occur on weed photos.
      const cannabisCombo = detectCannabisCombo(labels);
      if (cannabisCombo) {
        hits.push(cannabisCombo);
      }
      if (hits.length) {
        blocked = true;
        labelHits.push(
          ...hits.map((h) => ({
            ...h,
            source: key,
          })),
        );
      }
      scores[key].topLabels = labels
        .slice(0, 15)
        .map((l) => ({
          label: String(l.description || l.name || ''),
          score: typeof l.score === 'number' ? Number(l.score.toFixed(3)) : 0,
        }));
    }
    return { blocked, scores, labelHits };
  } catch (err) {
    console.error('Vision image moderation failed', err);
    return {
      blocked: false,
      scores,
      labelHits,
      error: String(err && err.message ? err.message : err),
    };
  }
}

function looksLikeFirebaseUid(v) {
  const s = String(v || '').trim();
  // Firebase Auth UIDs are typically 28 chars [A-Za-z0-9]
  return /^[A-Za-z0-9]{20,128}$/.test(s) && !/^\d+$/.test(s);
}

function resolveMerchantFirebaseUid(data) {
  const candidates = [
    data.firebaseUid,
    data.merchantId,
    data.sellerUserId,
    data.ownerId,
    data.uid,
  ];
  for (const c of candidates) {
    if (looksLikeFirebaseUid(c)) return String(c).trim();
  }
  // Last resort: first non-empty string
  for (const c of candidates) {
    const s = String(c || '').trim();
    if (s) return s;
  }
  return '';
}

function stringifyDataPayload(payload) {
  const out = {};
  if (!payload || typeof payload !== 'object') return out;
  for (const [k, v] of Object.entries(payload)) {
    if (v === undefined || v === null) continue;
    out[String(k)] = String(v);
  }
  return out;
}

async function notifyMerchant(merchantUid, title, body, payload) {
  const uid = String(merchantUid || '').trim();
  if (!uid) {
    console.warn('notifyMerchant skipped: empty merchant uid');
    return;
  }

  const dataPayload = stringifyDataPayload({
    type: 'marketplace_moderation',
    title,
    body,
    ...(payload || {}),
  });

  // 1) In-app queue (works when app is open and listening)
  try {
    await admin.firestore().collection(ORDER_PARTY_ALERTS).add({
      toUid: uid,
      title,
      body,
      payload: dataPayload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      consumed: false,
    });
    console.log(`order_party_alerts written for ${uid}`);
  } catch (err) {
    console.error('Merchant moderation alert (firestore) failed', err);
  }

  // 2) Real FCM push (works in background / killed)
  try {
    const userSnap = await admin.firestore().collection('users').doc(uid).get();
    const udata = userSnap.data() || {};
    const tokens = new Set();
    const single = String(udata.fcmToken || udata.messagingToken || '').trim();
    if (single) tokens.add(single);
    const arr = udata.fcmTokens;
    if (Array.isArray(arr)) {
      for (const t of arr) {
        const s = String(t || '').trim();
        if (s) tokens.add(s);
      }
    }

    if (!tokens.size) {
      console.warn(`No FCM tokens on users/${uid} — push skipped (in-app alert still queued)`);
      return;
    }

    const invalid = [];
    for (const token of tokens) {
      try {
        await admin.messaging().send({
          token,
          notification: { title, body },
          data: dataPayload,
          android: {
            priority: 'high',
            notification: {
              channelId: 'high_importance_channel',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        });
        console.log(`FCM moderation push sent to ${uid}`);
      } catch (err) {
        const code = err && err.code ? String(err.code) : '';
        console.error(`FCM moderation push failed for ${uid}`, code || err);
        if (
          code.includes('registration-token-not-registered') ||
          code.includes('invalid-registration-token') ||
          code.includes('messaging/registration-token-not-registered') ||
          code.includes('messaging/invalid-registration-token')
        ) {
          invalid.push(token);
        }
      }
    }

    if (invalid.length) {
      await admin
        .firestore()
        .collection('users')
        .doc(uid)
        .set(
          {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid),
            ...(invalid.includes(single) ? { fcmToken: admin.firestore.FieldValue.delete() } : {}),
          },
          { merge: true },
        );
    }
  } catch (err) {
    console.error('Merchant moderation FCM path failed', err);
  }
}

/**
 * Auto-moderate a marketplace_items doc. Fail closed on Vision errors.
 * @param {FirebaseFirestore.DocumentSnapshot} snap
 */
async function moderateMarketplaceListing(snap) {
  const data = snap.data() || {};
  const name = listingName(data);
  const description = String(data.description || '').trim();
  const textHits = findBlockedTerms(name, description);
  const imageSources = collectImageSources(data);
  const imageResult = await checkImagesSafeSearch(imageSources);

  const reasons = [];
  if (textHits.length) reasons.push('prohibited_text');
  if (imageResult.blocked) {
    reasons.push(
      imageResult.labelHits && imageResult.labelHits.length
        ? 'prohibited_image_content'
        : 'unsafe_image',
    );
  }

  const checkedAt = admin.firestore.FieldValue.serverTimestamp();
  const moderationBase = {
    source: 'cloud_function',
    reasons,
    checkedAt,
    textHits,
    imageScores: imageResult.scores,
    imageLabelHits: imageResult.labelHits || [],
  };

  // Vision not configured / disabled → continue with text-only (don't strand listings).
  // Transient Vision failures still fail closed (leave pending).
  if (imageResult.error) {
    const errLower = String(imageResult.error).toLowerCase();
    const visionNotReady =
      errLower.includes('has not been used') ||
      errLower.includes('it is disabled') ||
      errLower.includes('vision.googleapis.com') ||
      errLower.includes('api has not been enabled') ||
      errLower.includes('service_disabled');

    if (!visionNotReady) {
      await snap.ref.set(
        {
          reviewStatus: 'pending',
          isActive: false,
          moderation: {
            ...moderationBase,
            reasons: [...reasons, 'vision_error'],
            visionError: imageResult.error,
          },
        },
        { merge: true },
      );
      console.log(`Marketplace item ${snap.id} left pending (vision error)`);
      return { outcome: 'pending' };
    }

    console.warn(
      `Vision unavailable for ${snap.id}; approving/rejecting on text only`,
      imageResult.error,
    );
    moderationBase.reasons = [...reasons, 'vision_skipped'];
    moderationBase.visionError = imageResult.error;
  }

  if (reasons.length) {
    let rejectedReason =
      'Listing images did not pass safety review.';
    if (textHits.length) {
      rejectedReason =
        'Listing text includes content that is not allowed on Vero Marketplace.';
    } else if (imageResult.labelHits && imageResult.labelHits.length) {
      const cats = [
        ...new Set(imageResult.labelHits.map((h) => h.category)),
      ];
      if (cats.includes('weapon')) {
        rejectedReason =
          'Listing images appear to show weapons or related items, which are not allowed.';
      } else if (cats.includes('drugs')) {
        rejectedReason =
          'Listing images appear to show drugs or related items, which are not allowed.';
      } else {
        rejectedReason =
          'Listing images include content that is not allowed on Vero Marketplace.';
      }
    }
    await snap.ref.set(
      {
        reviewStatus: 'rejected',
        isActive: false,
        rejectedReason,
        rejectedAt: checkedAt,
        moderation: moderationBase,
      },
      { merge: true },
    );
    await notifyMerchant(
      resolveMerchantFirebaseUid(data),
      'Listing not approved',
      rejectedReason,
      {
        type: 'marketplace_moderation',
        status: 'rejected',
        marketplaceItemId: snap.id,
      },
    );
    console.log(`Marketplace item ${snap.id} rejected: ${reasons.join(',')}`);
    return { outcome: 'rejected' };
  }

  await snap.ref.set(
    {
      reviewStatus: 'approved',
      isActive: true,
      approvedAt: checkedAt,
      rejectedReason: admin.firestore.FieldValue.delete(),
      moderation: moderationBase,
    },
    { merge: true },
  );
  const itemLabel = name || 'Your product';
  await notifyMerchant(
    resolveMerchantFirebaseUid(data),
    'Your listing is live on Vero Marketplace',
    `${itemLabel} has been approved and is now visible to buyers.`,
    {
      type: 'marketplace_moderation',
      status: 'approved',
      marketplaceItemId: snap.id,
    },
  );
  console.log(`Marketplace item ${snap.id} approved`);
  return { outcome: 'approved' };
}

async function sendMarketplaceAudiencePush(itemId, name) {
  const cooldownRef = admin
    .firestore()
    .collection('engagement_meta')
    .doc('cooldowns');
  const meta = await cooldownRef.get();
  const lastMs = Number((meta.data() || {}).marketplace || 0);
  const COOLDOWN_MS = 15 * 60 * 1000;
  const nowMs = Date.now();
  if (lastMs > 0 && nowMs - lastMs < COOLDOWN_MS) {
    console.log('Marketplace engagement push skipped (cooldown)');
    return;
  }
  await cooldownRef.set({ marketplace: nowMs }, { merge: true });

  const title = 'New on Marketplace';
  const body =
    name.length > 0
      ? `Just listed: ${name}. Open Vero360 to browse.`
      : 'New listings just went live. Open Vero360 to browse.';

  const dataPayload = {
    type: 'marketplace_digest',
    title,
    body,
  };
  if (itemId) dataPayload.marketplaceItemId = itemId;

  await admin.messaging().send({
    topic: ENGAGEMENT_TOPIC,
    notification: { title, body },
    data: dataPayload,
    android: {
      priority: 'normal',
      notification: {
        channelId: 'high_importance_channel',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  });

  console.log(`Marketplace engagement push sent: ${name || itemId}`);
}

/**
 * Updates a Firebase Auth password after the user verified OTP in the app.
 * Deploy: firebase deploy --only functions:resetPasswordAfterOtp
 */
exports.resetPasswordAfterOtp = onCall(async (request) => {
  const data = request.data || {};
  const authEmail = typeof data.authEmail === 'string' ? data.authEmail.trim() : '';
  const newPassword =
    typeof data.newPassword === 'string' ? data.newPassword : '';
  const verificationTicket =
    typeof data.verificationTicket === 'string'
      ? data.verificationTicket.trim()
      : '';

  if (!authEmail) {
    throw new HttpsError('invalid-argument', 'Email is required.');
  }
  if (!newPassword || newPassword.length < 6) {
    throw new HttpsError(
      'invalid-argument',
      'Password must be at least 6 characters.',
    );
  }
  if (!verificationTicket || verificationTicket.length < 8) {
    throw new HttpsError('invalid-argument', 'Invalid verification.');
  }

  try {
    const user = await admin.auth().getUserByEmail(authEmail);
    await admin.auth().updateUser(user.uid, { password: newPassword });
    return { success: true };
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'No account found for this email.');
    }
    throw new HttpsError('internal', 'Failed to reset password.');
  }
});

/**
 * Frequent keep-alive digest for users subscribed to FCM topic
 * `vero360_engagement` (app opts in via Settings → Deals & new listings).
 *
 * Schedule: every 3 hours during the day (08,11,14,17,20) Africa/Blantyre.
 * Also fires when a marketplace listing becomes approved/live
 * (see onMarketplaceItemUpdated) and on docs written to engagement_broadcasts.
 *
 * Deploy: firebase deploy --only functions:sendEngagementDigest,functions:onEngagementBroadcast,functions:onMarketplaceItemCreated,functions:onMarketplaceItemUpdated
 */
exports.sendEngagementDigest = onSchedule(
  {
    schedule: '0 8,11,14,17,20 * * *',
    timeZone: 'Africa/Blantyre',
    retryCount: 1,
  },
  async () => {
    const since = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 4 * 60 * 60 * 1000),
    );

    let marketCount = 0;
    let sampleName = '';
    let sampleId = '';
    try {
      const snap = await admin
        .firestore()
        .collection('marketplace_items')
        .where('createdAt', '>', since)
        .orderBy('createdAt', 'desc')
        .limit(24)
        .get();
      const live = snap.docs.filter((d) => {
        const data = d.data() || {};
        if (data.isActive === false) return false;
        const rs = String(data.reviewStatus || '').toLowerCase();
        if (rs === 'pending' || rs === 'rejected') return false;
        return true;
      });
      marketCount = live.length;
      if (live.length) {
        sampleId = live[0].id;
        const d = live[0].data() || {};
        sampleName = String(d.name || d.title || d.productName || '').trim();
      }
    } catch (err) {
      console.warn('Engagement digest marketplace query failed', err);
    }

    // Skip quiet windows — don't spam when nothing is new.
    if (marketCount <= 0) {
      console.log('Engagement digest skipped (no new marketplace items).');
      return;
    }

    const title = 'New on Vero360 Marketplace';
    const body =
      sampleName.length > 0
        ? `Just listed: ${sampleName}${
            marketCount > 1 ? ` +${marketCount - 1} more` : ''
          }. Open the app to browse.`
        : `${marketCount} new listing${
            marketCount === 1 ? '' : 's'
          } recently. Open Vero360 to check them out.`;

    const dataPayload = {
      type: 'marketplace_digest',
      title,
      body,
    };
    if (sampleId) dataPayload.marketplaceItemId = sampleId;

    await admin.messaging().send({
      topic: ENGAGEMENT_TOPIC,
      notification: { title, body },
      data: dataPayload,
      android: {
        priority: 'normal',
        notification: {
          channelId: 'high_importance_channel',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    });

    console.log(`Engagement digest sent (${marketCount} marketplace items).`);
  },
);

/**
 * Auto-moderate new marketplace listings (text blocklist + Vision SafeSearch).
 * Does NOT send public engagement — that runs after approval (onUpdate).
 */
exports.onMarketplaceItemCreated = onDocumentCreated(
  {
    document: 'marketplace_items/{id}',
    // Vision API needs longer timeout / memory headroom.
    timeoutSeconds: 120,
    memory: '512MiB',
    serviceAccount: FUNCTIONS_SERVICE_ACCOUNT,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    try {
      await moderateMarketplaceListing(snap);
    } catch (err) {
      console.error('onMarketplaceItemCreated moderation failed', err);
      try {
        await snap.ref.set(
          {
            reviewStatus: 'pending',
            isActive: false,
            moderation: {
              source: 'cloud_function',
              reasons: ['moderation_error'],
              checkedAt: admin.firestore.FieldValue.serverTimestamp(),
              error: String(err && err.message ? err.message : err),
            },
          },
          { merge: true },
        );
      } catch (_) {}
    }
  },
);

/**
 * When a listing becomes approved + live → audience engagement push.
 * When reviewStatus returns to pending (merchant resubmit) → re-moderate.
 */
exports.onMarketplaceItemUpdated = onDocumentUpdated(
  {
    document: 'marketplace_items/{id}',
    timeoutSeconds: 120,
    memory: '512MiB',
    serviceAccount: FUNCTIONS_SERVICE_ACCOUNT,
  },
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap) return;

    const beforeStatus = String(before.reviewStatus || '')
      .trim()
      .toLowerCase();
    const afterStatus = String(after.reviewStatus || '')
      .trim()
      .toLowerCase();

    // Re-moderate only when status transitions into pending (resubmit).
    if (afterStatus === 'pending' && beforeStatus !== 'pending') {
      try {
        await moderateMarketplaceListing(afterSnap);
      } catch (err) {
        console.error('onMarketplaceItemUpdated re-moderation failed', err);
      }
      return;
    }

    const becameLive =
      afterStatus === 'approved' &&
      after.isActive === true &&
      !(beforeStatus === 'approved' && before.isActive === true);

    if (!becameLive) return;

    const name = listingName(after);
    const itemId = String(event.params.id || '').trim();
    try {
      await sendMarketplaceAudiencePush(itemId, name);
    } catch (err) {
      console.error('Marketplace audience push failed', err);
    }
  },
);

/**
 * Manual / admin / app broadcast for a promo, arrival, or campaign.
 * Write a doc to Firestore `engagement_broadcasts` with:
 *   { title, body, type?: 'promo_digest'|'arrivals_digest'|'marketplace_digest'|'engagement',
 *     badgeRoute?: 'quick_promotions'|'quick_post_arrival' }
 *
 * Deploy: firebase deploy --only functions:onEngagementBroadcast
 */
exports.onEngagementBroadcast = onDocumentCreated(
  'engagement_broadcasts/{id}',
  async (event) => {
    const data = event.data?.data() || {};
    const title = String(data.title || 'Vero360').trim() || 'Vero360';
    const body =
      String(data.body || 'Something new is waiting for you on Vero360.').trim();
    const type = String(data.type || 'engagement').trim() || 'engagement';
    const badgeRoute = String(data.badgeRoute || '').trim();

    const payload = {
      type,
      title,
      body,
    };
    if (badgeRoute) payload.badgeRoute = badgeRoute;
    // Deep-link ids (all FCM data values must be strings).
    for (const key of ['promoId', 'arrivalId', 'marketplaceItemId', 'itemId', 'id']) {
      const v = data[key];
      if (v !== undefined && v !== null && String(v).trim()) {
        payload[key] = String(v).trim();
      }
    }

    await admin.messaging().send({
      topic: ENGAGEMENT_TOPIC,
      notification: { title, body },
      data: payload,
      android: {
        priority: 'normal',
        notification: {
          channelId: 'high_importance_channel',
        },
      },
    });

    await event.data.ref.set(
      {
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        sent: true,
      },
      { merge: true },
    );

    console.log(`Engagement broadcast sent: ${title}`);
  },
);

/**
 * Taobao / Idle Fish style photo scan for marketplace search.
 * Runs Google Cloud Vision (labels, objects, logos, OCR, web entities)
 * and returns ranked search terms the app uses to match listings.
 *
 * Deploy: firebase deploy --only functions:scanMarketplacePhoto
 */
const PHOTO_SCAN_STOP = new Set([
  'product',
  'products',
  'goods',
  'item',
  'items',
  'merchandise',
  'object',
  'objects',
  'thing',
  'device',
  'gadget',
  'technology',
  'electronic device',
  'electronics',
  'clothing',
  'fashion',
  'apparel',
  'textile',
  'fabric',
  'material',
  'pattern',
  'design',
  'art',
  'photography',
  'photo',
  'image',
  'picture',
  'screenshot',
  'font',
  'text',
  'line',
  'symbol',
  'logo',
  'brand',
  'company',
  'person',
  'people',
  'human',
  'hand',
  'finger',
  'skin',
  'outdoor',
  'indoor',
  'room',
  'floor',
  'wall',
  'ceiling',
  'furniture',
  'tableware',
  'food',
  'drink',
  'beverage',
]);

function normalizeVisionPhrase(raw) {
  return String(raw || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s+\-&.]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function isUsefulVisionPhrase(phrase) {
  if (!phrase || phrase.length < 3) return false;
  if (PHOTO_SCAN_STOP.has(phrase)) return false;
  // Drop ultra-generic single words that rarely help shopping search.
  if (
    phrase.split(' ').length === 1 &&
    ['white', 'black', 'red', 'blue', 'green', 'yellow', 'brown', 'grey', 'gray'].includes(
      phrase,
    )
  ) {
    return false;
  }
  return true;
}

function pushWeightedTerm(map, phrase, weight) {
  const p = normalizeVisionPhrase(phrase);
  if (!isUsefulVisionPhrase(p)) return;
  const prev = map.get(p) || 0;
  if (weight > prev) map.set(p, weight);
  // Also index meaningful tokens from multi-word phrases.
  for (const part of p.split(' ')) {
    if (part.length < 4 || PHOTO_SCAN_STOP.has(part)) continue;
    const w = Math.max(1, Math.floor(weight * 0.6));
    const cur = map.get(part) || 0;
    if (w > cur) map.set(part, w);
  }
}

exports.scanMarketplacePhoto = onCall(
  {
    timeoutSeconds: 60,
    memory: '512MiB',
    serviceAccount: FUNCTIONS_SERVICE_ACCOUNT,
  },
  async (request) => {
    const data = request.data || {};
    let imageBase64 =
      typeof data.imageBase64 === 'string' ? data.imageBase64.trim() : '';
    if (!imageBase64) {
      throw new HttpsError('invalid-argument', 'imageBase64 is required.');
    }
    if (imageBase64.includes(',')) {
      imageBase64 = imageBase64.split(',').pop().trim();
    }

    let buf;
    try {
      buf = Buffer.from(imageBase64, 'base64');
    } catch (_) {
      throw new HttpsError('invalid-argument', 'Invalid image data.');
    }
    if (!buf || buf.length < 200) {
      throw new HttpsError('invalid-argument', 'Image too small.');
    }
    if (buf.length > 4 * 1024 * 1024) {
      throw new HttpsError('invalid-argument', 'Image too large (max 4MB).');
    }

    const client = getVisionClient();
    let result;
    try {
      [result] = await client.annotateImage({
        image: { content: buf.toString('base64') },
        features: [
          { type: 'LABEL_DETECTION', maxResults: 25 },
          { type: 'OBJECT_LOCALIZATION', maxResults: 15 },
          { type: 'LOGO_DETECTION', maxResults: 10 },
          { type: 'TEXT_DETECTION', maxResults: 15 },
          { type: 'WEB_DETECTION', maxResults: 15 },
        ],
      });
    } catch (err) {
      console.error('scanMarketplacePhoto Vision failed', err);
      throw new HttpsError(
        'internal',
        'Photo scan failed. Please try again.',
      );
    }

    /** @type {Map<string, number>} */
    const weighted = new Map();

    for (const l of result.labelAnnotations || []) {
      const score = typeof l.score === 'number' ? l.score : 0;
      if (score < 0.55) continue;
      pushWeightedTerm(weighted, l.description, score >= 0.75 ? 4 : 3);
    }

    for (const o of result.localizedObjectAnnotations || []) {
      const score = typeof o.score === 'number' ? o.score : 0;
      if (score < 0.45) continue;
      pushWeightedTerm(weighted, o.name, 5);
    }

    for (const logo of result.logoAnnotations || []) {
      const score = typeof logo.score === 'number' ? logo.score : 0;
      if (score < 0.4) continue;
      pushWeightedTerm(weighted, logo.description, 6);
    }

    const texts = result.textAnnotations || [];
    if (texts.length) {
      // First annotation is the full block; following are words/lines.
      const full = normalizeVisionPhrase(texts[0].description || '');
      if (full && full.length <= 80) {
        pushWeightedTerm(weighted, full, 5);
      }
      for (let i = 1; i < Math.min(texts.length, 20); i++) {
        const t = normalizeVisionPhrase(texts[i].description || '');
        if (t.length >= 3 && t.length <= 32) {
          pushWeightedTerm(weighted, t, 4);
        }
      }
    }

    const web = result.webDetection || {};
    for (const g of web.bestGuessLabels || []) {
      pushWeightedTerm(weighted, g.label, 5);
    }
    for (const e of web.webEntities || []) {
      const score = typeof e.score === 'number' ? e.score : 0;
      if (score < 0.35) continue;
      pushWeightedTerm(weighted, e.description, score >= 0.6 ? 4 : 3);
    }

    const terms = [...weighted.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 30)
      .map(([term, weight]) => ({ term, weight }));

    const queries = terms
      .filter((t) => t.weight >= 3)
      .slice(0, 12)
      .map((t) => t.term);

    console.log(
      `scanMarketplacePhoto: ${terms.length} terms, top=${queries.slice(0, 5).join(', ')}`,
    );

    return {
      queries,
      terms,
      labels: (result.labelAnnotations || [])
        .slice(0, 12)
        .map((l) => ({
          description: String(l.description || ''),
          score: typeof l.score === 'number' ? Number(l.score.toFixed(3)) : 0,
        })),
      objects: (result.localizedObjectAnnotations || [])
        .slice(0, 10)
        .map((o) => ({
          name: String(o.name || ''),
          score: typeof o.score === 'number' ? Number(o.score.toFixed(3)) : 0,
        })),
      logos: (result.logoAnnotations || [])
        .slice(0, 8)
        .map((l) => ({
          description: String(l.description || ''),
          score: typeof l.score === 'number' ? Number(l.score.toFixed(3)) : 0,
        })),
      bestGuess: (web.bestGuessLabels || [])
        .slice(0, 5)
        .map((g) => String(g.label || '')),
    };
  },
);


