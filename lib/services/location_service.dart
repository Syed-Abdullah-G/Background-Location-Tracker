import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location_poc/models/location_model.dart';

class LocationService {
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Requests foreground/background permissions.
  Future<bool> requestLocationPermissions() async {
    // Step 1: foreground (When In Use)
    final locationStatus = await Permission.location.request();
    if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      return false;
    }

    // Step 2: background (Always) — must be requested after foreground on Android 10+
    final backgroundStatus = await Permission.locationAlways.request();
    return backgroundStatus.isGranted;
  }

  /// Gets the current GPS position as a [LocationModel].
  Future<LocationModel?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );

    return LocationModel(latitude: position.latitude, longitude: position.longitude, timestamp: DateTime.now());
  }

  Future<bool> hasLocationPermission() async => await Permission.location.isGranted;

  Future<bool> hasBackgroundLocationPermission() async => await Permission.locationAlways.isGranted;
}
