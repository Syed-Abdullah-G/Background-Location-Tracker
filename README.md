# LocationPOC

LocationPOC is a Flutter app that authenticates users with Firebase Auth and uploads device location to Cloud Firestore in the background every 5 minutes using a foreground service.

## What This App Does

- Email/password sign up and sign in.
- Requests foreground and background location permission.
- Starts a foreground tracking service (Android) with a persistent notification.
- Captures high-accuracy GPS coordinates periodically.
- Uploads location history to Firestore under the signed-in user.
- Shows live status and runtime logs in the UI.

## Tech Stack

- Flutter
- Firebase Core
- Firebase Auth
- Cloud Firestore
- Geolocator
- Permission Handler
- Flutter Foreground Task

## How It Works

1. App startup initializes Firebase and foreground task config.
2. Auth gate routes users to Login or Home based on auth state.
3. Home screen lets user start/stop tracking.
4. On start, app validates GPS, notification permission, and authenticated user.
5. Background isolate runs `LocationTaskHandler`:
	 - reads user UID
	 - initializes Firebase in isolate
	 - uploads location immediately
	 - uploads again every 5 minutes
6. Each upload is saved to Firestore.

## Firestore Data Model

Locations are written to:

`users/{uid}/locations/{autoDocId}`

Each location document contains:

- `uid` (string)
- `latitude` (double)
- `longitude` (double)
- `timestamp` (Firestore Timestamp)

## Project Structure

```text
lib/
	main.dart                        # App bootstrap, Firebase init, auth gate
	auth/login_screen.dart           # Login/register UI + auth actions
	screens/home_screen.dart         # Start/stop tracking + in-app logs
	services/background_service.dart # Foreground service + periodic uploader
	services/location_service.dart   # Permission + GPS helpers
	services/firebase_service.dart   # Firebase Auth wrapper
	models/location_model.dart       # Firestore location payload model
```

## Prerequisites

- Flutter SDK installed
- Xcode (for iOS builds)
- Android Studio / Android SDK (for Android builds)
- Firebase project enabled for:
	- Authentication (Email/Password provider)
	- Cloud Firestore

## Firebase Configuration

This repo already includes platform Firebase config files:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

If you need to reconfigure Firebase for a new project:

1. Install FlutterFire CLI.
2. Run:

```bash
flutterfire configure
```

3. Ensure Email/Password sign-in is enabled in Firebase Console.
4. Ensure Firestore database is created.

## Setup and Run

```bash
flutter pub get
flutter run
```

To run on a specific platform:

```bash
flutter run -d android
flutter run -d ios
```

## Platform Permissions

### Android

Configured in `android/app/src/main/AndroidManifest.xml`:

- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS`

### iOS

Configured in `ios/Runner/Info.plist`:

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes` with `location` and `fetch`

## Expected User Flow

1. Launch app.
2. Sign up or sign in.
3. Grant location and notification permissions when prompted.
4. Tap **Start Tracking**.
5. Keep app/service running for periodic uploads.
6. Tap **Stop Tracking** to end background uploads.

## Troubleshooting

- Tracking does not start:
	- Confirm GPS is enabled on device.
	- Confirm notification permission is granted.
	- Confirm user is authenticated.
- No uploads in Firestore:
	- Check Firestore rules allow authenticated writes.
	- Check internet connectivity.
	- Keep app/service alive long enough for periodic cycle.
- Android kills service:
	- Allow battery optimization ignore when prompted.
	- Test on a physical device (some emulators are restrictive).

## Notes

- Upload interval is currently 5 minutes.
- Foreground service is essential for reliable background tracking on Android.
- iOS background behavior is platform-constrained and may vary by device state and OS policies.

## Security Recommendations

- Do not keep permissive Firestore rules in production.
- Scope writes to authenticated user paths only.
- Consider server-side validation (Cloud Functions / App Check) for production hardening.

## Future Improvements

- Add map-based timeline UI for location history.
- Add retry/backoff and offline queue for failed uploads.
- Add unit and integration tests for service lifecycle and uploads.
- Add CI checks for linting and test automation.
