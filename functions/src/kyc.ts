/**
 * TypeScript reference for createDiditSession.
 * Production deploy uses functions/index.js + functions/didit_webhook.js
 * (full X-Signature-V2 / raw / simple verification + event dispatch).
 */
import { defineSecret } from 'firebase-functions/params';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import axios from 'axios';

if (!admin.apps.length) {
  admin.initializeApp();
}

export const diditApiKey = defineSecret('DIDIT_API_KEY');
export const diditWorkflowId = defineSecret('DIDIT_WORKFLOW_ID');

type DiditSessionResponse = {
  session_id?: string;
  session_token?: string;
  url?: string;
  session_url?: string;
  [key: string]: unknown;
};

/**
 * Creates a Didit KYC session for the signed-in user and returns session_token
 * for the Flutter hosted verification WebView.
 *
 * Webhook receiver: see ../didit_webhook.js → exports.diditWebhook
 */
export const createDiditSession = onCall(
  {
    secrets: [diditApiKey, diditWorkflowId],
    serviceAccount: 'vero360app-ca423@appspot.gserviceaccount.com',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }

    const workflowId = String(diditWorkflowId.value() || '').trim();
    if (!workflowId) {
      throw new HttpsError(
        'failed-precondition',
        'DIDIT_WORKFLOW_ID is not configured on the server.',
      );
    }

    let data: DiditSessionResponse;
    try {
      const res = await axios.post<DiditSessionResponse>(
        'https://verification.didit.me/v3/session/',
        {
          workflow_id: workflowId,
          vendor_data: uid,
          callback: 'vero360://kyc-complete',
          // Didit expects ISO 3166-1 alpha-3 (Malawi = MWI, not MW).
          expected_details: { country: 'MWI' },
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
      const status = axios.isAxiosError(err) ? err.response?.status : undefined;
      const body = axios.isAxiosError(err) ? err.response?.data : undefined;
      console.error('Didit session create failed', status, body || err);
      let detail = '';
      if (body && typeof body === 'object') {
        const o = body as Record<string, unknown>;
        detail = String(
          o.detail || o.message || o.error || JSON.stringify(body),
        ).slice(0, 240);
      } else if (typeof body === 'string') {
        detail = body.slice(0, 240);
      }
      // Do NOT use 'internal' — Firebase strips its message from clients.
      throw new HttpsError(
        'failed-precondition',
        detail
          ? `Didit rejected session (${status || '?'}): ${detail}`
          : `Didit session failed (${status || 'network'}). Set DIDIT_API_KEY + DIDIT_WORKFLOW_ID and redeploy createDiditSession.`,
      );
    }

    const sessionId = data.session_id;
    const sessionToken = data.session_token;
    if (!sessionId || !sessionToken) {
      console.error('Didit session response missing fields', data);
      throw new HttpsError(
        'failed-precondition',
        'Didit response missing session_token. Check API key / workflow.',
      );
    }

    await admin.firestore().collection('users').doc(uid).set(
      {
        kycStatus: 'pending',
        kycSessionId: sessionId,
        kycVerified: false,
      },
      { merge: true },
    );

    const url =
      (typeof data.url === 'string' && data.url) ||
      (typeof data.session_url === 'string' && data.session_url) ||
      `https://verify.didit.me/session/${sessionToken}`;

    return { session_token: sessionToken, url, session_id: sessionId };
  },
);
