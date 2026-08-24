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

FirebaseOptions get kFirebaseOptions {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
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

Future<bool>? _ensureInFlight;

/// Safe to call from services before Auth / Firestore / Storage.
/// Retries briefly so refunds / occupancy do not hit `core/no-app`.
Future<bool> ensureFirebaseApp({int maxAttempts = 3}) async {
  if (isFirebaseAppReady) return true;
  if (_ensureInFlight != null) return _ensureInFlight!;

  _ensureInFlight = () async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: kFirebaseOptions);
        }
        Firebase.app();
        return true;
      } catch (_) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 160 * attempt));
        }
      }
    }
    return false;
  }();

  final ok = await _ensureInFlight!;
  if (!ok) _ensureInFlight = null;
  return ok;
}
