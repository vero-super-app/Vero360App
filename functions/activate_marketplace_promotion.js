/**
 * Activate a marketplace promote package only after PayChangu confirms payment.
 * Clients must not write status=paid/active themselves.
 *
 * Secret: set Firebase secret PAYCHANGU_SECRET_KEY (test or live key).
 * Deploy: firebase deploy --only functions:activateMarketplacePromotion
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const FUNCTIONS_SERVICE_ACCOUNT =
  'vero360app-ca423@appspot.gserviceaccount.com';

const PAYCHANGU_SECRET_KEY = defineSecret('PAYCHANGU_SECRET_KEY');

function verticalItemsCollection(vertical) {
  const v = String(vertical || 'marketplace').trim().toLowerCase();
  if (v === 'food') return 'food_menu_items';
  if (v === 'accommodation' || v === 'stay') return 'accommodation_rooms';
  return 'marketplace_items';
}

function listingOwnerId(data) {
  if (!data || typeof data !== 'object') return '';
  return String(
    data.merchantId ||
      data.sellerUserId ||
      data.sellerId ||
      data.ownerId ||
      data.userId ||
      data.hostUid ||
      data.hostId ||
      data.createdBy ||
      data.uid ||
      '',
  ).trim();
}

function isAlreadyActive(status) {
  const s = String(status || '').trim().toLowerCase();
  return s === 'paid' || s === 'active' || s === 'fulfilled';
}

function paymentSucceeded(payload) {
  // Prefer nested payment status — top-level "success" often means API OK only.
  const nested = String(
    payload?.data?.status || payload?.data?.payment_status || '',
  )
    .trim()
    .toLowerCase();
  if (
    nested === 'success' ||
    nested === 'successful' ||
    nested === 'paid' ||
    nested === 'completed'
  ) {
    return true;
  }
  if (nested) return false;

  const status = String(payload?.status || '')
    .trim()
    .toLowerCase();
  return (
    status === 'successful' ||
    status === 'paid' ||
    status === 'completed'
  );
}

async function verifyPayChanguTx(txRef, secret) {
  const url = `https://api.paychangu.com/transaction/verify/${encodeURIComponent(txRef)}`;
  const res = await fetch(url, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: secret.toLowerCase().startsWith('bearer ')
        ? secret
        : `Bearer ${secret}`,
    },
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }
  if (!res.ok) {
    throw new HttpsError(
      'failed-precondition',
      `Payment verify failed (${res.status}).`,
    );
  }
  if (!paymentSucceeded(json || {})) {
    throw new HttpsError(
      'failed-precondition',
      'Payment not confirmed yet. Try again after PayChangu shows success.',
    );
  }
  return json;
}

function parseTimestampMs(raw) {
  if (!raw) return 0;
  if (typeof raw.toMillis === 'function') return raw.toMillis();
  if (typeof raw._seconds === 'number') return raw._seconds * 1000;
  if (raw instanceof Date) return raw.getTime();
  const n = Date.parse(String(raw));
  return Number.isFinite(n) ? n : 0;
}

async function activatePromoDoc({ promoRef, promo, txRef, uid }) {
  const planId = String(promo.planId || '').trim();
  const channel = String(promo.channel || '').trim();
  const itemId = String(promo.itemId || '').trim();
  const hours = Number(promo.durationHours || 24) || 24;
  const amount = Number(promo.amountMwk || 0) || 0;
  const vertical = String(promo.vertical || 'marketplace').trim().toLowerCase();
  const now = new Date();
  const ends = new Date(now.getTime() + hours * 60 * 60 * 1000);
  const isFeedTop = channel.endsWith('_top');

  const db = admin.firestore();

  if (String(promo.merchantId || '').trim() !== uid) {
    throw new HttpsError('permission-denied', 'Promotion owner mismatch.');
  }

  // Always require the linked listing to belong to the payer when itemId is set.
  if (itemId) {
    const col = verticalItemsCollection(vertical);
    const itemRef = db.collection(col).doc(itemId);
    const itemSnap = await itemRef.get();
    if (!itemSnap.exists) {
      throw new HttpsError('not-found', 'Listing not found for this promotion.');
    }
    const item = itemSnap.data() || {};
    const owner = listingOwnerId(item);
    if (!owner || owner !== uid) {
      throw new HttpsError(
        'permission-denied',
        'You can only promote your own listings.',
      );
    }

    if (isFeedTop) {
      let baseMs = now.getTime();
      const existingMs = parseTimestampMs(item.promotedUntil);
      if (existingMs > baseMs) baseMs = existingMs;
      const until = new Date(baseMs + hours * 60 * 60 * 1000);

      const batch = db.batch();
      batch.set(
        itemRef,
        {
          promotedUntil: admin.firestore.Timestamp.fromDate(until),
          promotionPlanId: planId,
          promotionPaidAt: admin.firestore.FieldValue.serverTimestamp(),
          promotionTxRef: txRef,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      batch.set(
        promoRef,
        {
          status: 'active',
          vertical,
          txRef,
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromDate(until),
          paymentVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          paymentVerifiedBy: 'activateMarketplacePromotion',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await batch.commit();
      return {
        status: 'active',
        amountMwk: amount,
        expiresAt: until.toISOString(),
        channel,
        planId,
      };
    }
  }

  // Facebook ads order — queued for admin fulfillment (no listing boost).
  await promoRef.set(
    {
      status: 'paid',
      vertical,
      fulfillmentStatus: 'queued',
      txRef,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(ends),
      paymentVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentVerifiedBy: 'activateMarketplacePromotion',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return {
    status: 'paid',
    amountMwk: amount,
    expiresAt: ends.toISOString(),
    channel,
    planId,
  };
}

exports.PAYCHANGU_SECRET_KEY = PAYCHANGU_SECRET_KEY;

exports.activateMarketplacePromotion = onCall(
  {
    timeoutSeconds: 45,
    memory: '256MiB',
    serviceAccount: FUNCTIONS_SERVICE_ACCOUNT,
    secrets: [PAYCHANGU_SECRET_KEY],
  },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const uid = request.auth.uid;
    const data = request.data || {};
    const promoId = String(data.promoId || '').trim();
    const txRef = String(data.txRef || '').trim();
    if (!promoId) {
      throw new HttpsError('invalid-argument', 'promoId is required.');
    }
    if (!txRef) {
      throw new HttpsError('invalid-argument', 'txRef is required.');
    }

    let secret = '';
    try {
      secret = String(PAYCHANGU_SECRET_KEY.value() || '').trim();
    } catch (_) {
      secret = String(process.env.PAYCHANGU_SECRET_KEY || '').trim();
    }
    if (!secret) {
      throw new HttpsError(
        'failed-precondition',
        'PAYCHANGU_SECRET_KEY is not configured on Cloud Functions.',
      );
    }

    const promoRef = admin
      .firestore()
      .collection('marketplace_promotions')
      .doc(promoId);
    const snap = await promoRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Promotion not found.');
    }
    const promo = snap.data() || {};
    if (String(promo.merchantId || '').trim() !== uid) {
      throw new HttpsError(
        'permission-denied',
        'You can only activate your own promotions.',
      );
    }
    if (isAlreadyActive(promo.status)) {
      return { ok: true, alreadyActive: true, status: promo.status };
    }

    const expectedTx = String(promo.txRef || '').trim();
    if (expectedTx && expectedTx !== txRef) {
      throw new HttpsError(
        'failed-precondition',
        'txRef does not match this promotion.',
      );
    }

    await verifyPayChanguTx(txRef, secret);
    const result = await activatePromoDoc({
      promoRef,
      promo,
      txRef,
      uid,
    });
    return { ok: true, ...result };
  },
);
