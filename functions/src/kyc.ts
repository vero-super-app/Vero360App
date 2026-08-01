import { createHmac, timingSafeEqual } from 'crypto';
import { defineSecret } from 'firebase-functions/params';
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import axios from 'axios';

if (!admin.apps.length) {
  admin.initializeApp();
}

/** Cloud Secret Manager only — never Flutter, .env, or source control. */
export const diditApiKey = defineSecret('DIDIT_API_KEY');
export const diditWebhookSecret = defineSecret('DIDIT_WEBHOOK_SECRET');

type DiditSessionResponse = {
  session_id?: string;
  session_token?: string;
  [key: string]: unknown;
};

type DiditWebhookPayload = {
  session_id?: string;
  status?: string;
  vendor_data?: string;
  decision?: Record<string, unknown>;
  [key: string]: unknown;
};

/**
 * Creates a Didit KYC session for the signed-in user and returns session_token
 * for the Flutter Didit SDK.
 */
export const createDiditSession = onCall(
  { secrets: [diditApiKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }

    let data: DiditSessionResponse;
    try {
      const res = await axios.post<DiditSessionResponse>(
        'https://verification.didit.me/v3/session/',
        {
          vendor_data: uid,
          // ID verification (OCR) + face match + liveness
          features: 'OCR + FACE',
          expected_details: { country: 'MW' },
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'X-Api-Key': diditApiKey.value(),
          },
        },
      );
      data = res.data;
    } catch (err) {
      if (axios.isAxiosError(err)) {
        console.error(
          'Didit session create failed',
          err.response?.status,
          err.response?.data,
        );
      } else {
        console.error('Didit session create failed', err);
      }
      throw new HttpsError('internal', 'Could not start identity verification.');
    }

    const sessionId = data.session_id;
    const sessionToken = data.session_token;
    if (!sessionId || !sessionToken) {
      console.error('Didit session response missing fields', data);
      throw new HttpsError('internal', 'Invalid Didit session response.');
    }

    await admin.firestore().collection('users').doc(uid).set(
      {
        kycStatus: 'pending',
        kycSessionId: sessionId,
      },
      { merge: true },
    );

    return { session_token: sessionToken };
  },
);

function constantTimeEqualHex(a: string, b: string): boolean {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

/** Pull human-readable decline reasons from Didit decision warnings. */
function extractRejectionReason(decision: Record<string, unknown> | undefined): string {
  if (!decision || typeof decision !== 'object') {
    return 'Verification declined';
  }

  const reasons: string[] = [];
  for (const value of Object.values(decision)) {
    if (!Array.isArray(value)) continue;
    for (const item of value) {
      if (!item || typeof item !== 'object') continue;
      const warnings = (item as { warnings?: unknown }).warnings;
      if (!Array.isArray(warnings)) continue;
      for (const warning of warnings) {
        if (!warning || typeof warning !== 'object') continue;
        const w = warning as {
          short_description?: unknown;
          long_description?: unknown;
          risk?: unknown;
        };
        const text =
          (typeof w.short_description === 'string' && w.short_description) ||
          (typeof w.long_description === 'string' && w.long_description) ||
          (typeof w.risk === 'string' && w.risk) ||
          '';
        if (text.trim()) reasons.push(text.trim());
      }
    }
  }

  return reasons.length ? reasons.join('; ') : 'Verification declined';
}

/**
 * Public Didit webhook. Verifies HMAC over the raw body + timestamp freshness,
 * then updates users/{vendor_data} KYC fields. No Firebase Auth.
 */
export const diditWebhook = onRequest(
  {
    secrets: [diditWebhookSecret],
    invoker: 'public',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const signature = req.get('X-Signature') || '';
    const timestampHeader = req.get('X-Timestamp') || '';
    const rawBodyBuf = req.rawBody;

    if (!signature || !timestampHeader || !rawBodyBuf?.length) {
      res.status(401).send('Unauthorized');
      return;
    }

    const timestamp = Number.parseInt(timestampHeader, 10);
    if (!Number.isFinite(timestamp)) {
      res.status(401).send('Unauthorized');
      return;
    }

    const nowSec = Math.floor(Date.now() / 1000);
    if (Math.abs(nowSec - timestamp) > 300) {
      res.status(401).send('Unauthorized');
      return;
    }

    const expected = createHmac('sha256', diditWebhookSecret.value())
      .update(rawBodyBuf)
      .digest('hex');

    if (!constantTimeEqualHex(expected, signature)) {
      res.status(401).send('Unauthorized');
      return;
    }

    let payload: DiditWebhookPayload;
    try {
      payload = JSON.parse(rawBodyBuf.toString('utf8')) as DiditWebhookPayload;
    } catch {
      res.status(401).send('Unauthorized');
      return;
    }

    const sessionId =
      typeof payload.session_id === 'string' ? payload.session_id.trim() : '';
    const status =
      typeof payload.status === 'string' ? payload.status.trim() : '';
    const uid =
      typeof payload.vendor_data === 'string' ? payload.vendor_data.trim() : '';
    const decision =
      payload.decision && typeof payload.decision === 'object'
        ? (payload.decision as Record<string, unknown>)
        : undefined;

    if (!uid || !sessionId || !status) {
      console.warn('Didit webhook missing session_id/status/vendor_data');
      res.status(400).send('Bad Request');
      return;
    }

    const userRef = admin.firestore().collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      console.warn(`Didit webhook: no user for vendor_data=${uid}`);
      res.status(404).send('Not Found');
      return;
    }

    const update: Record<string, unknown> = {
      kycSessionId: sessionId,
      kycUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    switch (status) {
      case 'Approved':
        update.kycStatus = 'verified';
        update.kycRejectionReason = admin.firestore.FieldValue.delete();
        break;
      case 'Declined':
        update.kycStatus = 'rejected';
        update.kycRejectionReason = extractRejectionReason(decision);
        break;
      case 'In Review':
        update.kycStatus = 'pending';
        break;
      default:
        // Ignore other statuses (Not Started, In Progress, etc.) after auth.
        res.status(200).json({ ok: true, ignored: status });
        return;
    }

    await userRef.set(update, { merge: true });
    console.log(`Didit webhook: uid=${uid} status=${status} session=${sessionId}`);
    res.status(200).json({ ok: true });
  },
);
