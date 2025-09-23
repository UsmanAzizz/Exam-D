import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'run_test.dart'; // Sesuaikan path-nya jika perlu
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Platform belum didukung');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB0z9M1q7m4HQPf1zU03nw5uBMyIgjReUc',
    appId: '1:541596506756:android:93731de2456752bf2480d1',
    messagingSenderId: '541596506756',
    projectId: 'mutingsky',
    storageBucket: 'mutingsky.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB0z9M1q7m4HQPf1zU03nw5uBMyIgjReUc',
    appId: '1:541596506756:ios:78a4f13460c7ac372480d1',
    messagingSenderId: '541596506756',
    projectId: 'mutingsky',
    storageBucket: 'mutingsky.appspot.com',
    iosBundleId: 'BUNDLE_ID',
    iosClientId: 'CLIENT_ID',
    androidClientId: 'ANDROID_CLIENT_ID',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyCVAjs0v1r5rpehnZ30lyCH8ZufKrCYJIY",
    authDomain: "mutingsky.firebaseapp.com",
    databaseURL:
        "https://mutingsky-default-rtdb.asia-southeast1.firebasedatabase.app",
    projectId: "mutingsky",
    storageBucket: "mutingsky.appspot.com",
    messagingSenderId: "541596506756",
    appId: "1:541596506756:web:8b5982b01c6d03402480d1",
    measurementId: "G-9LGN757SGT",
  );
}

class RemoteAccess extends StatefulWidget {
  const RemoteAccess({Key? key}) : super(key: key);

  @override
  State<RemoteAccess> createState() => _RemoteAccessState();
}

class _RemoteAccessState extends State<RemoteAccess> {
  late final Future<FirebaseApp> _firebaseInitFuture;

  @override
  void initState() {
    super.initState();
    _firebaseInitFuture = _initializeFirebase();
  }

  Future<FirebaseApp> _initializeFirebase() async {
    // Cek apakah Firebase sudah diinisialisasi
    if (Firebase.apps.isNotEmpty) {
      // Firebase sudah ada, tinggal kembalikan app default
      return Firebase.app();
    }

    // Belum ada, inisialisasi baru
    FirebaseApp app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Setting Firestore (persistence bisa true atau false sesuai kebutuhan)
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);

    // Login anonim supaya rules yang membutuhkan auth terpenuhi
    await FirebaseAuth.instance.signInAnonymously();

    return app;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _firebaseInitFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Gagal inisialisasi Firebase:\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Setelah Firebase siap, panggil Firestore
        final remoteDoc = FirebaseFirestore.instance
            .collection('remote')
            .doc('remote_access');

        return Scaffold(
          body: FutureBuilder<DocumentSnapshot>(
            future: remoteDoc.get(),
            builder: (context, docSnap) {
              if (docSnap.hasError) {
                debugPrint('Error memuat data: ${docSnap.error}');
                return Center(
                  child: Text(
                    'Error memuat data:\n${docSnap.error}',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              if (docSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!docSnap.hasData || !docSnap.data!.exists) {
                debugPrint(
                    'Data tidak ditemukan pada dokumen remote/remote_access');
                return const Center(child: Text('Data tidak ditemukan.'));
              }

              final data = docSnap.data!.data();
              if (data == null || data is! Map<String, dynamic>) {
                debugPrint('Data dokumen null atau format tidak sesuai');
                return const Center(child: Text('Data tidak valid.'));
              }

              final linkRaw = data['link'];
              final link = linkRaw != null ? linkRaw.toString().trim() : '';

              if (link.isEmpty) {
                debugPrint('Link pada dokumen kosong');
                return const Center(child: Text('Link tidak tersedia.'));
              }

              // Langsung navigasi ke RunTest jika link valid
              // Gunakan addPostFrameCallback supaya tidak panggil Navigator saat build berlangsung
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => RunTest(ipAddress: link)),
                );
              });

              // Tampilkan loading atau kosong sementara menunggu navigasi
              return const Center(child: CircularProgressIndicator());
            },
          ),
        );
      },
    );
  }
}
