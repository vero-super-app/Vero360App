import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

const FirebaseOptions kFirebaseOptionsAndroid = FirebaseOptions(
  apiKey: 'AIzaSyCQ5_4N2J_xwKqmY-lAa8-ifRxovoRTTYk',
  authDomain: 'vero360app-ca423.firebaseapp.com',
  projectId: 'vero360app-ca423',
  storageBucket: 'vero360app-ca423.firebasestorage.app',
  messagingSenderId: '1010595167807',
  appId: '1:1010595167807:android:86f213f63fa2f8391dc28a',
);

const FirebaseOptions kFirebaseOptionsIos = FirebaseOptions(
  apiKey: 'AIzaSyBJX498cAin_BXc_IAvs_spisGl2kKtuCE',
  authDomain: 'vero360app-ca423.firebaseapp.com',
  databaseURL: 'https://vero360app-ca423-default-rtdb.firebaseio.com',
  projectId: 'vero360app-ca423',
  storageBucket: 'vero360app-ca423.firebasestorage.app',
  messagingSenderId: '1010595167807',
  appId: '1:1010595167807:ios:83dcb52c7e1285251dc28a',
  iosBundleId: 'com.vero265.app',
);

/// Same project as the native apps. The PWA is an extra client, not a replacement.
const FirebaseOptions kFirebaseOptionsWeb = FirebaseOptions(
  apiKey: 'AIzaSyCQ5_4N2J_xwKqmY-lAa8-ifRxovoRTTYk',
  authDomain: 'vero360app-ca423.firebaseapp.com',
  projectId: 'vero360app-ca423',
  storageBucket: 'vero360app-ca423.firebasestorage.app',
  messagingSenderId: '1010595167807',
  appId: '1:1010595167807:android:f63d7c7959bdb2891dc28a',
);

FirebaseOptions get kFirebaseOptions {
  if (kIsWeb) return kFirebaseOptionsWeb;
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return kFirebaseOptionsIos;
  }
  return kFirebaseOptionsAndroid;
}

bool get isFirebaseAppReady {
  try {
    return Firebase.apps.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Never throw `[core/no-app]` during launch. Returns null until Firebase is up.
FirebaseAuth? tryFirebaseAuth() {
  if (!isFirebaseAppReady) return null;
  try {
    return FirebaseAuth.instance;
  } catch (_) {
    return null;
  }
}

User? tryFirebaseUser() {
  try {
    return tryFirebaseAuth()?.currentUser;
  } catch (_) {
    return null;
  }
}

Future<bool>? _ensureInFlight;

/// Safe to call from services before Auth / Firestore / Storage.
/// Retries briefly so refunds / occupancy do not hit `core/no-app`.
Future<bool> ensureFirebaseApp({
  int maxAttempts = 3,
  Duration attemptTimeout = const Duration(seconds: 4),
}) async {
  if (isFirebaseAppReady) return true;
  if (_ensureInFlight != null) return _ensureInFlight!;

  _ensureInFlight = () async {
    // iOS AppDelegate already calls FirebaseApp.configure(). Give the Dart
    // plugin a brief moment to see that app so we do not start a second init.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      for (var i = 0; i < 6 && !isFirebaseAppReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if (isFirebaseAppReady) return true;
    }

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: kFirebaseOptions)
              .timeout(attemptTimeout);
        }
        Firebase.app();
        return true;
      } catch (e) {
        final text = e.toString();
        // Native already created DEFAULT — treat as success.
        if (text.contains('duplicate-app') || isFirebaseAppReady) {
          return true;
        }
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 160 * attempt));
        }
      }
    }
    return isFirebaseAppReady;
  }();

  final ok = await _ensureInFlight!;
  if (!ok) _ensureInFlight = null;
  return ok;
}
