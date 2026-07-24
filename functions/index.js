const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const ENGAGEMENT_TOPIC = 'vero360_engagement';

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
 * Morning + evening keep-alive digest for all users subscribed to
 * FCM topic `vero360_engagement` (app opts in via Settings).
 *
 * Schedule: 09:00 and 17:00 Africa/Blantyre (Malawi).
 * Deploy: firebase deploy --only functions:sendEngagementDigest
 */
exports.sendEngagementDigest = onSchedule(
  {
    schedule: '0 9,17 * * *',
    timeZone: 'Africa/Blantyre',
    retryCount: 1,
  },
  async () => {
    const since = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 12 * 60 * 60 * 1000),
    );

    let marketCount = 0;
    let sampleName = '';
    try {
      const snap = await admin
        .firestore()
        .collection('marketplace_items')
        .where('createdAt', '>', since)
        .orderBy('createdAt', 'desc')
        .limit(12)
        .get();
      marketCount = snap.size;
      if (!snap.empty) {
        const d = snap.docs[0].data() || {};
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
          } today. Open Vero360 to check them out.`;

    await admin.messaging().send({
      topic: ENGAGEMENT_TOPIC,
      notification: { title, body },
      data: {
        type: 'marketplace_digest',
        title,
        body,
      },
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
 * Manual / admin broadcast for a big promo or campaign.
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
