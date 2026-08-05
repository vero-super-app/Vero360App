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

type DiditSessionResponse = {
  session_id?: string;
  session_token?: string;
  [key: string]: unknown;
};

/**
 * Creates a Didit KYC session for the signed-in user and returns session_token
 * for the Flutter Didit SDK.
 *
 * Webhook receiver: see ../didit_webhook.js → exports.diditWebhook
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
        kycVerified: false,
      },
      { merge: true },
    );

    return { session_token: sessionToken };
  },
);
