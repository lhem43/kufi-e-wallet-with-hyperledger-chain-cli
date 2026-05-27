# Kufi Wallet Frontend (Flutter)

This is the Flutter client for Kufi wallet.

## Requirements

- Flutter SDK stable (Dart 3.10+)
- Android SDK + Android build tools (for APK build)
- Java 17 (recommended by recent Android Gradle toolchains)
- Platform target enabled if you run desktop locally:
  - Linux: `flutter config --enable-linux-desktop`
  - macOS: `flutter config --enable-macos-desktop`
  - Windows: `flutter config --enable-windows-desktop`

## Environment Inputs

The app reads configuration from:

1. `--dart-define` values (highest priority)
2. `.env` file in this folder

Required keys:

- `API_BASE_URL`
- `FIREBASE_API_KEY`

## Run Desktop App

Linux:

```bash
flutter pub get
flutter run -d linux \
  --dart-define=API_BASE_URL=http://<api-host>:3000 \
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

macOS:

```bash
flutter pub get
flutter run -d macos \
  --dart-define=API_BASE_URL=http://<api-host>:3000 \
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

Windows PowerShell:

```powershell
flutter pub get
flutter run -d windows `
  --dart-define=API_BASE_URL=http://<api-host>:3000 `
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

## Build APK

Linux/macOS:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=http://<api-host>:3000 \
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

Windows PowerShell:

```powershell
flutter build apk --release `
  --dart-define=API_BASE_URL=http://<api-host>:3000 `
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

Generated file:

```bash
build/app/outputs/flutter-apk/app-release.apk
```
