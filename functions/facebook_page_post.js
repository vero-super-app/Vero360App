/**
 * Post vero360.app listing links to the Vero360 Facebook Page when listings go live.
 *
 * Secrets (Firebase):
 *   firebase functions:secrets:set FACEBOOK_PAGE_ACCESS_TOKEN
 *   firebase functions:secrets:set FACEBOOK_PAGE_ID
 *     value: 1146056985268073
 *
 * Token must include pages_manage_posts + pages_read_engagement (Page token from /me/accounts).
 *
 * Deploy:
 *   firebase deploy --only functions:onMarketplaceItemFacebookPost,functions:onFoodMenuItemFacebookPost,functions:onAccommodationFacebookPost,functions:onAccommodationRoomFacebookPost,functions:onMarketplaceItemCreated,functions:onMarketplaceItemUpdated
 */

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const FACEBOOK_PAGE_ACCESS_TOKEN = defineSecret('FACEBOOK_PAGE_ACCESS_TOKEN');
const FACEBOOK_PAGE_ID = defineSecret('FACEBOOK_PAGE_ID');

const DEFAULT_PAGE_ID = '1146056985268073';
const GRAPH_VERSION = 'v26.0';
/** Same SA as other Vero functions — Compute default often cannot write Firestore. */
const FUNCTIONS_SERVICE_ACCOUNT =
  'vero360app-ca423@appspot.gserviceaccount.com';

function listingTitle(data) {
  return String(
    data.name || data.title || data.FoodName || data.productName || 'New listing',
  ).trim();
}

function firstHttpImage(data) {
  const keys = [
    'imageUrl',
    'image',
    'FoodImage',
    'photo',
    'coverImage',
    'coverImageUrl',
  ];
  for (const k of keys) {
    const v = String(data[k] || '').trim();
    if (/^https?:\/\//i.test(v) && !v.startsWith('data:')) return v;
  }
  for (const field of ['gallery', 'galleryUrls', 'images']) {
    const list = data[field];
    if (!Array.isArray(list)) continue;
    for (const e of list) {
      const v = String(e || '').trim();
      if (/^https?:\/\//i.test(v) && !v.startsWith('data:')) return v;
    }
  }
  return '';
}

function marketplaceShareUrl(id, data) {
  const params = new URLSearchParams();
  const name = listingTitle(data);
  const loc = String(data.location || '').trim();
  const price = data.price != null ? String(data.price) : '';
  const merchant = String(
    data.merchantName || data.sellerBusinessName || data.businessName || '',
  ).trim();
  const img = firstHttpImage(data);
  if (name) params.set('name', name);
  if (loc) params.set('loc', loc);
  if (price) params.set('price', price);
  if (merchant) params.set('merchant', merchant);
  if (img) params.set('img', img);
  const q = [name, loc].filter(Boolean).join(' ');
  if (q) params.set('q', q);
  const qs = params.toString();
  return `https://vero360.app/marketplace/${encodeURIComponent(id)}${qs ? `?${qs}` : ''}`;
}

function foodShareUrl(id, data) {
  const params = new URLSearchParams();
  const name = listingTitle(data);
  const merchant = String(
    data.RestrauntName || data.restaurantName || data.merchantName || '',
  ).trim();
  const price = data.price != null ? String(data.price) : '';
  const img = firstHttpImage(data);
  if (name) params.set('name', name);
  if (merchant) params.set('merchant', merchant);
  if (price) params.set('price', price);
  if (img) params.set('img', img);
  const qs = params.toString();
  return `https://vero360.app/food/${encodeURIComponent(id)}${qs ? `?${qs}` : ''}`;
}

function accommodationShareUrl(id, data) {
  const params = new URLSearchParams();
  const name = listingTitle(data);
  const loc = String(data.location || '').trim();
  const price =
    data.price != null
      ? String(data.price)
      : data.pricePerNight != null
        ? String(data.pricePerNight)
        : '';
  const img = firstHttpImage(data);
  if (name) params.set('name', name);
  if (loc) params.set('loc', loc);
  if (price) params.set('price', price);
  if (img) params.set('img', img);
  const q = [name, loc].filter(Boolean).join(' ');
  if (q) params.set('q', q);
  const qs = params.toString();
  return `https://vero360.app/accommodation/${encodeURIComponent(id)}${qs ? `?${qs}` : ''}`;
}

function isLiveMarketplace(data) {
  const status = String(data.reviewStatus || '')
    .trim()
    .toLowerCase();
  if (status === 'approved') return data.isActive === true;
  if (!status) return data.isActive === true;
  return false;
}

function becameLiveMarketplace(before, after) {
  if (!isLiveMarketplace(after)) return false;
  if (after.facebookPostId || after.facebookPostedAt) return false;
  return !isLiveMarketplace(before);
}

function isPublicFood(data) {
  if (data.isActive === false) return false;
  if (data.hidden === true || data.deleted === true) return false;
  const status = String(data.reviewStatus || data.status || '')
    .trim()
    .toLowerCase();
  if (status === 'pending' || status === 'rejected' || status === 'draft') {
    return false;
  }
  return true;
}

function becamePublicFood(before, after) {
  if (!isPublicFood(after)) return false;
  if (after.facebookPostId || after.facebookPostedAt) return false;
  return !isPublicFood(before || {});
}

function isPublicAccommodation(data) {
  if (data.isActive === false || data.published === false) return false;
  if (data.hidden === true || data.deleted === true) return false;
  const status = String(data.reviewStatus || data.status || '')
    .trim()
    .toLowerCase();
  if (status === 'pending' || status === 'rejected' || status === 'draft') {
    return false;
  }
  return true;
}

function becamePublicAccommodation(before, after) {
  if (!isPublicAccommodation(after)) return false;
  if (after.facebookPostId || after.facebookPostedAt) return false;
  return !isPublicAccommodation(before || {});
}

function resolvePageCredentials(tokenOverride, pageIdOverride) {
  let token = String(tokenOverride || '').trim();
  let pageId = String(pageIdOverride || '').trim() || DEFAULT_PAGE_ID;
  if (!token) {
    try {
      token = String(FACEBOOK_PAGE_ACCESS_TOKEN.value() || '').trim();
    } catch (_) {
      token = String(process.env.FACEBOOK_PAGE_ACCESS_TOKEN || '').trim();
    }
  }
  if (!pageId || pageId === DEFAULT_PAGE_ID) {
    try {
      pageId =
        String(FACEBOOK_PAGE_ID.value() || '').trim() || DEFAULT_PAGE_ID;
    } catch (_) {
      pageId =
        String(process.env.FACEBOOK_PAGE_ID || '').trim() || DEFAULT_PAGE_ID;
    }
  }
  return { token, pageId };
}

async function graphPost(path, fields) {
  const url = `https://graph.facebook.com/${GRAPH_VERSION}/${path}`;
  const body = new URLSearchParams();
  for (const [k, v] of Object.entries(fields)) {
    if (v == null) continue;
    const s = String(v).trim();
    if (!s) continue;
    body.set(k, s);
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, json };
}

async function scrapeFacebookUrl(link, token) {
  const access = String(token || '').trim();
  const url = String(link || '').trim();
  if (!access || !url) return;
  try {
    // Warm Facebook's link preview cache so the card shows our OG image.
    await graphPost('', {
      id: url,
      scrape: 'true',
      access_token: access,
    });
  } catch (err) {
    console.warn(
      'Facebook scrape warning',
      err && err.message ? err.message : err,
    );
  }
}

async function postLinkToFacebookPage({ link, message, pageId, token }) {
  const pid = String(pageId || DEFAULT_PAGE_ID).trim() || DEFAULT_PAGE_ID;
  const access = String(token || '').trim();
  if (!access) {
    console.warn(
      'Facebook Page post skipped: FACEBOOK_PAGE_ACCESS_TOKEN not set (len=0)',
    );
    return null;
  }

  await scrapeFacebookUrl(link, access);

  const { ok, status, json } = await graphPost(
    `${encodeURIComponent(pid)}/feed`,
    {
      access_token: access,
      link,
      message,
      published: 'true',
    },
  );
  if (!ok) {
    console.error('Facebook Graph link post failed', status, json);
    throw new Error(
      `Facebook Graph error ${status}: ${JSON.stringify(json)}`,
    );
  }
  return json && json.id ? String(json.id) : null;
}

/**
 * Prefer a photo post (shows the product image on the Page) with caption + link.
 * Falls back to a plain link post when no public image URL is available.
 */
async function postPhotoToFacebookPage({
  imageUrl,
  caption,
  pageId,
  token,
}) {
  const pid = String(pageId || DEFAULT_PAGE_ID).trim() || DEFAULT_PAGE_ID;
  const access = String(token || '').trim();
  const img = String(imageUrl || '').trim();
  if (!access || !img || !/^https?:\/\//i.test(img)) return null;

  const { ok, status, json } = await graphPost(
    `${encodeURIComponent(pid)}/photos`,
    {
      access_token: access,
      url: img,
      caption,
      published: 'true',
    },
  );
  if (!ok) {
    console.warn('Facebook Graph photo post failed', status, json);
    return null;
  }
  // Photo posts return { id: "<photo_id>", post_id: "<pageId_postId>" }
  if (json && json.post_id) return String(json.post_id);
  if (json && json.id) return String(json.id);
  return null;
}

async function claimFacebookPostSlot(ref) {
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const data = snap.data() || {};
    if (data.facebookPostId || data.facebookPostedAt) return false;
    // Soft claim so concurrent CF triggers don't double-post.
    if (data.facebookPostClaimAt) {
      const claimed = data.facebookPostClaimAt;
      const ms =
        claimed && typeof claimed.toMillis === 'function'
          ? claimed.toMillis()
          : Number(claimed) || 0;
      // Allow retry if claim is older than 3 minutes (failed previous attempt).
      if (ms > 0 && Date.now() - ms < 3 * 60 * 1000) return false;
    }
    tx.set(
      ref,
      {
        facebookPostClaimAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return true;
  });
}

async function clearFacebookPostClaim(ref) {
  try {
    await ref.set(
      { facebookPostClaimAt: admin.firestore.FieldValue.delete() },
      { merge: true },
    );
  } catch (_) {}
}

async function markPosted(ref, postId) {
  const id = String(postId || '').trim();
  if (!id) return;
  await ref.set(
    {
      facebookPostId: id,
      facebookPostedAt: admin.firestore.FieldValue.serverTimestamp(),
      facebookPostClaimAt: admin.firestore.FieldValue.delete(),
    },
    { merge: true },
  );
}

async function handleFacebookPost({
  before,
  after,
  afterSnap,
  docId,
  kind,
  token,
  pageId,
  isCreate = false,
}) {
  if (!afterSnap) return;

  let shouldPost = false;
  let link = '';
  let message = '';

  if (kind === 'marketplace') {
    shouldPost = isCreate
      ? isLiveMarketplace(after) &&
        !after.facebookPostId &&
        !after.facebookPostedAt
      : becameLiveMarketplace(before, after);
    link = marketplaceShareUrl(docId, after);
    const price =
      after.price != null
        ? ` — MWK ${Number(after.price).toLocaleString('en-US')}`
        : '';
    // Keep the URL out of the message — Facebook attaches a clickable image card via `link`.
    message = `New on Vero360 Marketplace: ${listingTitle(after)}${price}`;
  } else if (kind === 'food') {
    shouldPost = isCreate
      ? isPublicFood(after) && !after.facebookPostId && !after.facebookPostedAt
      : becamePublicFood(before, after);
    link = foodShareUrl(docId, after);
    message = `New dish on Vero360: ${listingTitle(after)}`;
  } else if (kind === 'accommodation') {
    shouldPost = isCreate
      ? isPublicAccommodation(after) &&
        !after.facebookPostId &&
        !after.facebookPostedAt
      : becamePublicAccommodation(before, after);
    link = accommodationShareUrl(docId, after);
    message = `New stay on Vero360: ${listingTitle(after)}`;
  }

  if (!shouldPost) {
    console.log(`Facebook Page post not needed (${kind})`, docId, {
      isCreate,
      reviewStatus: after.reviewStatus || after.status || null,
      isActive: after.isActive,
      alreadyPosted: Boolean(after.facebookPostId || after.facebookPostedAt),
    });
    return;
  }

  const creds = resolvePageCredentials(token, pageId);
  const access = creds.token;
  const resolvedPageId = creds.pageId;
  if (!access) {
    console.warn(
      `Facebook Page post aborted (${kind}) ${docId}: missing page access token`,
    );
    return;
  }

  let claimed = false;
  try {
    claimed = await claimFacebookPostSlot(afterSnap.ref);
  } catch (claimErr) {
    console.error(
      `Facebook claim failed (${kind})`,
      docId,
      claimErr && claimErr.message ? claimErr.message : claimErr,
    );
    // Still attempt Graph post — better a rare double-post than silent failure.
    claimed = true;
  }
  if (!claimed) {
    console.log(
      `Facebook Page post skipped (already claimed/posted) (${kind})`,
      docId,
    );
    return;
  }

  try {
    const imageUrl = firstHttpImage(after);
    // Prefer a link card (embedded image preview + click opens Vero360).
    // Plain photo posts open Facebook's photo viewer instead of our listing URL.
    let postId = await postLinkToFacebookPage({
      link,
      message,
      pageId: resolvedPageId,
      token: access,
    });
    if (!postId && imageUrl) {
      postId = await postPhotoToFacebookPage({
        imageUrl,
        caption: `${message}\n${link}`,
        pageId: resolvedPageId,
        token: access,
      });
    }
    // Never stamp facebookPostedAt without a real Graph post id — that permanently
    // blocks retries after auto-moderation when the token was missing or Graph
    // returned an empty body.
    if (!postId) {
      console.warn(
        `Facebook Page post skipped / no id (${kind})`,
        docId,
        '— not marking as posted',
      );
      await clearFacebookPostClaim(afterSnap.ref);
      return;
    }
    await markPosted(afterSnap.ref, postId);
    console.log(`Facebook Page post ok (${kind})`, docId, postId);
  } catch (err) {
    await clearFacebookPostClaim(afterSnap.ref);
    throw err;
  }
}

/**
 * Call from other Cloud Functions (e.g. marketplace became-live) that declare
 * the FACEBOOK_* secrets on their own options.
 */
async function tryPostFromEvent({
  before,
  after,
  afterSnap,
  docId,
  kind,
  isCreate = false,
}) {
  const { token, pageId } = resolvePageCredentials();
  await handleFacebookPost({
    before,
    after,
    afterSnap,
    docId,
    kind,
    token,
    pageId,
    isCreate,
  });
}

exports.tryPostFromEvent = tryPostFromEvent;
exports.FACEBOOK_PAGE_ACCESS_TOKEN = FACEBOOK_PAGE_ACCESS_TOKEN;
exports.FACEBOOK_PAGE_ID = FACEBOOK_PAGE_ID;

const firestoreOpts = {
  timeoutSeconds: 60,
  memory: '256MiB',
  serviceAccount: FUNCTIONS_SERVICE_ACCOUNT,
  secrets: [FACEBOOK_PAGE_ACCESS_TOKEN, FACEBOOK_PAGE_ID],
};

exports.onMarketplaceItemFacebookPost = onDocumentWritten(
  {
    document: 'marketplace_items/{id}',
    ...firestoreOpts,
  },
  async (event) => {
    const isCreate = !event.data?.before?.exists;
    const before = event.data?.before?.exists
      ? event.data.before.data() || {}
      : {};
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;
    try {
      const { token, pageId } = resolvePageCredentials();
      await handleFacebookPost({
        before,
        after,
        afterSnap,
        docId: String(event.params.id || '').trim(),
        kind: 'marketplace',
        token,
        pageId,
        isCreate,
      });
    } catch (err) {
      console.error('onMarketplaceItemFacebookPost failed', err);
    }
  },
);

exports.onFoodMenuItemFacebookPost = onDocumentWritten(
  {
    document: 'food_menu_items/{id}',
    ...firestoreOpts,
  },
  async (event) => {
    const isCreate = !event.data?.before?.exists;
    const before = event.data?.before?.exists
      ? event.data.before.data() || {}
      : {};
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;
    try {
      const { token, pageId } = resolvePageCredentials();
      await handleFacebookPost({
        before,
        after,
        afterSnap,
        docId: String(event.params.id || '').trim(),
        kind: 'food',
        token,
        pageId,
        isCreate,
      });
    } catch (err) {
      console.error('onFoodMenuItemFacebookPost failed', err);
    }
  },
);

exports.onAccommodationFacebookPost = onDocumentWritten(
  {
    document: 'accommodations/{id}',
    ...firestoreOpts,
  },
  async (event) => {
    const isCreate = !event.data?.before?.exists;
    const before = event.data?.before?.exists
      ? event.data.before.data() || {}
      : {};
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;
    try {
      const { token, pageId } = resolvePageCredentials();
      await handleFacebookPost({
        before,
        after,
        afterSnap,
        docId: String(event.params.id || after.id || '').trim(),
        kind: 'accommodation',
        token,
        pageId,
        isCreate,
      });
    } catch (err) {
      console.error('onAccommodationFacebookPost failed', err);
    }
  },
);

/** Merchant app writes stays to `accommodation_rooms`. */
exports.onAccommodationRoomFacebookPost = onDocumentWritten(
  {
    document: 'accommodation_rooms/{id}',
    ...firestoreOpts,
  },
  async (event) => {
    const isCreate = !event.data?.before?.exists;
    const before = event.data?.before?.exists
      ? event.data.before.data() || {}
      : {};
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;
    try {
      const { token, pageId } = resolvePageCredentials();
      await handleFacebookPost({
        before,
        after,
        afterSnap,
        docId: String(event.params.id || after.id || '').trim(),
        kind: 'accommodation',
        token,
        pageId,
        isCreate,
      });
    } catch (err) {
      console.error('onAccommodationRoomFacebookPost failed', err);
    }
  },
);
