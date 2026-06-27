const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

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
