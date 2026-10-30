/**
 * Mobile-money payouts via PawaPay. Bank cash-out stays on PayChangu.
 *
 *   firebase functions:secrets:set PAWAPAY_API_TOKEN
 *   firebase deploy --only functions:createPawaPayPayout,functions:pawapayWebhook
 *
 * Set the PawaPay callback URL to the pawapayWebhook function URL.
 * PAWAPAY_ENV=live uses production; anything else uses sandbox.
 */

const { randomUUID } = require('crypto');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const pawapayApiToken = defineSecret('PAWAPAY_API_TOKEN');

const AIRTEL = '20be6c20-adeb-4b5b-a7ba-0769820df4fb';
const TNM = '27494cb5-ba9e-437f-a114-4e7a7686bcca';

function providerFor(operatorId) {
  const id = String(operatorId || '').trim().toLowerCase();
  if (id === AIRTEL || id.includes('airtel')) return 'AIRTEL_MWI';
  if (id === TNM || id.includes('tnm') || id.includes('mpamba')) return 'TNM_MPAMBA_MWI';
  return '';
}

function toMsisdn(raw) {
  let mobile = String(raw || '').trim().replace(/\s+/g, '');
  if (mobile.startsWith('+265')) mobile = `0${mobile.slice(4)}`;
  else if (mobile.startsWith('265')) mobile = `0${mobile.slice(3)}`;
  if (!/^0\d{8,9}$/.test(mobile)) return '';
  return `265${mobile.slice(1)}`;
}

const SANDBOX = 'https://api.sandbox.pawapay.io';
const LIVE = 'https://api.pawapay.io';
let resolvedBase = '';

function cleanToken(raw) {
  let token = String(raw || '').replace(/^\uFEFF/, '').trim();
  if (
    (token.startsWith('"') && token.endsWith('"')) ||
    (token.startsWith("'") && token.endsWith("'"))
  ) {
    token = token.slice(1, -1).trim();
  }
  return token.replace(/^Bearer\s+/i, '').replace(/\s+/g, '');
}

function baseCandidates() {
  const mode = String(process.env.PAWAPAY_ENV || '').trim().toLowerCase();
  if (mode === 'live' || mode === 'production') return [LIVE];
  if (mode === 'sandbox' || mode === 'test') return [SANDBOX];
  if (resolvedBase) return [resolvedBase, resolvedBase === SANDBOX ? LIVE : SANDBOX];
  return [SANDBOX, LIVE];
}

// 403 also covers "provider not enabled for this account", so only 401 or an
// explicit AUTHENTICATION_ERROR means the token itself is wrong.
function isAuthFailure(status, body) {
  if (status === 401) return true;
  const reason = body && body.failureReason;
  const code = reason && typeof reason === 'object' ? String(reason.failureCode || '') : '';
  if (code.toUpperCase() === 'AUTHENTICATION_ERROR') return true;
  return failureMessage(body).toLowerCase().includes('api token');
}

function rawFailureMessage(body) {
  const reason = body && body.failureReason;
  if (typeof reason === 'string' && reason.trim()) return reason.trim();
  if (reason && typeof reason === 'object') {
    const message = String(reason.failureMessage || reason.failureCode || '').trim();
    if (message) return message;
  }
  return String((body && (body.message || body.error)) || 'PawaPay rejected the payment');
}

function failureMessage(body) {
  const raw = rawFailureMessage(body);
  const text = raw.toLowerCase();
  if (text.includes('not been configured') || text.includes('provider_temporarily_unavailable')) {
    return 'This mobile-money network is not switched on for Vero360 payments yet. Try the other network or try again later.';
  }
  if (text.includes('not approve') || text.includes('payment_not_approved')) {
    return 'The prompt was not approved. Open it on your phone, enter your PIN, then try again.';
  }
  if (text.includes('insufficient') || text.includes('enough funds')) {
    return 'This wallet does not have enough money for this payment.';
  }
  return raw;
}

function moneyAmount(amount) {
  const rounded = Math.round(Number(amount));
  return String(rounded);
}

async function findWallet(uid) {
  const db = admin.firestore();
  const fixed = await db.collection('wallets').doc(uid).get();
  if (fixed.exists && String((fixed.data() || {}).userId || '') === uid) return fixed;
  const query = await db.collection('wallets').where('userId', '==', uid).limit(1).get();
  if (query.empty) return null;
  return query.docs[0];
}

async function reservePayout(walletRef, amount, payoutId, description, phone, provider) {
  const db = admin.firestore();
  const transactionId = `TXN${Date.now()}`;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const txPayload = {
    transactionId,
    walletId: walletRef.id,
    userId: null,
    type: 'payout',
    amount,
    status: 'pending',
    description,
    reference: payoutId,
    payoutMethod: 'mobile_money',
    payoutProvider: 'pawapay',
    recipientPhone: phone,
    provider,
    createdAt: now,
    updatedAt: now,
  };

  await db.runTransaction(async txn => {
    const snap = await txn.get(walletRef);
    if (!snap.exists) throw new HttpsError('failed-precondition', 'Wallet not found');
    const data = snap.data() || {};
    const balance = Number(data.balance) || 0;
    if (balance < amount) {
      throw new HttpsError('failed-precondition', 'Insufficient balance');
    }
    txPayload.userId = data.userId || null;
    const list = Array.isArray(data.transactions) ? data.transactions.slice(-24) : [];
    list.push({ ...txPayload, createdAt: admin.firestore.Timestamp.now() });
    txn.update(walletRef, {
      balance: balance - amount,
      pendingBalance: (Number(data.pendingBalance) || 0) + amount,
      updatedAt: now,
      transactions: list,
    });
    txn.set(db.collection('wallet_transactions').doc(transactionId), txPayload);
    txn.set(db.collection('pawapay_payouts').doc(payoutId), {
      payoutId,
      transactionId,
      walletId: walletRef.id,
      userId: data.userId || null,
      amount,
      phone,
      provider,
      status: 'pending',
      createdAt: now,
    });
  });

  return transactionId;
}

async function releaseReserve(payoutId, status, failure) {
  const db = admin.firestore();
  const payoutRef = db.collection('pawapay_payouts').doc(payoutId);
  await db.runTransaction(async txn => {
    const payoutSnap = await txn.get(payoutRef);
    if (!payoutSnap.exists) return;
    const payout = payoutSnap.data() || {};
    if (payout.status === 'completed' || payout.status === 'failed') return;
    const amount = Number(payout.amount) || 0;
    const walletRef = db.collection('wallets').doc(String(payout.walletId || ''));
    const walletSnap = await txn.get(walletRef);
    if (!walletSnap.exists) return;
    const wallet = walletSnap.data() || {};
    const pending = Number(wallet.pendingBalance) || 0;
    const nextPending = Math.max(0, pending - amount);
    const nextStatus = status === 'completed' ? 'completed' : 'failed';
    const patch = {
      pendingBalance: nextPending,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (Array.isArray(wallet.transactions)) {
      patch.transactions = wallet.transactions.map(row => {
        if (!row || typeof row !== 'object') return row;
        if (
          String(row.reference || '') !== payoutId &&
          String(row.transactionId || '') !== String(payout.transactionId || '')
        ) {
          return row;
        }
        return {
          ...row,
          status: nextStatus,
          failureReason: failure || null,
          updatedAt: admin.firestore.Timestamp.now(),
        };
      });
    }
    if (status === 'failed') {
      patch.balance = (Number(wallet.balance) || 0) + amount;
    }
    txn.update(walletRef, patch);
    txn.set(
      payoutRef,
      {
        status,
        failure: failure || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (payout.transactionId) {
      txn.set(
        db.collection('wallet_transactions').doc(String(payout.transactionId)),
        {
          status: status === 'completed' ? 'completed' : 'failed',
          failureReason: failure || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  });
}

async function sendPayout(payoutId, amount, phone, provider) {
  const { ok, body } = await pawapayRequest('/v2/payouts', {
    method: 'POST',
    body: JSON.stringify({
      payoutId,
      amount: moneyAmount(amount),
      currency: 'MWK',
      recipient: {
        type: 'MMO',
        accountDetails: { phoneNumber: phone, provider },
      },
    }),
  });
  if (!ok) {
    throw new HttpsError('failed-precondition', failureMessage(body));
  }
  const status = String(body.status || '').toUpperCase();
  if (status === 'REJECTED') {
    throw new HttpsError('failed-precondition', failureMessage(body));
  }
  if (status !== 'ACCEPTED' && status !== 'DUPLICATE_IGNORED') {
    throw new HttpsError('failed-precondition', failureMessage(body));
  }
  return status;
}

const createPawaPayPayout = onCall(
  {
    secrets: [pawapayApiToken],
    serviceAccount: 'vero360app-ca423@appspot.gserviceaccount.com',
  },
  async request => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');

    const amount = Math.round(Number(request.data && request.data.amount));
    const phone = toMsisdn(request.data && request.data.phone);
    const provider = providerFor(request.data && request.data.operatorId);
    if (!Number.isFinite(amount) || amount < 1000) {
      throw new HttpsError('invalid-argument', 'Minimum withdrawal is MWK 1,000.');
    }
    if (!phone || !provider) {
      throw new HttpsError('invalid-argument', 'Enter a valid Airtel Money or TNM Mpamba number.');
    }

    const userSnap = await admin.firestore().collection('users').doc(uid).get();
    const user = userSnap.data() || {};
    const kyc = String(user.kycStatus || '').toLowerCase();
    if (user.kycVerified !== true && kyc !== 'verified') {
      throw new HttpsError('failed-precondition', 'Complete KYC before withdrawing.');
    }

    const wallet = await findWallet(uid);
    if (!wallet) throw new HttpsError('failed-precondition', 'Wallet not found.');

    const payoutId = randomUUID();
    const label = provider === 'AIRTEL_MWI' ? 'Airtel Money' : 'TNM Mpamba';
    await reservePayout(
      wallet.ref,
      amount,
      payoutId,
      `${label} payout to ${phone}`,
      phone,
      provider,
    );

    try {
      const status = await sendPayout(payoutId, amount, phone, provider);
      return { payoutId, status, pending: true };
    } catch (err) {
      await releaseReserve(payoutId, 'failed', err instanceof Error ? err.message : 'Payout failed');
      throw err;
    }
  },
);

async function pawapayRequest(path, options) {
  const token = cleanToken(pawapayApiToken.value());
  if (!token) {
    throw new HttpsError('failed-precondition', 'PawaPay is not configured.');
  }
  const attempts = [];
  let last = { ok: false, status: 0, body: {} };
  for (const base of baseCandidates()) {
    const res = await fetch(`${base}${path}`, {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...(options && options.headers ? options.headers : {}),
      },
    });
    const body = await res.json().catch(() => ({}));
    last = { ok: res.ok, status: res.status, body };
    const host = base.includes('sandbox') ? 'sandbox' : 'live';
    attempts.push(`${host} ${res.status}`);
    if (isAuthFailure(res.status, body)) continue;
    resolvedBase = base;
    return last;
  }
  console.error('PawaPay auth failed', { length: token.length, attempts });
  throw new HttpsError(
    'failed-precondition',
    'Mobile-money payments are temporarily unavailable. Please try again later.',
  );
}

async function sendDeposit(depositId, amount, phone, provider, reference) {
  const { ok, body } = await pawapayRequest('/v2/deposits', {
    method: 'POST',
    body: JSON.stringify({
      depositId,
      amount: moneyAmount(amount),
      currency: 'MWK',
      clientReferenceId: String(reference || depositId).slice(0, 64),
      customerMessage: 'Vero360',
      payer: {
        type: 'MMO',
        accountDetails: { phoneNumber: phone, provider },
      },
      metadata: [
        { orderId: String(reference || depositId).slice(0, 64) },
      ],
    }),
  });
  if (!ok) {
    throw new HttpsError('failed-precondition', failureMessage(body));
  }
  const status = String(body.status || '').toUpperCase();
  if (status === 'REJECTED') {
    throw new HttpsError('failed-precondition', failureMessage(body));
  }
  if (status !== 'ACCEPTED' && status !== 'DUPLICATE_IGNORED') {
    throw new HttpsError('failed-precondition', failureMessage(body));
  }
  return status;
}

const createPawaPayDeposit = onCall(
  {
    secrets: [pawapayApiToken],
    serviceAccount: 'vero360app-ca423@appspot.gserviceaccount.com',
  },
  async request => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');

    const amount = Math.round(Number(request.data && request.data.amount));
    const phone = toMsisdn(request.data && request.data.phone);
    const provider = providerFor(request.data && request.data.operatorId);
    const reference = String((request.data && request.data.reference) || '').trim();
    if (!Number.isFinite(amount) || amount < 1) {
      throw new HttpsError('invalid-argument', 'Enter a valid amount.');
    }
    if (!phone || !provider) {
      throw new HttpsError(
        'invalid-argument',
        'Enter a valid Airtel Money or TNM Mpamba number.',
      );
    }

    const depositId = randomUUID();
    const depositRef = admin.firestore().collection('pawapay_deposits').doc(depositId);
    await depositRef.set({
      depositId,
      userId: uid,
      amount,
      phone,
      provider,
      reference: reference || depositId,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      const status = await sendDeposit(depositId, amount, phone, provider, reference || depositId);
      await depositRef.set({ providerStatus: status }, { merge: true });
      return { depositId, status, pending: true };
    } catch (err) {
      await depositRef.set(
        {
          status: 'failed',
          failure: err instanceof Error ? err.message : 'Payout failed',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw err;
    }
  },
);

const getPawaPayDepositStatus = onCall(
  {
    secrets: [pawapayApiToken],
    serviceAccount: 'vero360app-ca423@appspot.gserviceaccount.com',
  },
  async request => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
    const depositId = String((request.data && request.data.depositId) || '').trim();
    if (!depositId) throw new HttpsError('invalid-argument', 'Missing deposit.');

    const ref = admin.firestore().collection('pawapay_deposits').doc(depositId);
    const snap = await ref.get();
    const stored = snap.data() || {};
    if (!snap.exists || String(stored.userId || '') !== uid) {
      throw new HttpsError('not-found', 'Payment not found.');
    }

    const storedStatus = String(stored.status || '').toLowerCase();
    if (storedStatus === 'completed' || storedStatus === 'failed') {
      return {
        depositId,
        status: storedStatus,
        failure: stored.failure || '',
      };
    }

    let remote = {};
    let ok = false;
    try {
      const live = await pawapayRequest(`/v2/deposits/${encodeURIComponent(depositId)}`, {
        method: 'GET',
      });
      ok = live.ok;
      remote = paymentRecord(live.body);
    } catch (_) {
      return { depositId, status: 'pending' };
    }
    const status = paymentStatus(remote);
    if (!ok && !status) {
      return { depositId, status: 'pending' };
    }
    if (status === 'COMPLETED') {
      await ref.set(
        { status: 'completed', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
      return { depositId, status: 'completed' };
    }
    if (status === 'FAILED' || status === 'REJECTED') {
      const failure = failureMessage(remote);
      await ref.set(
        {
          status: 'failed',
          failure,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { depositId, status: 'failed', failure };
    }
    return { depositId, status: 'pending' };
  },
);

function callbackPayload(body) {
  if (!body || typeof body !== 'object') return null;
  if (body.payoutId || body.depositId) return body;
  const data = body.data;
  if (Array.isArray(data) && data[0] && typeof data[0] === 'object') return data[0];
  if (data && typeof data === 'object') return data;
  return body;
}

/** PawaPay v2 GET wraps the payment in { status: "FOUND", data: { status: "COMPLETED" } }. */
function paymentRecord(body) {
  if (!body || typeof body !== 'object') return {};
  const envelope = String(body.status || '').toUpperCase();
  let data = body.data;
  if (Array.isArray(data)) data = data[0];
  if (data && typeof data === 'object' && !Array.isArray(data)) return data;
  if (envelope === 'FOUND' || envelope === 'NOT_FOUND') return {};
  return body;
}

function paymentStatus(record) {
  return String((record && record.status) || '').toUpperCase();
}

const pawapayWebhook = onRequest(
  { invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }
    const payload = callbackPayload(req.body);
    const depositId = payload && typeof payload.depositId === 'string' ? payload.depositId.trim() : '';
    if (depositId) {
      const status = String(payload.status || '').toUpperCase();
      const next = status === 'COMPLETED' ? 'completed' : status === 'FAILED' || status === 'REJECTED' ? 'failed' : '';
      if (next) {
        await admin.firestore().collection('pawapay_deposits').doc(depositId).set(
          {
            status: next,
            failure: next === 'failed' ? failureMessage(payload) : null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      res.status(200).json({ ok: true });
      return;
    }
    const payoutId = payload && typeof payload.payoutId === 'string' ? payload.payoutId.trim() : '';
    if (!payoutId) {
      res.status(200).json({ ok: true, ignored: true });
      return;
    }
    const status = String(payload.status || '').toUpperCase();
    try {
      if (status === 'COMPLETED') {
        await releaseReserve(payoutId, 'completed');
      } else if (status === 'FAILED' || status === 'REJECTED') {
        await releaseReserve(payoutId, 'failed', failureMessage(payload));
      }
      res.status(200).json({ ok: true });
    } catch (err) {
      console.error('pawapayWebhook failed', err);
      res.status(500).json({ ok: false });
    }
  },
);

module.exports = {
  createPawaPayPayout,
  createPawaPayDeposit,
  getPawaPayDepositStatus,
  pawapayWebhook,
};
