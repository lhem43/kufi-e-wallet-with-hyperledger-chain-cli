# Kufi Monitoring System

`monitoring_system/` provides operational visibility for wallet and chain services.

## Components

- `backend/`: NestJS API (auth, RBAC, audit logs, metrics aggregation).
- `web/`: React + Vite monitoring console.
- `docker-compose.yml`: local compose setup for monitoring DB/backend/web.

## Prerequisites

- Docker Engine 24+ and Docker Compose v2 for compose-based run.
- Node.js 20+ and npm 10+ for manual backend/web development.
- PostgreSQL 16+ only if you run backend without Docker.

## Local Run With Docker Compose

Linux/macOS:

```bash
cd monitoring_system
docker compose up -d
```

Windows PowerShell:

```powershell
cd monitoring_system
docker compose up -d
```

OS note:

- Linux: Docker Engine + Docker Compose plugin.
- macOS/Windows: Docker Desktop.

Default ports:

- Backend: `4300`
- Web: `4173`
- Monitoring Postgres: `55433`

All runtime settings are expected from environment variables and `.env` files.

## Manual Development

- Backend setup/run: `monitoring_system/backend/README.md`
- Web setup/run: `monitoring_system/web/README.md`
