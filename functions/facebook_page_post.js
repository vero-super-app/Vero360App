/**
 * Post vero360.app listing links to the Vero360 Facebook Page when listings go live.
 *
 * Secrets (Firebase):
 *   firebase functions:secrets:set FACEBOOK_PAGE_ACCESS_TOKEN
 *   firebase functions:secrets:set FACEBOOK_PAGE_ID
 *     value: 1146056985268073
 *
 * ---------------------------------------------------------------------------
 * NEVER-EXPIRE PAGE TOKEN (do this once — do NOT use Graph Explorer "User" token)
 * ---------------------------------------------------------------------------
 * Short-lived Explorer tokens expire in ~1–2 hours. A Page token minted from a
 * long-lived User token does not expire (until password change / app revoke /
 * secret rotation).
 *
 * 1) Meta App Dashboard → your app → copy App ID + App Secret
 * 2) Graph API Explorer:
 *      - User or Page = your user
 *      - Permissions: pages_show_list, pages_manage_posts, pages_read_engagement,
 *        pages_manage_metadata (optional), business_management (if required)
 *      - Generate short-lived User access token → copy it (USER_SHORT)
 * 3) Exchange for long-lived User token (~60 days):
 *      GET https://graph.facebook.com/v22.0/oauth/access_token
 *        ?grant_type=fb_exchange_token
 *        &client_id=APP_ID
 *        &client_secret=APP_SECRET
 *        &fb_exchange_token=USER_SHORT
 *      → copy access_token (USER_LONG)
 * 4) Mint the permanent Page token:
 *      GET https://graph.facebook.com/v22.0/me/accounts
 *        ?access_token=USER_LONG
 *      → find Page id 1146056985268073 → copy that object's access_token
 *        (this Page token is the never-expire one)
 * 5) Optional check (should show expires_at: 0):
 *      GET https://graph.facebook.com/v22.0/debug_token
 *        ?input_token=PAGE_TOKEN
 *        &access_token=APP_ID|APP_SECRET
 * 6) Save + redeploy:
 *      firebase functions:secrets:set FACEBOOK_PAGE_ACCESS_TOKEN
 *      firebase deploy --only functions:onMarketplaceItemFacebookPost,functions:onFoodMenuItemFacebookPost,functions:onAccommodationFacebookPost,functions:onAccommodationRoomFacebookPost,functions:onMarketplacePromotionFacebookPost,functions:onLatestArrivalFacebookPost,functions:onMerchantPromotionFacebookPost,functions:onMarketplaceItemCreated,functions:onMarketplaceItemUpdated
 *
 * Failed attempts write `facebookPostError` on the Firestore listing doc.
 */

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const FACEBOOK_PAGE_ACCESS_TOKEN = defineSecret('FACEBOOK_PAGE_ACCESS_TOKEN');
const FACEBOOK_PAGE_ID = defineSecret('FACEBOOK_PAGE_ID');

const DEFAULT_PAGE_ID = '1146056985268073';
/** Prefer a stable version; v26 is fine for feed but token errors dominate outages. */
const GRAPH_VERSION = 'v22.0';
/** Same SA as other Vero functions — Compute default often cannot write Firestore. */
const FUNCTIONS_SERVICE_ACCOUNT =
  'vero360app-ca423@appspot.gserviceaccount.com';

const FACEBOOK_CLAIM_TTL_MS = 3 * 60 * 1000;
const FACEBOOK_RETRY_COOLDOWN_MS = 10 * 60 * 1000;

function timestampToMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value === 'number') return value;
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : 0;
}

function isFacebookAuthError(errOrJson) {
  const raw =
    typeof errOrJson === 'string'
      ? errOrJson
      : JSON.stringify(errOrJson || {});
  const s = raw.toLowerCase();
  return (
    s.includes('oauthexception') ||
    s.includes('session has expired') ||
    s.includes('invalid oauth') ||
    s.includes('error validating access token') ||
    s.includes('cannot parse access token') ||
    s.includes('"code":190') ||
    s.includes('"code":102')
  );
}

/** Same bands as BuyerCommission in the app. Do not store this as the seller price. */
function buyerFacingTotal(raw) {
  const price = Number(raw);
  if (!Number.isFinite(price) || price <= 0) return 0;
  let rate = 0.03;
  if (price <= 5000) rate = 0.1;
  else if (price <= 10000) rate = 0.09;
  else if (price <= 20000) rate = 0.08;
  else if (price <= 50000) rate = 0.07;
  else if (price <= 100000) rate = 0.06;
  else if (price <= 500000) rate = 0.05;
  else if (price <= 2000000) rate = 0.04;
  else if (price <= 10000000) rate = 0.033;
  const money = (v) => Math.round(v * 100) / 100;
  const base = money(price);
  return Math.round(base + money(base * rate));
}

function buyerPriceLabel(raw) {
  const total = buyerFacingTotal(raw);
  if (!total) return '';
  return ` — MWK ${total.toLocaleString('en-US')}`;
}

/** Shop price for the public link. vero360.app adds commission when it renders. */
function rawPriceParam(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return '';
  return String(n);
}

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
  const price = rawPriceParam(data.price);
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
  const price = rawPriceParam(data.price);
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
  const price = rawPriceParam(
    data.price != null ? data.price : data.pricePerNight,
  );
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

/** Live listing that never got a Graph post id — retry after claim/attempt cools down. */
function needsFacebookRetry(after, isLiveFn) {
  if (!after || typeof after !== 'object') return false;
  if (after.facebookPostId || after.facebookPostedAt) return false;
  if (!isLiveFn(after)) return false;

  const claimMs = timestampToMs(after.facebookPostClaimAt);
  if (claimMs > 0 && Date.now() - claimMs < FACEBOOK_CLAIM_TTL_MS) {
    return false; // in-flight
  }

  const lastMs = timestampToMs(after.facebookPostLastAttemptAt);
  if (lastMs > 0 && Date.now() - lastMs < FACEBOOK_RETRY_COOLDOWN_MS) {
    return false;
  }

  // Retry only when we previously failed / claimed, or never attempted after going live.
  return (
    Boolean(after.facebookPostError) ||
    claimMs > 0 ||
    lastMs > 0 ||
    after.facebookPostNeeded === true
  );
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

function graphFailure(kind, status, json) {
  console.error(`Facebook Graph ${kind} failed`, status, json);
  if (isFacebookAuthError(json)) {
    throw new Error(
      'Facebook Page access token expired or invalid. ' +
        'Refresh FACEBOOK_PAGE_ACCESS_TOKEN (Page token with pages_manage_posts). ' +
        `Graph: ${JSON.stringify(json)}`,
    );
  }
  throw new Error(`Facebook Graph ${kind} error ${status}: ${JSON.stringify(json)}`);
}

async function postFeedMessage({ message, pageId, token, link }) {
  const pid = String(pageId || DEFAULT_PAGE_ID).trim() || DEFAULT_PAGE_ID;
  const access = String(token || '').trim();
  const fields = {
    access_token: access,
    message,
    published: 'true',
  };
  if (link) fields.link = link;
  const { ok, status, json } = await graphPost(
    `${encodeURIComponent(pid)}/feed`,
    fields,
  );
  if (!ok) graphFailure(link ? 'link post' : 'feed post', status, json);
  return json && json.id ? String(json.id) : null;
}

async function postLinkToFacebookPage({ link, message, pageId, token }) {
  const access = String(token || '').trim();
  if (!access) {
    console.warn(
      'Facebook Page post skipped: FACEBOOK_PAGE_ACCESS_TOKEN not set (len=0)',
    );
    return null;
  }
  await scrapeFacebookUrl(link, access);
  return postFeedMessage({ message, pageId, token: access, link });
}

function photoPostId(json) {
  if (json && json.post_id) return String(json.post_id);
  if (json && json.id) return String(json.id);
  return null;
}

/** Download the listing image ourselves so Facebook does not crawl it later. */
async function downloadListingImage(imageUrl) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 15000);
  try {
    const res = await fetch(imageUrl, {
      redirect: 'follow',
      signal: ctrl.signal,
    });
    if (!res.ok) {
      throw new Error(`image fetch ${res.status}`);
    }
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length < 200) throw new Error('image too small');
    if (buf.length > 8 * 1024 * 1024) throw new Error('image over 8 MB');
    return buf;
  } finally {
    clearTimeout(timer);
  }
}

/** Small JPEG so the Page photo is ready as soon as the post appears. */
async function shrinkForFacebook(buf) {
  const sharp = require('sharp');
  return sharp(buf, { failOn: 'none' })
    .rotate()
    .resize({ width: 1080, height: 1080, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 70 })
    .toBuffer();
}

function shortPublicLink(link) {
  try {
    const u = new URL(String(link || '').trim());
    return `${u.origin}${u.pathname}`;
  } catch (_) {
    return String(link || '').trim();
  }
}

/**
 * Upload the photo bytes with the caption so the picture is on the post
 * immediately. A URL-only photo makes Facebook fetch the file later.
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

  try {
    const raw = await downloadListingImage(img);
    const jpeg = await shrinkForFacebook(raw);
    console.log(
      'Facebook photo upload bytes',
      raw.length,
      '->',
      jpeg.length,
    );
    const form = new FormData();
    form.set('access_token', access);
    form.set('caption', caption);
    form.set('published', 'true');
    form.set('source', new Blob([jpeg], { type: 'image/jpeg' }), 'listing.jpg');
    const res = await fetch(
      `https://graph.facebook.com/${GRAPH_VERSION}/${encodeURIComponent(pid)}/photos`,
      { method: 'POST', body: form },
    );
    const json = await res.json().catch(() => ({}));
    if (!res.ok) graphFailure('photo upload', res.status, json);
    const id = photoPostId(json);
    if (id) return id;
  } catch (err) {
    const msg = err && err.message ? String(err.message) : String(err);
    if (isFacebookAuthError(msg)) throw err;
    console.warn('Facebook photo upload fallback to URL', msg);
  }

  const { ok, status, json } = await graphPost(
    `${encodeURIComponent(pid)}/photos`,
    {
      access_token: access,
      url: img,
      caption,
      published: 'true',
    },
  );
  if (!ok) graphFailure('photo post', status, json);
  return photoPostId(json);
}

/**
 * Page posts fail in different ways (link field rejected, image host blocked).
 * Try a photo, then a normal feed post with the link in the text, then a link card.
 * An expired Page token still stops immediately.
 */
async function publishListingToPage({ link, message, imageUrl, pageId, token }) {
  const access = String(token || '').trim();
  if (!access) {
    throw new Error('Missing FACEBOOK_PAGE_ACCESS_TOKEN secret');
  }
  // Short page address in the caption so the post itself is clickable.
  // Query params (including the slow image URL) stay off the caption.
  const caption = [String(message || '').trim(), shortPublicLink(link)]
    .filter(Boolean)
    .join('\n');
  const errors = [];
  const img = String(imageUrl || '').trim();

  if (/^https?:\/\//i.test(img)) {
    try {
      const id = await postPhotoToFacebookPage({
        imageUrl: img,
        caption,
        pageId,
        token: access,
      });
      if (id) return id;
      errors.push('photo post returned no id');
    } catch (err) {
      const msg = err && err.message ? String(err.message) : String(err);
      if (isFacebookAuthError(msg)) throw err;
      errors.push(msg);
    }
  }

  try {
    const id = await postFeedMessage({
      message: caption,
      pageId,
      token: access,
    });
    if (id) return id;
    errors.push('feed post returned no id');
  } catch (err) {
    const msg = err && err.message ? String(err.message) : String(err);
    if (isFacebookAuthError(msg)) throw err;
    errors.push(msg);
  }

  if (String(link || '').trim()) {
    try {
      const id = await postLinkToFacebookPage({
        link,
        message,
        pageId,
        token: access,
      });
      if (id) return id;
      errors.push('link post returned no id');
    } catch (err) {
      const msg = err && err.message ? String(err.message) : String(err);
      if (isFacebookAuthError(msg)) throw err;
      errors.push(msg);
    }
  }

  throw new Error(
    errors.filter(Boolean).join(' | ') || 'Graph returned no post id',
  );
}

async function claimFacebookPostSlot(ref) {
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const data = snap.data() || {};
    if (data.facebookPostId || data.facebookPostedAt) return false;
    // Soft claim so concurrent CF triggers don't double-post.
    if (data.facebookPostClaimAt) {
      const ms = timestampToMs(data.facebookPostClaimAt);
      // Allow retry if claim is older than TTL (failed previous attempt).
      if (ms > 0 && Date.now() - ms < FACEBOOK_CLAIM_TTL_MS) return false;
    }
    tx.set(
      ref,
      {
        facebookPostClaimAt: admin.firestore.FieldValue.serverTimestamp(),
        facebookPostLastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return true;
  });
}

async function clearFacebookPostClaim(ref, errorMessage) {
  try {
    const patch = {
      facebookPostClaimAt: admin.firestore.FieldValue.delete(),
      facebookPostLastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const msg = String(errorMessage || '').trim();
    if (msg) {
      patch.facebookPostError = msg.slice(0, 500);
    }
    await ref.set(patch, { merge: true });
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
      facebookPostError: admin.firestore.FieldValue.delete(),
      facebookPostNeeded: admin.firestore.FieldValue.delete(),
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
      : becameLiveMarketplace(before, after) ||
        needsFacebookRetry(after, isLiveMarketplace);
    link = marketplaceShareUrl(docId, after);
    const price = buyerPriceLabel(after.price);
    // Keep the URL out of the message — Facebook attaches a clickable image card via `link`.
    message = `New on Vero360 Marketplace: ${listingTitle(after)}${price}`;
  } else if (kind === 'food') {
    shouldPost = isCreate
      ? isPublicFood(after) && !after.facebookPostId && !after.facebookPostedAt
      : becamePublicFood(before, after) ||
        needsFacebookRetry(after, isPublicFood);
    link = foodShareUrl(docId, after);
    message = `New dish on Vero360: ${listingTitle(after)}`;
  } else if (kind === 'accommodation') {
    shouldPost = isCreate
      ? isPublicAccommodation(after) &&
        !after.facebookPostId &&
        !after.facebookPostedAt
      : becamePublicAccommodation(before, after) ||
        needsFacebookRetry(after, isPublicAccommodation);
    link = accommodationShareUrl(docId, after);
    message = `New stay on Vero360: ${listingTitle(after)}`;
  }

  if (!shouldPost) {
    console.log(`Facebook Page post not needed (${kind})`, docId, {
      isCreate,
      reviewStatus: after.reviewStatus || after.status || null,
      isActive: after.isActive,
      alreadyPosted: Boolean(after.facebookPostId || after.facebookPostedAt),
      lastError: after.facebookPostError || null,
    });
    return;
  }

  // Merchant opted out on the post form (toggle default is on).
  if (after.postToFacebook === false) {
    console.log(`Facebook Page post skipped by merchant (${kind})`, docId);
    return;
  }

  if (!assertFacebookPostAllowed({ after, kind })) {
    return;
  }

  const creds = resolvePageCredentials(token, pageId);
  const access = creds.token;
  const resolvedPageId = creds.pageId;
  if (!access) {
    console.warn(
      `Facebook Page post aborted (${kind}) ${docId}: missing page access token — set secret FACEBOOK_PAGE_ACCESS_TOKEN`,
    );
    await clearFacebookPostClaim(
      afterSnap.ref,
      'Missing FACEBOOK_PAGE_ACCESS_TOKEN secret',
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
    const postId = await publishListingToPage({
      link,
      message,
      imageUrl,
      pageId: resolvedPageId,
      token: access,
    });
    // Never stamp facebookPostedAt without a real Graph post id — that permanently
    // blocks retries after auto-moderation when the token was missing or Graph
    // returned an empty body.
    if (!postId) {
      console.warn(
        `Facebook Page post skipped / no id (${kind})`,
        docId,
        '— not marking as posted',
      );
      await clearFacebookPostClaim(
        afterSnap.ref,
        'Graph returned no post id (check token + Page permissions)',
      );
      return;
    }
    await markPosted(afterSnap.ref, postId);
    console.log(`Facebook Page post ok (${kind})`, docId, postId);
  } catch (err) {
    const msg = err && err.message ? String(err.message) : String(err);
    console.error(`Facebook Page post failed (${kind})`, docId, msg);
    await clearFacebookPostClaim(afterSnap.ref, msg);
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
  memory: '512MiB',
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

function verticalItemsCollection(vertical) {
  const v = String(vertical || 'marketplace').trim().toLowerCase();
  if (v === 'food') return 'food_menu_items';
  if (v === 'accommodation' || v === 'stay') return 'accommodation_rooms';
  return 'marketplace_items';
}

function shareUrlForVertical(vertical, itemId, itemData) {
  const v = String(vertical || 'marketplace').trim().toLowerCase();
  if (v === 'food') return foodShareUrl(itemId, itemData);
  if (v === 'accommodation' || v === 'stay') {
    return accommodationShareUrl(itemId, itemData);
  }
  return marketplaceShareUrl(itemId, itemData);
}

function isPaidPromoStatus(status) {
  const s = String(status || '').trim().toLowerCase();
  return s === 'paid' || s === 'active' || s === 'fulfilled';
}

/** Owner uid on listing / promo docs (common field names across verticals). */
function listingOwnerId(data) {
  if (!data || typeof data !== 'object') return '';
  return String(
    data.merchantId ||
      data.sellerUserId ||
      data.ownerId ||
      data.userId ||
      data.hostUid ||
      '',
  ).trim();
}

/**
 * Refuse Page posts when the doc has no owner, or (for paid promote) when
 * promo.merchantId does not own the linked listing. Also require server-side
 * payment verification for marketplace_promotions.
 */
function assertFacebookPostAllowed({ after, kind, item }) {
  const owner = listingOwnerId(after);
  if (!owner) {
    console.warn(
      `Facebook Page post blocked (${kind}): missing merchantId/owner`,
    );
    return false;
  }
  if (kind === 'marketplace_promotion') {
    if (after.paymentVerifiedBy !== 'activateMarketplacePromotion') {
      console.warn(
        'Facebook Page post blocked (marketplace_promotion): payment not verified server-side',
      );
      return false;
    }
    const itemOwner = listingOwnerId(item || {});
    if (!itemOwner || itemOwner !== owner) {
      console.warn(
        'Facebook Page post blocked (marketplace_promotion): promo owner != listing owner',
        { promoOwner: owner, itemOwner },
      );
      return false;
    }
  }
  if (kind === 'merchant_promotion' && !owner) {
    return false;
  }
  return true;
}

/**
 * When a promote package is paid/activated, also post the item to the Facebook Page.
 */
exports.onMarketplacePromotionFacebookPost = onDocumentWritten(
  {
    document: 'marketplace_promotions/{id}',
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

    const promoId = String(event.params.id || '').trim();
    try {
      const becamePaid =
        isPaidPromoStatus(after.status) &&
        (isCreate || !isPaidPromoStatus(before.status));
      if (!becamePaid) return;
      if (after.facebookPostId || after.facebookPostedAt) return;

      const itemId = String(after.itemId || '').trim();
      if (!itemId) {
        console.warn('Promotion FB post skipped: missing itemId', promoId);
        return;
      }

      const vertical = String(after.vertical || 'marketplace').trim();
      const col = verticalItemsCollection(vertical);
      const itemSnap = await admin.firestore().collection(col).doc(itemId).get();
      if (!itemSnap.exists) {
        console.warn(
          'Promotion FB post skipped: item not found',
          col,
          itemId,
        );
        return;
      }
      const item = itemSnap.data() || {};
      if (
        !assertFacebookPostAllowed({
          after,
          kind: 'marketplace_promotion',
          item,
        })
      ) {
        return;
      }

      const { token, pageId } = resolvePageCredentials();
      if (!token) {
        console.warn('Promotion FB post aborted: missing page token', promoId);
        return;
      }

      let claimed = false;
      try {
        claimed = await claimFacebookPostSlot(afterSnap.ref);
      } catch (_) {
        claimed = true;
      }
      if (!claimed) return;

      const link = shareUrlForVertical(vertical, itemId, item);
      const title = listingTitle(item);
      const planLabel = String(after.planId || after.channel || 'boost').trim();
      const price = buyerPriceLabel(item.price);
      const message = `🔥 Promoted on Vero360 (${planLabel}): ${title}${price}\nShop now on Vero360`;

      const imageUrl = firstHttpImage(item);
      const postId = await publishListingToPage({
        link,
        message,
        imageUrl,
        pageId,
        token,
      });
      if (!postId) {
        await clearFacebookPostClaim(afterSnap.ref);
        return;
      }
      await markPosted(afterSnap.ref, postId);
      console.log('Promotion Facebook Page post ok', promoId, postId);
    } catch (err) {
      console.error('onMarketplacePromotionFacebookPost failed', err);
      try {
        await clearFacebookPostClaim(afterSnap.ref);
      } catch (_) {}
    }
  },
);

/**
 * Latest arrivals → Facebook Page photo/link post.
 */
exports.onLatestArrivalFacebookPost = onDocumentWritten(
  {
    document: 'latest_arrivals/{id}',
    ...firestoreOpts,
  },
  async (event) => {
    const isCreate = !event.data?.before?.exists;
    if (!isCreate) return;
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;
    const docId = String(event.params.id || '').trim();

    try {
      if (after.facebookPostId || after.facebookPostedAt) return;
      if (after.postToFacebook === false) return;
      if (!assertFacebookPostAllowed({ after, kind: 'latest_arrival' })) {
        return;
      }

      const { token, pageId } = resolvePageCredentials();
      if (!token) {
        console.warn('Latest arrival FB post aborted: missing page token', docId);
        return;
      }

      let claimed = false;
      try {
        claimed = await claimFacebookPostSlot(afterSnap.ref);
      } catch (_) {
        claimed = true;
      }
      if (!claimed) return;

      const name = listingTitle(after);
      const price = buyerPriceLabel(after.price);
      const link = 'https://vero360.app/';
      const message = `🆕 Today's arrival on Vero360: ${name}${price}\nOpen the app to shop.`;
      const imageUrl = firstHttpImage(after);
      const postId = await publishListingToPage({
        link,
        message,
        imageUrl,
        pageId,
        token,
      });
      await markPosted(afterSnap.ref, postId);
      console.log('Latest arrival Facebook Page post ok', docId, postId);
    } catch (err) {
      console.error('onLatestArrivalFacebookPost failed', err);
      try {
        await clearFacebookPostClaim(afterSnap.ref);
      } catch (_) {}
    }
  },
);

/**
 * Merchant promotions (Nest promos) → Facebook Page when queued from the app.
 */
exports.onMerchantPromotionFacebookPost = onDocumentWritten(
  {
    document: 'merchant_promotions/{id}',
    ...firestoreOpts,
  },
  async (event) => {
    const isCreate = !event.data?.before?.exists;
    if (!isCreate) return;
    const after = event.data?.after?.data() || {};
    const afterSnap = event.data?.after;
    if (!afterSnap || !afterSnap.exists) return;
    const docId = String(event.params.id || '').trim();

    try {
      if (after.facebookPostId || after.facebookPostedAt) return;
      if (after.postToFacebook === false) return;
      if (
        !assertFacebookPostAllowed({ after, kind: 'merchant_promotion' })
      ) {
        return;
      }

      const { token, pageId } = resolvePageCredentials();
      if (!token) {
        console.warn(
          'Merchant promo FB post aborted: missing page token',
          docId,
        );
        return;
      }

      let claimed = false;
      try {
        claimed = await claimFacebookPostSlot(afterSnap.ref);
      } catch (_) {
        claimed = true;
      }
      if (!claimed) return;

      const name = listingTitle(after);
      const price = buyerPriceLabel(after.price);
      const desc = String(after.description || '').trim();
      const link = 'https://vero360.app/';
      const message = [
        `🏷️ Promotion on Vero360: ${name}${price}`,
        desc ? desc.slice(0, 180) : '',
        'Open the app to grab the deal.',
      ]
        .filter(Boolean)
        .join('\n');
      const imageUrl = firstHttpImage(after);
      const postId = await publishListingToPage({
        link,
        message,
        imageUrl,
        pageId,
        token,
      });
      await markPosted(afterSnap.ref, postId);
      console.log('Merchant promo Facebook Page post ok', docId, postId);
    } catch (err) {
      console.error('onMerchantPromotionFacebookPost failed', err);
      try {
        await clearFacebookPostClaim(afterSnap.ref);
      } catch (_) {}
    }
  },
);
