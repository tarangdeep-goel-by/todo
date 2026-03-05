// File generated from Firebase project todo-3a0ae.
// flutterfire configure --project=todo-3a0ae

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDyD8MWR8_-_hpTKCtzGjokPMGtOyoiSOE',
    appId: '1:712442635351:android:46e1daecfecf428b652f12',
    messagingSenderId: '712442635351',
    projectId: 'todo-3a0ae',
    storageBucket: 'todo-3a0ae.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAhikUc9g-MDgFpIVVBEJbs0M_n0eRnU-Y',
    appId: '1:712442635351:ios:6fdc076f8806f9a3652f12',
    messagingSenderId: '712442635351',
    projectId: 'todo-3a0ae',
    storageBucket: 'todo-3a0ae.firebasestorage.app',
    iosBundleId: 'com.amble.app',
  );
}
