# AML Service

`aml-service` runs scheduled AML detection and stores flags into `aml_transaction_flags`.

## Prerequisites

- Python 3.10+.
- `venv` and `pip`.
- PostgreSQL reachable from this service (configured via `.env`).

## API

- `GET /healthz`
- `GET /aml/status`
- `GET /aml/accounts?limit=50&offset=0`
- `GET /aml/accounts/{accountId}/transactions?limit=200`
- `POST /aml/scan`

Optional `POST /aml/scan` body:

```json
{
  "lookbackHours": 24,
  "limit": 20000
}
```

## Environment Variables

Read from `.env` in this folder.

Required:

- `AML_DB_HOST`
- `AML_DB_PORT`
- `AML_DB_NAME`
- `AML_DB_USER`
- `AML_DB_PASS`

Common runtime settings:

- `AML_HOST`
- `AML_PORT`
- `AML_SCAN_INTERVAL_SECONDS`
- `AML_SCAN_LOOKBACK_HOURS`
- `AML_SCAN_LIMIT`
- `AML_SCAN_ON_START`
- `AML_SCAN_ONLY_UNSCANNED`
- `AML_OVERVIEW_LIMIT`
- `AML_FLAGS_TABLE`
- `AML_DB_SSLMODE`

## Local Run

```bash
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python app.py
```
