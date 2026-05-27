# ATO Service

`ato-service` provides account takeover risk scoring signals for transaction flow.

## Prerequisites

- Python 3.10+.
- `venv` and `pip`.

## Run

```bash
cd e-wallet/ato-service
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python app.py
```

## Configuration

Read from environment variables in runtime shell or process manager.
