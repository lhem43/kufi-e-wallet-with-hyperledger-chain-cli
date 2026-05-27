# Kufi E-Wallet

`e-wallet/` contains the wallet platform backend services and mobile frontend.

## Components

- `api-gateway` (NestJS)
- `auth-service` (NestJS)
- `transaction-service` (NestJS)
- `outside-payment-service` (NestJS)
- `chain-service` (NestJS)
- `notification-service` (NestJS)
- `settlement-service` (NestJS)
- `ato-service` (Python)
- `aml-service` (Python)
- `frontend` (Flutter)

## Prerequisites

- Docker Engine 24+ and Docker Compose v2.
- Node.js 20+ and npm 10+ for all NestJS services.
- Python 3.10+ with `venv` and `pip` for `ato-service` and `aml-service`.
- Flutter stable (Dart 3.10+) for `frontend`.
- Android SDK if you build APK locally.

## Infrastructure

Use local infra stack (PostgreSQL + Redpanda):

```bash
cd e-wallet
docker compose -f docker-compose.infra.yml up -d
```

## Backend Services (Development)

Each Nest service expects its own `.env` file in its folder.
Copy `.env.example` to `.env` and fill in the values.

Start one service:

```bash
cd e-wallet/<service>
npm install
npm run start:dev
```

Apply this to:

- `api-gateway`
- `auth-service`
- `transaction-service`
- `outside-payment-service`
- `chain-service`
- `notification-service`
- `settlement-service`

## Python Services

### ATO service

```bash
cd e-wallet/ato-service
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python app.py
```

### AML service

```bash
cd e-wallet/aml-service
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python app.py
```

AML service details are documented in `e-wallet/aml-service/README.md`.

## Flutter Frontend

From `e-wallet/frontend`:

Replace the values below with your own deployment settings.

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

Build APK:

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
