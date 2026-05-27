# Monitoring Backend

NestJS backend for the Kufi monitoring console.

## Features

- JWT authentication
- RBAC for admin roles
- Audit logs
- Monitoring overview and trend APIs
- Chain status aggregation
- Log-tail endpoints

## Prerequisites

- Node.js 20+ and npm 10+.
- PostgreSQL 16+ (unless you run via `monitoring_system/docker-compose.yml`).

## Environment

Copy `.env.example` to `.env` and fill in the values.

Required keys:

- `DB_HOST`
- `DB_PORT`
- `DB_USER`
- `DB_PASS`
- `DB_NAME`
- `JWT_SECRET`
- `ADMIN_EMAIL`
- `ADMIN_PASSWORD`

Common optional keys:

- `DB_SYNC`
- `JWT_EXPIRES_IN`
- `ADMIN_DISPLAY_NAME`
- `ADMIN_TITLE`
- `ADMIN_LOCALE`
- `MONITORED_SERVICE_ENDPOINTS`
- `CHAIN_GATEWAY_HEALTH_URL`
- `CHAIN_BOOTSTRAP_MGMT_URL`
- `WALLET_DB_URL` (or `WALLET_DB_HOST/PORT/USER/PASS/NAME`)

## Run

Linux/macOS:

```bash
cd monitoring_system/backend
npm install
npm run start:dev
```

Windows PowerShell:

```powershell
cd monitoring_system\backend
npm install
npm run start:dev
```

Production build:

```bash
npm run build
npm run start:prod
```
