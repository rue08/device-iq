import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'home_screen.dart';
import 'sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No FirebaseOptions passed: on Android, firebase_core reads them from
  // android/app/google-services.json via the Google Services Gradle plugin
  // (wired up in android/app/build.gradle.kts) - see mobile/README.md for
  // the one-time setup step to generate that file.
  await Firebase.initializeApp();
  runApp(const DeviceIqApp());
}

class DeviceIqApp extends StatelessWidget {
  const DeviceIqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeviceIQ',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      // Follows the phone's system light/dark setting.
      themeMode: ThemeMode.system,
      home: StreamBuilder(
        stream: AuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data == null ? const SignInScreen() : const HomeScreen();
        },
      ),
    );
  }
}
