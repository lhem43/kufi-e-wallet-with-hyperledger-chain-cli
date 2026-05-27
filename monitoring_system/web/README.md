# Monitoring Web

React + Vite frontend for Kufi Monitoring.

## Prerequisites

- Node.js 20+ and npm 10+.

## Environment

Copy `.env.example` to `.env` and fill in the values.

Required key:

- `VITE_API_BASE_URL` (example: `http://127.0.0.1:4300/api`)

## Run

Linux/macOS:

```bash
cd monitoring_system/web
npm install
npm run dev -- --host 0.0.0.0 --port 4173
```

Windows PowerShell:

```powershell
cd monitoring_system\web
npm install
npm run dev -- --host 0.0.0.0 --port 4173
```

## Build

```bash
npm run build
npm run preview -- --host 0.0.0.0 --port 4173
```
