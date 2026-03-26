import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location_poc/firebase_options.dart';
import 'package:location_poc/models/location_model.dart';

// ─────────────────────────────────────────────────────────────
// Top-level entry point called by the native foreground service.
// Must be annotated so it survives tree-shaking in release mode.
// ─────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

// ─────────────────────────────────────────────────────────────
// Task handler — runs in a separate Dart isolate.
// Firebase must be re-initialised here because isolates don't
// share memory with the main isolate.
// ─────────────────────────────────────────────────────────────
class LocationTaskHandler extends TaskHandler {
  Timer? _timer;
  bool _firebaseReady = false;
  String? _uid;
  bool _initialUploadTriggered = false;

  void _log(String msg) {
    FlutterForegroundTask.sendDataToMain(msg);
  }

  @override
Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
  _log('Tracking service started');

  // ✅ Read UID from storage — available immediately, no race condition
  _uid = await FlutterForegroundTask.getData<String>(key: 'uid');
  if (_uid != null) {
    _log('Account loaded');
    _initialUploadTriggered = true;
    await _uploadLocation(); // safe to upload right away
  } else {
    _log('Waiting for account information');
  }

  _timer = Timer.periodic(const Duration(minutes: 5), (_) async {
    await _uploadLocation();
  });
}

  @override
  void onReceiveData(Object data) {
    if (data is String && data.trim().isNotEmpty) {
      final incomingUid = data.trim();
      final hadSameUid = _uid == incomingUid;
      _uid = incomingUid;
      _log('Account connected');

      // Avoid duplicate initial upload: onStart may already have uploaded with
      // the same uid loaded from storage.
      if (_initialUploadTriggered && hadSameUid) {
        _log('Initial upload already completed');
        return;
      }

      _initialUploadTriggered = true;
      unawaited(_uploadLocation());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Driven by the timer above; nothing needed here
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
  }

  // ── Helpers ────────────────────────────────────────────────

  Future<void> _initFirebase() async {
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _firebaseReady = true;
      _log('Cloud connection ready');
    } catch (e) {
      // Already initialised in the main isolate on hot-restart
      _firebaseReady = true;
      _log('Cloud connection ready');
    }
  }

  Future<void> _uploadLocation() async {
    _log('Uploading location...');
    try {
      await _initFirebase();

      final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _log('Upload skipped: account unavailable');
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log('Upload failed: GPS is off. Please enable location services.');
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _log('Upload failed: location permission is not granted.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );

      final model = LocationModel(latitude: position.latitude, longitude: position.longitude, timestamp: DateTime.now());

      await FirebaseFirestore.instance.collection('users').doc(uid).collection('locations').add(model.toMap(uid));
      _log('Location uploaded successfully');
    } on LocationServiceDisabledException {
      _log('Upload failed: GPS is off. Please enable location services.');
    } on FirebaseException catch (e) {
      _log('Upload failed: ${e.message ?? e.code}');
    } catch (_) {
      _log('Upload failed. Please try again.');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Public API used from the UI layer
// ─────────────────────────────────────────────────────────────
class BackgroundService {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(channelId: 'location_tracking', channelName: 'Location Tracking', channelDescription: 'Tracks your location every 5 minutes', onlyAlertOnce: true, playSound: false),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true, // restart after device reboot
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }
static Future<ServiceRequestResult> startService(String uid) async {
  if (await FlutterForegroundTask.isRunningService) {
    final result = await FlutterForegroundTask.restartService();
    // Delay slightly so the restarted isolate has time to call setTaskHandler
    await Future<void>.delayed(const Duration(milliseconds: 500));
    FlutterForegroundTask.sendDataToTask(uid);
    return result;
  }

  final result = await FlutterForegroundTask.startService(
    serviceId: 256,
    notificationTitle: 'Location Tracking Active',
    notificationText: 'Uploading your location every 5 minutes',
    callback: startCallback,
  );

  // Only send UID if service actually started
  if (result is ServiceRequestSuccess) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    FlutterForegroundTask.sendDataToTask(uid);
  }

  return result;
}

  static Future<ServiceRequestResult> stopService() {
    return FlutterForegroundTask.stopService();
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}
