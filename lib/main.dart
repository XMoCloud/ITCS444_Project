import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _quickFirebaseTest();
  }

  Future<void> _quickFirebaseTest() async {
    try {
      setState(() => _status = 'Signing in anonymously...');
      final userCred = await FirebaseAuth.instance.signInAnonymously();
      final uid = userCred.user?.uid;
      setState(() => _status = 'Signed in (uid: $uid). Writing to Firestore...');

      await FirebaseFirestore.instance.collection('test').doc('ping').set({
        'ts': FieldValue.serverTimestamp(),
        'uid': uid,
      });

      setState(() => _status = 'Success: wrote ping document (uid: $uid)');
      // Also print to console for DevTools
      // ignore: avoid_print
      print('Firebase test succeeded for uid: $uid');
    } catch (e, st) {
      // Print detailed error to console and show short message in UI
      // ignore: avoid_print
      print('Firebase test failed: $e');
      // ignore: avoid_print
      print(st);
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Firebase Quick Test')),
        body: Center(child: Text(_status)),
      ),
    );
  }
}
