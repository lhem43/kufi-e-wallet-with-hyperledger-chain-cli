# Kufi Capstone Project

## Students

- Lê Đỗ Minh Anh - 2252023
- Trần Đăng Khoa - 2252363

## Repository Structure

- `e-wallet/`: wallet backend microservices, Flutter mobile app, and supporting Python services (AML/ATO).
- `chain/`: KufiChain CLI and Hyperledger Fabric integration code.
- `monitoring_system/`: monitoring backend and web console.
- `evaluation/`: load-test toolkit and the latest benchmark result set.
- `ref/`: reference papers used in study.
- `.github/`: CI/CD workflows.

## Prerequisites (Global)

- Docker Engine 24+ and Docker Compose v2 (or Docker Desktop on macOS/Windows).
- Node.js 20+ and npm 10+ (for NestJS/React services).
- Python 3.10+ with `venv` and `pip` (for AML/ATO/evaluation scripts).
- Flutter stable with Dart 3.10+ and Android SDK (for mobile app build).
- Go 1.21+ (for KufiChain CLI and chain gateway).

## Rebuild APK From Source (Optional)

Linux/macOS:

```bash
cd e-wallet/frontend
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE_URL=http://<api-host>:3000 \
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

Windows PowerShell:

```powershell
cd e-wallet\frontend
flutter pub get
flutter build apk --release `
  --dart-define=API_BASE_URL=http://<api-host>:3000 `
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

Output APK:

```bash
build/app/outputs/flutter-apk/app-release.apk
```

## Run Flutter Desktop App (Optional)

Linux:

```bash
cd e-wallet/frontend
flutter run -d linux \
  --dart-define=API_BASE_URL=http://<api-host>:3000 \
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

macOS:

```bash
cd e-wallet/frontend
flutter run -d macos \
  --dart-define=API_BASE_URL=http://<api-host>:3000 \
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

Windows PowerShell:

```powershell
cd e-wallet\frontend
flutter run -d windows `
  --dart-define=API_BASE_URL=http://<api-host>:3000 `
  --dart-define=FIREBASE_API_KEY=<your-firebase-api-key>
```

## Entry Points

- Wallet backend stack: see `e-wallet/README.md`.
- Chain node setup/run: see `chain/README.md`.
- Monitoring stack: see `monitoring_system/README.md`.
- Evaluation toolkit and latest result: see `evaluation/README.md`.
