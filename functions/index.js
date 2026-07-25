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
 * Frequent keep-alive digest for users subscribed to FCM topic
 * `vero360_engagement` (app opts in via Settings → Deals & new listings).
 *
 * Schedule: every 3 hours during the day (08,11,14,17,20) Africa/Blantyre.
 * Also fires on new marketplace listings (see onMarketplaceItemCreated) and
 * on docs written to engagement_broadcasts (promos / arrivals / campaigns).
 *
 * Deploy: firebase deploy --only functions:sendEngagementDigest,functions:onEngagementBroadcast,functions:onMarketplaceItemCreated
 */
exports.sendEngagementDigest = onSchedule(
  {
    schedule: '0 8,11,14,17,20 * * *',
    timeZone: 'Africa/Blantyre',
    retryCount: 1,
  },
  async () => {
    const since = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 4 * 60 * 60 * 1000),
    );

    let marketCount = 0;
    let sampleName = '';
    let sampleId = '';
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
        sampleId = snap.docs[0].id;
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
          } recently. Open Vero360 to check them out.`;

    const dataPayload = {
      type: 'marketplace_digest',
      title,
      body,
    };
    if (sampleId) dataPayload.marketplaceItemId = sampleId;

    await admin.messaging().send({
      topic: ENGAGEMENT_TOPIC,
      notification: { title, body },
      data: dataPayload,
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
 * Push when a marketplace item is created — keeps the app “alive”
 * as new products go live (with a short cooldown).
 */
exports.onMarketplaceItemCreated = onDocumentCreated(
  'marketplace_items/{id}',
  async (event) => {
    const data = event.data?.data() || {};
    const name = String(
      data.name || data.title || data.productName || '',
    ).trim();

    const cooldownRef = admin
      .firestore()
      .collection('engagement_meta')
      .doc('cooldowns');
    const meta = await cooldownRef.get();
    const lastMs = Number((meta.data() || {}).marketplace || 0);
    const COOLDOWN_MS = 15 * 60 * 1000; // 15 minutes
    const nowMs = Date.now();
    if (lastMs > 0 && nowMs - lastMs < COOLDOWN_MS) {
      console.log('Marketplace engagement push skipped (cooldown)');
      return;
    }
    await cooldownRef.set({ marketplace: nowMs }, { merge: true });

    const title = 'New on Marketplace';
    const body =
      name.length > 0
        ? `Just listed: ${name}. Open Vero360 to browse.`
        : 'New listings just went live. Open Vero360 to browse.';

    const itemId = String(event.params.id || '').trim();
    const dataPayload = {
      type: 'marketplace_digest',
      title,
      body,
    };
    if (itemId) dataPayload.marketplaceItemId = itemId;

    await admin.messaging().send({
      topic: ENGAGEMENT_TOPIC,
      notification: { title, body },
      data: dataPayload,
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

    console.log(`Marketplace engagement push sent: ${name || event.params.id}`);
  },
);

/**
 * Manual / admin / app broadcast for a promo, arrival, or campaign.
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
    // Deep-link ids (all FCM data values must be strings).
    for (const key of ['promoId', 'arrivalId', 'marketplaceItemId', 'itemId', 'id']) {
      const v = data[key];
      if (v !== undefined && v !== null && String(v).trim()) {
        payload[key] = String(v).trim();
      }
    }

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
