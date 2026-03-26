import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location_poc/auth/login_screen.dart';
import 'package:location_poc/firebase_options.dart';
import 'package:location_poc/screens/home_screen.dart';
import 'package:location_poc/services/background_service.dart';
import 'package:location_poc/services/location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  // Request permissions to use the notification for the foreground service
  await FlutterForegroundTask.requestNotificationPermission();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialise foreground task config
  BackgroundService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocationPOC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)), useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final LocationService _locationService = LocationService();
  bool _requestedAppLocationPermissions = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedAppLocationPermissions) return;
    _requestedAppLocationPermissions = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _locationService.requestLocationPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F0F1A),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
          );
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
