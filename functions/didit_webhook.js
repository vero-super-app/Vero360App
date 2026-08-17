/**
 * Didit webhook receiver (v3 destinations).
 * Verifies X-Signature-V2 (preferred), X-Signature (raw bytes), then X-Signature-Simple.
 * @see https://docs.didit.me/integration/webhooks
 */

const { createHmac, timingSafeEqual } = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const diditWebhookSecret = defineSecret('DIDIT_WEBHOOK_SECRET');

const TIMESTAMP_SKEW_SEC = 300;

/** Match Didit's float normalisation: whole-valued floats serialise as ints. */
function shortenFloats(data) {
  if (Array.isArray(data)) return data.map(shortenFloats);
  if (data !== null && typeof data === 'object') {
    return Object.fromEntries(
      Object.entries(data).map(([key, value]) => [key, shortenFloats(value)]),
    );
  }
  if (typeof data === 'number' && !Number.isInteger(data) && data % 1 === 0) {
    return Math.trunc(data);
  }
  return data;
}

/** Sort object keys recursively before re-stringifying (Didit sort_keys). */
function sortKeys(obj) {
  if (Array.isArray(obj)) return obj.map(sortKeys);
  if (obj !== null && typeof obj === 'object') {
    return Object.keys(obj)
      .sort()
      .reduce((acc, key) => {
        acc[key] = sortKeys(obj[key]);
        return acc;
      }, {});
  }
  return obj;
}

function constantTimeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

function timestampFresh(timestampHeader) {
  const timestamp = Number.parseInt(String(timestampHeader || ''), 10);
  if (!Number.isFinite(timestamp)) return false;
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - timestamp) <= TIMESTAMP_SKEW_SEC;
}

function verifySignatureV2(jsonBody, signatureHeader, secret) {
  const canonical = JSON.stringify(sortKeys(shortenFloats(jsonBody)));
  const expected = createHmac('sha256', secret)
    .update(canonical, 'utf8')
    .digest('hex');
  return constantTimeEqualHex(expected, signatureHeader);
}

function verifySignatureRaw(rawBodyBuf, signatureHeader, secret) {
  const expected = createHmac('sha256', secret)
    .update(rawBodyBuf)
    .digest('hex');
  return constantTimeEqualHex(expected, signatureHeader);
}

/** Envelope-only; does NOT authenticate `decision`. */
function verifySignatureSimple(jsonBody, signatureHeader, secret) {
  const canonical = [
    jsonBody.timestamp ?? '',
    jsonBody.session_id ?? '',
    jsonBody.status ?? '',
    jsonBody.webhook_type ?? '',
  ].join(':');
  const expected = createHmac('sha256', secret)
    .update(canonical, 'utf8')
    .digest('hex');
  return constantTimeEqualHex(expected, signatureHeader);
}

function extractRejectionReason(decision) {
  if (!decision || typeof decision !== 'object') {
    return 'Verification declined';
  }
  const reasons = [];
  for (const value of Object.values(decision)) {
    if (!Array.isArray(value)) continue;
    for (const item of value) {
      if (!item || typeof item !== 'object') continue;
      const warnings = item.warnings;
      if (!Array.isArray(warnings)) continue;
      for (const warning of warnings) {
        if (!warning || typeof warning !== 'object') continue;
        const text =
          (typeof warning.short_description === 'string' &&
            warning.short_description) ||
          (typeof warning.long_description === 'string' &&
            warning.long_description) ||
          (typeof warning.risk === 'string' && warning.risk) ||
          '';
        if (String(text).trim()) reasons.push(String(text).trim());
      }
    }
  }
  return reasons.length ? reasons.join('; ') : 'Verification declined';
}

function normalizeSessionStatus(status) {
  const raw = String(status || '').trim();
  const lower = raw.toLowerCase().replace(/_/g, ' ');
  // Docs sometimes use "Kyc Expired"; console/tests may send "KYC Expired".
  if (lower === 'kyc expired') return 'KYC Expired';
  // Didit console shows APPROVED; webhooks may send Approved / approved.
  const aliases = {
    approved: 'Approved',
    declined: 'Declined',
    'in review': 'In Review',
    'in progress': 'In Progress',
    resubmitted: 'Resubmitted',
    abandoned: 'Abandoned',
    expired: 'Expired',
    'not started': 'Not Started',
  };
  return aliases[lower] || raw;
}

/**
 * Map Didit session status → Firestore KYC fields on users/{uid}.
 * @returns {Record<string, unknown>|null} null = no user field update
 */
function kycFieldsForStatus(status, decision, trustDecision) {
  const s = normalizeSessionStatus(status);
  const base = {
    kycUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    kycLastStatus: s,
  };

  switch (s) {
    case 'Approved':
      return {
        ...base,
        kycStatus: 'verified',
        kycVerified: true,
        kycRejectionReason: admin.firestore.FieldValue.delete(),
        ...(trustDecision && decision ? { kycDecision: decision } : {}),
      };
    case 'Declined':
      return {
        ...base,
        kycStatus: 'rejected',
        kycVerified: false,
        kycRejectionReason: trustDecision
          ? extractRejectionReason(decision)
          : 'Verification declined',
        ...(trustDecision && decision ? { kycDecision: decision } : {}),
      };
    case 'In Review':
      return {
        ...base,
        kycStatus: 'pending_review',
        kycVerified: false,
        ...(trustDecision && decision ? { kycDecision: decision } : {}),
      };
    case 'In Progress':
      return {
        ...base,
        kycStatus: 'in_progress',
        kycVerified: false,
      };
    case 'Resubmitted':
      return {
        ...base,
        kycStatus: 'resubmitted',
        kycVerified: false,
      };
    case 'Abandoned':
      return {
        ...base,
        kycStatus: 'abandoned',
        kycVerified: false,
        ...(trustDecision && decision ? { kycDecision: decision } : {}),
      };
    case 'Expired':
    case 'KYC Expired':
      return {
        ...base,
        kycStatus: 'expired',
        kycVerified: false,
      };
    case 'Not Started':
      return {
        ...base,
        kycStatus: 'pending',
        kycVerified: false,
      };
    default:
      return null;
  }
}

/**
 * Claim event_id for idempotency. Returns false if already processed.
 */
async function claimEventId(eventId, meta) {
  if (!eventId) return true; // no id → still process (best effort)
  const ref = admin.firestore().collection('didit_webhook_events').doc(eventId);
  try {
    await ref.create({
      ...meta,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  } catch (err) {
    if (err && err.code === 6) {
      // ALREADY_EXISTS
      return false;
    }
    // Fallback: race / older SDK codes
    if (String(err && err.message || '').includes('EXISTS')) return false;
    throw err;
  }
}

async function applySessionEvent(payload, trustDecision) {
  const sessionId =
    typeof payload.session_id === 'string' ? payload.session_id.trim() : '';
  const uid =
    typeof payload.vendor_data === 'string' ? payload.vendor_data.trim() : '';
  const status = payload.status;
  const decision =
    payload.decision && typeof payload.decision === 'object'
      ? payload.decision
      : undefined;
  const webhookType = payload.webhook_type;

  if (!uid) {
    console.warn('Didit session event missing vendor_data', {
      sessionId,
      webhookType,
    });
    return { ok: true, skipped: 'no_vendor_data' };
  }

  const userRef = admin.firestore().collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    // Do NOT 404 — Didit retries on 404.
    console.warn(`Didit webhook: no user for vendor_data=${uid}`);
    return { ok: true, skipped: 'user_not_found' };
  }

  const fields = kycFieldsForStatus(status, decision, trustDecision);
  const update = {
    kycSessionId: sessionId || userSnap.get('kycSessionId') || null,
    kycWebhookType: webhookType || null,
    kycEventId: typeof payload.event_id === 'string' ? payload.event_id : null,
  };

  if (payload.session_kind === 'business' || payload.business_session_id) {
    update.kycSessionKind = 'business';
    if (payload.business_session_id) {
      update.kycBusinessSessionId = payload.business_session_id;
    }
  }

  if (status === 'Resubmitted' && payload.resubmit_info) {
    update.kycResubmitInfo = payload.resubmit_info;
  }

  if (fields) Object.assign(update, fields);

  await userRef.set(update, { merge: true });
  return { ok: true, uid, status, webhookType };
}

async function applyUserEntityEvent(payload) {
  const uid =
    (typeof payload.vendor_data === 'string' && payload.vendor_data.trim()) ||
    (typeof payload.vendor_user_id === 'string' &&
      payload.vendor_user_id.trim()) ||
    '';
  if (!uid) return { ok: true, skipped: 'no_vendor_data' };

  const userRef = admin.firestore().collection('users').doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    console.warn(`Didit user entity event: no user ${uid}`);
    return { ok: true, skipped: 'user_not_found' };
  }

  const update = {
    diditUserStatus: payload.status || null,
    diditUserPreviousStatus: payload.previous_status || null,
    diditUserUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (payload.webhook_type === 'user.data.updated') {
    if (payload.changed_fields) update.diditUserChangedFields = payload.changed_fields;
    if (payload.changes) update.diditUserChanges = payload.changes;
  }
  await userRef.set(update, { merge: true });
  return { ok: true, uid, webhookType: payload.webhook_type };
}

async function applyBusinessEntityEvent(payload) {
  const businessId =
    (typeof payload.vendor_business_id === 'string' &&
      payload.vendor_business_id.trim()) ||
    (typeof payload.business_id === 'string' && payload.business_id.trim()) ||
    '';
  if (!businessId) {
    await admin.firestore().collection('didit_business_events').add({
      payload,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, logged: true };
  }

  await admin
    .firestore()
    .collection('didit_businesses')
    .doc(businessId)
    .set(
      {
        status: payload.status || null,
        previousStatus: payload.previous_status || null,
        changedFields: payload.changed_fields || null,
        changes: payload.changes || null,
        webhookType: payload.webhook_type || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return { ok: true, businessId };
}

async function applyTransactionEvent(payload) {
  const txnId =
    (typeof payload.transaction_id === 'string' &&
      payload.transaction_id.trim()) ||
    (typeof payload.txn_id === 'string' && payload.txn_id.trim()) ||
    '';
  const docId = txnId || (payload.event_id ? String(payload.event_id) : null);
  if (!docId) {
    await admin.firestore().collection('didit_transactions').add({
      ...payload,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true };
  }

  await admin
    .firestore()
    .collection('didit_transactions')
    .doc(docId)
    .set(
      {
        ...payload,
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return { ok: true, transactionId: docId };
}

async function applyActivityEvent(payload) {
  await admin.firestore().collection('didit_activity').add({
    ...payload,
    receivedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
}

async function applyTravelRuleEvent(payload) {
  const id =
    (typeof payload.transaction_id === 'string' && payload.transaction_id) ||
    (typeof payload.event_id === 'string' && payload.event_id) ||
    null;
  const col = admin.firestore().collection('didit_travel_rule');
  if (id) {
    await col.doc(id).set(
      { ...payload, receivedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );
  } else {
    await col.add({
      ...payload,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  return { ok: true };
}

async function processWebhook(payload, trustDecision, isTest) {
  const webhookType = String(payload.webhook_type || '');
  const eventId =
    typeof payload.event_id === 'string' ? payload.event_id.trim() : '';

  const claimed = await claimEventId(eventId, {
    webhookType,
    status: payload.status || null,
    sessionId: payload.session_id || null,
    isTest: !!isTest,
    trustDecision: !!trustDecision,
  });
  if (!claimed) {
    console.log(`Didit webhook duplicate event_id=${eventId}`);
    return { ok: true, duplicate: true };
  }

  switch (webhookType) {
    case 'status.updated':
    case 'data.updated':
      return applySessionEvent(payload, trustDecision);
    case 'user.status.updated':
    case 'user.data.updated':
      return applyUserEntityEvent(payload);
    case 'business.status.updated':
    case 'business.data.updated':
      return applyBusinessEntityEvent(payload);
    case 'activity.created':
      return applyActivityEvent(payload);
    case 'transaction.created':
    case 'transaction.status.updated':
      return applyTransactionEvent(payload);
    case 'travel_rule.status.updated':
      return applyTravelRuleEvent(payload);
    default:
      console.warn(`Didit webhook unknown webhook_type=${webhookType}`);
      await admin.firestore().collection('didit_webhook_unknown').add({
        payload,
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { ok: true, ignored: webhookType };
  }
}

/**
 * Public HTTPS POST — point Didit destination webhook_url here.
 * subscribed_events should list every family you want (no wildcard).
 */
const diditWebhook = onRequest(
  {
    secrets: [diditWebhookSecret],
    invoker: 'public',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const secret = diditWebhookSecret.value();
    const timestampHeader = req.get('X-Timestamp') || '';
    const signatureV2 = req.get('X-Signature-V2') || '';
    const signatureRaw = req.get('X-Signature') || '';
    const signatureSimple = req.get('X-Signature-Simple') || '';
    const rawBodyBuf = req.rawBody;
    const isTest = String(req.get('X-Didit-Test-Webhook') || '') === 'true';

    if (!secret || !timestampHeader) {
      console.warn('Didit webhook missing secret or X-Timestamp');
      res.status(401).json({ message: 'Unauthorized' });
      return;
    }

    if (!timestampFresh(timestampHeader)) {
      console.warn('Didit webhook timestamp outside 300s window');
      res.status(401).json({ message: 'Unauthorized' });
      return;
    }

    if (!rawBodyBuf || !rawBodyBuf.length) {
      console.warn('Didit webhook empty raw body');
      res.status(401).json({ message: 'Unauthorized' });
      return;
    }

    let payload;
    try {
      payload = JSON.parse(rawBodyBuf.toString('utf8'));
    } catch (err) {
      console.warn('Didit webhook JSON parse failed', err && err.message);
      // Log raw for signature debugging (truncated; avoid huge dumps in prod if needed)
      console.warn('Didit webhook raw (prefix)', rawBodyBuf.toString('utf8').slice(0, 500));
      res.status(401).json({ message: 'Unauthorized' });
      return;
    }

    let verified = false;
    let trustDecision = false;

    if (
      signatureV2 &&
      verifySignatureV2(payload, signatureV2, secret)
    ) {
      verified = true;
      trustDecision = true;
    } else if (
      signatureRaw &&
      verifySignatureRaw(rawBodyBuf, signatureRaw, secret)
    ) {
      verified = true;
      trustDecision = true;
    } else if (
      signatureSimple &&
      verifySignatureSimple(payload, signatureSimple, secret)
    ) {
      verified = true;
      // Simple does not authenticate decision — do not persist decision blob.
      trustDecision = false;
      console.warn(
        'Didit webhook accepted via X-Signature-Simple; decision not trusted',
      );
    }

    if (!verified) {
      console.warn('Didit webhook signature verification failed', {
        hasV2: !!signatureV2,
        hasRaw: !!signatureRaw,
        hasSimple: !!signatureSimple,
        eventId: payload && payload.event_id,
      });
      console.warn(
        'Didit webhook raw (prefix)',
        rawBodyBuf.toString('utf8').slice(0, 500),
      );
      res.status(401).json({ message: 'Invalid signature' });
      return;
    }

    try {
      const result = await processWebhook(payload, trustDecision, isTest);
      // Always 2xx after auth so Didit does not retry (except on our 5xx).
      res.status(200).json({ ok: true, ...result });
    } catch (err) {
      console.error('Didit webhook processing failed', err);
      // 5xx triggers Didit retries (~1m, then ~4m).
      res.status(500).json({ ok: false });
    }
  },
);

module.exports = {
  diditWebhook,
  diditWebhookSecret,
};
