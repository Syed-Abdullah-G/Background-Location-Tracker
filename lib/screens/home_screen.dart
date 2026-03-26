import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location_poc/services/background_service.dart';
import 'package:location_poc/services/firebase_service.dart';
import 'package:location_poc/services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isTracking = false;
  bool _isLoading = false;
  bool _didPromptGpsOnOpen = false;
  final LocationService _locationService = LocationService();
  final List<String> _logs = [];
  final ScrollController _logScroll = ScrollController();

  void _onTaskData(Object data) {
    final msg = '[${TimeOfDay.now().format(context)}] $data';
    if (mounted) {
      setState(() => _logs.add(msg));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _syncServiceState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptGpsOnLogin();
    });
  }

  Future<void> _promptGpsOnLogin() async {
    if (!mounted || _didPromptGpsOnOpen) return;
    _didPromptGpsOnOpen = true;

    final serviceEnabled = await _locationService.isLocationServiceEnabled();
    if (serviceEnabled || !mounted) return;

    final openSettings = await _showEnableGpsDialog(
      title: 'Turn On Location',
      content: 'Please turn on device location (GPS) so tracking can work properly.',
      cancelText: 'Later',
    );

    if (openSettings == true) {
      await _locationService.openLocationSettings();
    }
  }

  Future<bool?> _showEnableGpsDialog({
    required String title,
    required String content,
    required String cancelText,
  }) async {
    Timer? watcher;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        watcher ??= Timer.periodic(const Duration(seconds: 1), (_) async {
          final enabled = await _locationService.isLocationServiceEnabled();
          if (enabled && mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop(true);
          }
        });

        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelText),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
    watcher?.cancel();
    return result;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _syncServiceState() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) setState(() => _isTracking = running);
  }

  Future<void> _toggleTracking() async {
  setState(() => _isLoading = true);
  try {
    if (_isTracking) {
      await BackgroundService.stopService();
      setState(() => _isTracking = false);
    } else {
      final serviceEnabled = await _locationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final openSettings = await _showEnableGpsDialog(
          title: 'Enable Location',
          content: 'Location service is turned off. Please enable GPS to start tracking.',
          cancelText: 'Cancel',
        );

        if (openSettings != true) {
          if (mounted) {
            setState(() {
              _logs.add('[${TimeOfDay.now().format(context)}] Tracking not started: GPS is off');
            });
          }
          return;
        }

        await _locationService.openLocationSettings();
        final enabledAfterSettings = await _locationService.isLocationServiceEnabled();
        if (!enabledAfterSettings) {
          if (mounted) {
            setState(() {
              _logs.add('[${TimeOfDay.now().format(context)}] Tracking not started: GPS is still off');
            });
          }
          return;
        }
      }

      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        final requested = await FlutterForegroundTask.requestNotificationPermission();
        if (requested != NotificationPermission.granted) {
          throw Exception('Notification permission not granted: $requested');
        }
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('No authenticated user found');

      // ✅ Always init the port before starting the service
      await FlutterForegroundTask.saveData(key: 'uid', value: uid);

      FlutterForegroundTask.initCommunicationPort();

      final result = await BackgroundService.startService(uid);

      if (result is ServiceRequestFailure) {
        final error = result.error;
        if (error is ServiceTimeoutException) {
          // give android extra time then re-check
          await Future<void>.delayed(const Duration(seconds: 5));
          final isRunning = await FlutterForegroundTask.isRunningService;
          if (isRunning) {
            // ✅ Don't return early without updating state properly
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Service started (delayed confirmation)')),
              );
              setState(() => _isTracking = true);
            }
            return;
          }
        }

        // Only request battery optimization after a real failure
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }

throw error;      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service started successfully')),
        );
        setState(() => _isTracking = true);
      }
    }
  } catch (e) {
    if (mounted) {
      print(  'Error in _toggleTracking: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text(
          'LocationPOC',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            tooltip: 'Sign Out',
            onPressed: () async {
              if (_isTracking) await BackgroundService.stopService();
              await FirebaseService().signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_isTracking ? const Color(0xFF3ECFCF) : const Color(0xFF6C63FF)).withValues(alpha: 0.12),
                border: Border.all(color: _isTracking ? const Color(0xFF3ECFCF) : const Color(0xFF6C63FF), width: 2),
              ),
              child: Icon(_isTracking ? Icons.location_on_rounded : Icons.location_off_rounded, size: 52, color: _isTracking ? const Color(0xFF3ECFCF) : const Color(0xFF6C63FF)),
            ),
            const SizedBox(height: 24),

            // Status text
            Text(
              _isTracking ? 'Tracking Active' : 'Tracking Stopped',
              style: TextStyle(color: _isTracking ? const Color(0xFF3ECFCF) : Colors.white.withValues(alpha: 0.6), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(_isTracking ? 'Uploading location every 5 minutes' : 'Tap below to start location tracking', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
            const SizedBox(height: 24),

            // Debug log panel
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Time-stamped activity will appear here', style: TextStyle(color: Colors.white24, fontSize: 12)),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Text(
                        _logs[i],
                        style: TextStyle(
                          color: _logs[i].toLowerCase().contains('failed') ? Colors.redAccent : Colors.greenAccent.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 24),

            // Start / Stop button
            SizedBox(
              width: 200,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _isTracking ? [const Color(0xFFCF3E3E), const Color(0xFFCF7A3E)] : [const Color(0xFF6C63FF), const Color(0xFF3ECFCF)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: (_isTracking ? const Color(0xFFCF3E3E) : const Color(0xFF6C63FF)).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _toggleTracking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(
                          _isTracking ? 'Stop Tracking' : 'Start Tracking',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
