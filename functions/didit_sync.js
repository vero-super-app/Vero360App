/**
 * Pull Didit session status into Firestore when the webhook is missed
 * or createDiditSession overwrote a completed approval with pending.
 */
const axios = require('axios');
const admin = require('firebase-admin');
const {
  applySessionEvent,
  kycFieldsForStatus,
  normalizeSessionStatus,
} = require('./didit_webhook');

function diditHeaders(apiKey) {
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-Api-Key': apiKey,
    'x-api-key': apiKey,
  };
}

function sessionRank(status) {
  switch (normalizeSessionStatus(status)) {
    case 'Approved':
      return 50;
    case 'In Review':
      return 40;
    case 'Resubmitted':
      return 30;
    case 'In Progress':
      return 20;
    case 'Not Started':
      return 10;
    case 'Declined':
      return 5;
    case 'Abandoned':
      return 3;
    case 'Expired':
    case 'KYC Expired':
      return 2;
    default:
      return 0;
  }
}

function unlocksApp(status) {
  const s = normalizeSessionStatus(status);
  return s === 'Approved' || s === 'In Review';
}

function sessionIdOf(row) {
  return String((row && (row.session_id || row.id)) || '').trim();
}

function sessionUrlOf(row) {
  return String((row && (row.session_url || row.url)) || '').trim();
}

function sessionTokenOf(row) {
  return String((row && (row.session_token || row.token)) || '').trim();
}

function pickBestSession(sessions) {
  if (!Array.isArray(sessions) || !sessions.length) return null;
  return sessions.slice().sort((a, b) => {
    const rankDiff = sessionRank(b && b.status) - sessionRank(a && a.status);
    if (rankDiff) return rankDiff;
    const ta = Date.parse((a && (a.created_at || a.createdAt)) || 0) || 0;
    const tb = Date.parse((b && (b.created_at || b.createdAt)) || 0) || 0;
    return tb - ta;
  })[0];
}

async function diditGet(apiKey, path, params) {
  return axios.get(`https://verification.didit.me${path}`, {
    headers: diditHeaders(apiKey),
    params: params || undefined,
    timeout: 15000,
    validateStatus: (status) => status < 500,
  });
}

async function listSessionsByVendor(apiKey, uid) {
  const sessions = [];
  try {
    const res = await diditGet(apiKey, '/v3/sessions/', {
      vendor_data: uid,
      session_kind: 'user',
      limit: 50,
    });
    if (res.status !== 200) {
      console.warn('Didit list sessions HTTP', res.status);
      return sessions;
    }
    const data = res.data || {};
    const rows = data.results || data.sessions || (Array.isArray(data) ? data : []);
    for (const row of rows) {
      if (row && typeof row === 'object') sessions.push(row);
    }
  } catch (err) {
    console.warn('Didit list sessions failed', err && err.message);
  }
  return sessions;
}

async function retrieveSession(apiKey, sessionId) {
  if (!sessionId) return null;
  const paths = [
    `/v3/session/${encodeURIComponent(sessionId)}/decision/`,
    `/v3/session/${encodeURIComponent(sessionId)}/`,
  ];
  for (const path of paths) {
    try {
      const res = await diditGet(apiKey, path);
      if (res.status === 200 && res.data && typeof res.data === 'object') {
        return res.data;
      }
    } catch (err) {
      console.warn('Didit retrieve failed', path, err && err.message);
    }
  }
  return null;
}

async function getDiditUser(apiKey, uid) {
  try {
    const res = await diditGet(
      apiKey,
      `/v3/users/${encodeURIComponent(uid)}/`,
    );
    if (res.status === 200 && res.data && typeof res.data === 'object') {
      return res.data;
    }
  } catch (err) {
    console.warn('Didit get user failed', err && err.message);
  }
  return null;
}

async function applyDiditSession(uid, session) {
  if (!session) return { ok: false };
  return applySessionEvent(
    {
      session_id: sessionIdOf(session),
      vendor_data: uid,
      status: session.status,
      decision:
        session.decision && typeof session.decision === 'object'
          ? session.decision
          : undefined,
      webhook_type: 'status.updated',
    },
    !!(session.decision && typeof session.decision === 'object'),
  );
}

function firestoreAlreadyVerified(snap) {
  if (!snap || !snap.exists) return false;
  if (snap.get('kycVerified') === true) return true;
  const status = String(snap.get('kycStatus') || '').toLowerCase();
  return status === 'verified' || status === 'approved';
}

async function syncUidFromDidit(uid, apiKey) {
  const userRef = admin.firestore().collection('users').doc(uid);
  const snap = await userRef.get();
  const storedId = snap.exists ? String(snap.get('kycSessionId') || '').trim() : '';
  const storedUrl = snap.exists
    ? String(snap.get('kycSessionUrl') || '').trim()
    : '';
  const alreadyVerified = firestoreAlreadyVerified(snap);

  const sessions = await listSessionsByVendor(apiKey, uid);
  if (storedId && !sessions.some((row) => sessionIdOf(row) === storedId)) {
    const one = await retrieveSession(apiKey, storedId);
    if (one) sessions.push(one);
  }

  let best = pickBestSession(sessions);

  if (!best || !unlocksApp(best.status)) {
    const entity = await getDiditUser(apiKey, uid);
    if (
      entity &&
      (Number(entity.approved_count) > 0 || Number(entity.in_review_count) > 0)
    ) {
      const syntheticStatus =
        Number(entity.approved_count) > 0 ? 'Approved' : 'In Review';
      if (!best || sessionRank(syntheticStatus) > sessionRank(best.status)) {
        best = {
          session_id: storedId || sessionIdOf(best) || null,
          status: syntheticStatus,
          session_url: storedUrl || sessionUrlOf(best),
          session_token: sessionTokenOf(best),
        };
      }
    }
  }

  if (best) {
    await applyDiditSession(uid, best);
  }

  const fields = best
    ? kycFieldsForStatus(best.status, best.decision, !!best.decision)
    : null;
  const verified =
    alreadyVerified ||
    !!(fields && fields.kycVerified) ||
    !!(best && unlocksApp(best.status));

  return {
    verified,
    status: verified
      ? 'verified'
      : (fields && fields.kycStatus) ||
        (snap.exists && snap.get('kycStatus')) ||
        'pending',
    session_id: (best && sessionIdOf(best)) || storedId || null,
    session_url: (best && sessionUrlOf(best)) || storedUrl || null,
    session_token: (best && sessionTokenOf(best)) || null,
    didit_status: best ? normalizeSessionStatus(best.status) : null,
  };
}

async function listCompletedDiditSessions(apiKey) {
  const rows = [];
  let offset = 0;
  for (let page = 0; page < 40; page += 1) {
    let batch = [];
    try {
      const res = await diditGet(apiKey, '/v3/sessions/', {
        status: 'Approved,In Review',
        session_kind: 'user',
        limit: 50,
        offset,
      });
      if (res.status !== 200) {
        console.warn('Didit backfill list HTTP', res.status);
        break;
      }
      const data = res.data || {};
      batch = data.results || data.sessions || [];
    } catch (err) {
      console.warn('Didit backfill list failed', err && err.message);
      break;
    }
    if (!Array.isArray(batch) || !batch.length) break;
    rows.push(...batch);
    offset += batch.length;
    if (batch.length < 50) break;
  }
  return rows;
}

async function backfillCompletedDiditKyc(apiKey) {
  const updated = [];
  const seen = new Set();

  const completed = await listCompletedDiditSessions(apiKey);
  for (const session of completed) {
    const uid = String((session && session.vendor_data) || '').trim();
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    try {
      await applyDiditSession(uid, session);
      updated.push(uid);
    } catch (err) {
      console.warn('Didit backfill apply failed', uid, err && err.message);
    }
  }

  const pendingStatuses = [
    'pending',
    'in_progress',
    'pending_review',
    'in_review',
    'submitted',
    'resubmitted',
  ];
  for (const status of pendingStatuses) {
    const qs = await admin
      .firestore()
      .collection('users')
      .where('kycStatus', '==', status)
      .limit(100)
      .get();
    for (const doc of qs.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      try {
        const result = await syncUidFromDidit(doc.id, apiKey);
        if (result.verified) updated.push(doc.id);
      } catch (err) {
        console.warn('Didit pending sync failed', doc.id, err && err.message);
      }
    }
  }

  return { checked: seen.size, updated: updated.length };
}

module.exports = {
  syncUidFromDidit,
  backfillCompletedDiditKyc,
  unlocksApp,
  sessionUrlOf,
  sessionIdOf,
  firestoreAlreadyVerified,
};
