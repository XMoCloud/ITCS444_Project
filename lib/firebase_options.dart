// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAOG-U0a43-bkM_mhwAXHOOcy5nmAVsZKE',
    authDomain: 'itcs444-89d10.firebaseapp.com',
    projectId: 'itcs444-89d10',
    storageBucket: 'itcs444-89d10.firebasestorage.app',
    messagingSenderId: '559277700334',
    appId: '1:559277700334:web:REPLACE_WITH_WEB_APP_ID',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAOG-U0a43-bkM_mhwAXHOOcy5nmAVsZKE',
    appId: '1:559277700334:android:4e1ed58659dfbdb8c2efff',
    messagingSenderId: '559277700334',
    projectId: 'itcs444-89d10',
    storageBucket: 'itcs444-89d10.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
    iosClientId: '',
    iosBundleId: '',
  );
}
