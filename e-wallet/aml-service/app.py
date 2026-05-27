from __future__ import annotations

import hashlib
import json
import os
import re
import threading
import time
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")

import pandas as pd
import psycopg
from dotenv import load_dotenv

from src.feature_engineer import engineer_features
from src.inference import AMLArtifacts, aggregate_by_account, predict
from src.transaction_store import TransactionStore

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")
MODEL_DIR = Path(os.getenv("AML_MODEL_DIR", BASE_DIR / "models"))
DATA_DIR = Path(os.getenv("AML_DATA_DIR", BASE_DIR / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

HOST = os.getenv("AML_HOST", "0.0.0.0")
PORT = int(os.getenv("AML_PORT", "3011"))
SCAN_INTERVAL_SECONDS = max(60, int(os.getenv("AML_SCAN_INTERVAL_SECONDS", "3600")))
SCAN_LOOKBACK_HOURS = max(1, int(os.getenv("AML_SCAN_LOOKBACK_HOURS", "24")))
SCAN_LIMIT = max(100, int(os.getenv("AML_SCAN_LIMIT", "20000")))
SCAN_ON_START = os.getenv("AML_SCAN_ON_START", "true").strip().lower() == "true"
SCAN_ONLY_UNSCANNED = os.getenv("AML_SCAN_ONLY_UNSCANNED", "true").strip().lower() == "true"
OVERVIEW_LIMIT = max(1000, int(os.getenv("AML_OVERVIEW_LIMIT", "200000")))

DB_HOST = os.getenv("AML_DB_HOST", "").strip()
DB_PORT = int(os.getenv("AML_DB_PORT", "5432"))
DB_NAME = os.getenv("AML_DB_NAME", "").strip()
DB_USER = os.getenv("AML_DB_USER", "").strip()
DB_PASS = os.getenv("AML_DB_PASS", "").strip()
DB_SSLMODE = os.getenv("AML_DB_SSLMODE", "prefer")
AML_FLAGS_TABLE = os.getenv("AML_FLAGS_TABLE", "aml_transaction_flags").strip()
if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", AML_FLAGS_TABLE):
    AML_FLAGS_TABLE = "aml_transaction_flags"

RESULTS_PATH = DATA_DIR / "latest_scan.json"
HISTORY_PATH = DATA_DIR / "transaction_history.parquet"

ARTIFACTS = AMLArtifacts(MODEL_DIR)
STORE = TransactionStore(HISTORY_PATH)

SCAN_LOCK = threading.Lock()
STATE_LOCK = threading.Lock()
STOP_EVENT = threading.Event()
LAST_RESULT: dict[str, Any] = {
    "status": "not_started",
    "generatedAt": None,
    "lookbackHours": SCAN_LOOKBACK_HOURS,
    "totalTransactions": 0,
    "flaggedTransactions": 0,
    "flaggedAccounts": 0,
    "accounts": [],
    "transactionsByAccount": {},
    "scanDurationMs": None,
    "scannedTransactions": 0,
    "error": None,
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(ts: datetime | None = None) -> str:
    value = ts or utc_now()
    return value.astimezone(timezone.utc).isoformat()


def stable_code(value: str) -> int:
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()
    return int(digest[:6], 16)


def map_payment_format(tx_type: str, is_external: bool) -> str:
    tx_type = (tx_type or "").strip().upper()
    if tx_type == "TRANSFER":
        return "Wire"
    if tx_type == "DEPOSIT":
        return "ACH"
    if tx_type == "WITHDRAWAL":
        return "Cash"
    if is_external:
        return "Wire"
    return "ACH"


def map_currency(value: str) -> str:
    code = (value or "").strip().upper()
    aliases = {
        "USD": "US Dollar",
        "USDT": "US Dollar",
        "EUR": "Euro",
        "BTC": "Bitcoin",
        "VND": "VND",
    }
    return aliases.get(code, code or "VND")


def account_from_row(row: dict[str, Any]) -> str:
    to_user = (row.get("to_user_id") or "").strip()
    if to_user:
        return to_user

    external_partner = (row.get("external_partner") or "").strip() or "external"
    external_account_no = (row.get("external_account_no") or "").strip() or "unknown"
    return f"ext:{external_partner}:{external_account_no}"


def to_float(value: Any) -> float:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and value.strip():
        return float(value)
    return 0.0


def db_conninfo() -> str:
    if not DB_HOST or not DB_NAME or not DB_USER or not DB_PASS:
        raise RuntimeError(
            "AML_DB_HOST, AML_DB_NAME, AML_DB_USER, AML_DB_PASS are required"
        )
    return (
        f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} user={DB_USER} "
        f"password={DB_PASS} sslmode={DB_SSLMODE}"
    )


def ensure_aml_storage() -> None:
    with psycopg.connect(db_conninfo()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE IF NOT EXISTS {AML_FLAGS_TABLE} (
                    transaction_id TEXT PRIMARY KEY,
                    created_at TIMESTAMPTZ NOT NULL,
                    from_account TEXT NOT NULL,
                    to_account TEXT NOT NULL,
                    amount_paid DOUBLE PRECISION NOT NULL DEFAULT 0,
                    amount_received DOUBLE PRECISION NOT NULL DEFAULT 0,
                    payment_format TEXT NOT NULL DEFAULT '',
                    payment_currency TEXT NOT NULL DEFAULT '',
                    fraud_probability DOUBLE PRECISION NOT NULL DEFAULT 0,
                    risk_level TEXT NOT NULL DEFAULT 'LOW',
                    is_flagged BOOLEAN NOT NULL DEFAULT FALSE,
                    scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    scan_lookback_hours INTEGER NOT NULL DEFAULT 24
                )
                """
            )
            cur.execute(
                f"CREATE INDEX IF NOT EXISTS idx_{AML_FLAGS_TABLE}_created_at ON {AML_FLAGS_TABLE} (created_at)"
            )
            cur.execute(
                f"CREATE INDEX IF NOT EXISTS idx_{AML_FLAGS_TABLE}_from_account ON {AML_FLAGS_TABLE} (from_account)"
            )
            cur.execute(
                f"CREATE INDEX IF NOT EXISTS idx_{AML_FLAGS_TABLE}_to_account ON {AML_FLAGS_TABLE} (to_account)"
            )
            cur.execute(
                f"CREATE INDEX IF NOT EXISTS idx_{AML_FLAGS_TABLE}_is_flagged ON {AML_FLAGS_TABLE} (is_flagged)"
            )
        conn.commit()


def fetch_wallet_transactions(
    lookback_hours: int,
    limit: int,
    *,
    only_unscanned: bool = True,
) -> pd.DataFrame:
    cutoff = utc_now() - timedelta(hours=lookback_hours)
    query = f"""
        SELECT
            tx.id::text AS transaction_id,
            tx."createdAt" AS created_at,
            tx."fromUserId"::text AS from_user_id,
            COALESCE(tx."toUserId"::text, '') AS to_user_id,
            tx.amount::numeric AS amount,
            tx.currency,
            tx.type,
            tx."isExternal" AS is_external,
            COALESCE(tx."externalPartner", '') AS external_partner,
            COALESCE(tx."externalAccountNo", '') AS external_account_no
        FROM transactions tx
        LEFT JOIN {AML_FLAGS_TABLE} afl
          ON afl.transaction_id = tx.id::text
        WHERE tx.status = 'COMPLETED'
          AND (
            (%(only_unscanned)s = TRUE AND afl.transaction_id IS NULL)
            OR
            (%(only_unscanned)s = FALSE AND tx."createdAt" >= %(cutoff)s)
          )
        ORDER BY tx."createdAt" ASC
        LIMIT %(limit)s
    """

    with psycopg.connect(db_conninfo()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                query,
                {
                    "cutoff": cutoff,
                    "limit": limit,
                    "only_unscanned": only_unscanned,
                },
            )
            rows = cur.fetchall()
            cols = [desc.name for desc in cur.description]

    if not rows:
        return pd.DataFrame(
            columns=[
                "TransactionId",
                "Timestamp",
                "Account",
                "Account.1",
                "From Bank",
                "To Bank",
                "Amount Paid",
                "Amount Received",
                "Payment Format",
                "Payment Currency",
                "Receiving Currency",
            ],
        )

    prepared: list[dict[str, Any]] = []
    for tup in rows:
        row = dict(zip(cols, tup, strict=False))
        created_at = row.get("created_at")
        if not isinstance(created_at, datetime):
            continue
        created_at = created_at.astimezone(timezone.utc)

        transaction_id = str(row.get("transaction_id") or "")
        from_user_id = (row.get("from_user_id") or "").strip()
        to_account = account_from_row(row)
        is_external = bool(row.get("is_external"))
        external_partner = (row.get("external_partner") or "").strip()

        amount = max(0.0, to_float(row.get("amount")))
        payment_currency = map_currency(str(row.get("currency") or ""))
        payment_format = map_payment_format(str(row.get("type") or ""), is_external)

        from_bank = 100
        to_bank = 100 if not is_external else 200 + (stable_code(external_partner or to_account) % 700)

        prepared.append(
            {
                "TransactionId": transaction_id,
                "Timestamp": created_at.strftime("%Y/%m/%d %H:%M"),
                "Account": from_user_id or f"unknown-from:{transaction_id}",
                "Account.1": to_account,
                "From Bank": from_bank,
                "To Bank": to_bank,
                "Amount Paid": amount,
                "Amount Received": amount,
                "Payment Format": payment_format,
                "Payment Currency": payment_currency,
                "Receiving Currency": payment_currency,
            }
        )

    return pd.DataFrame(prepared)


def account_risk_level(probability: float) -> str:
    if probability >= 0.8:
        return "CRITICAL"
    if probability >= 0.6:
        return "HIGH"
    if probability >= 0.3:
        return "MEDIUM"
    return "LOW"


def build_scan_result(
    *,
    lookback_hours: int,
    scan_started_at: datetime,
    tx_predictions: pd.DataFrame,
    account_scores: pd.DataFrame,
) -> dict[str, Any]:
    flagged_accounts = account_scores[account_scores["is_money_laundering"] == 1].copy()
    flagged_accounts = flagged_accounts.sort_values("max_fraud_prob", ascending=False)

    account_rows: list[dict[str, Any]] = []
    tx_by_account: dict[str, list[dict[str, Any]]] = {}

    for _, row in flagged_accounts.iterrows():
        account_id = str(row["account_id"])
        max_prob = float(row["max_fraud_prob"])
        account_rows.append(
            {
                "accountId": account_id,
                "riskLevel": account_risk_level(max_prob),
                "isMoneyLaundering": bool(int(row["is_money_laundering"])),
                "maxFraudProbability": round(max_prob, 6),
                "avgFraudProbability": round(float(row["avg_fraud_prob"]), 6),
                "totalTransactions": int(row["n_transactions"]),
                "flaggedTransactions": int(row["n_flagged_tx"]),
                "flagRatePct": float(row["flag_rate_pct"]),
                "totalSent": round(float(row["total_sent_usd"]), 2),
                "totalReceived": round(float(row["total_received_usd"]), 2),
                "isMuleAccount": bool(int(row.get("is_mule_account", 0))),
            }
        )

        acct_txs = tx_predictions[
            (tx_predictions["Account"] == account_id)
            | (tx_predictions["Account.1"] == account_id)
        ].copy()

        if not acct_txs.empty:
            acct_txs["_timestamp"] = pd.to_datetime(acct_txs["Timestamp"], errors="coerce")
            acct_txs = acct_txs.sort_values("_timestamp", ascending=False)

        tx_rows: list[dict[str, Any]] = []
        for _, tx in acct_txs.iterrows():
            sender = str(tx["Account"])
            receiver = str(tx["Account.1"])
            direction = "outbound" if sender == account_id else "inbound"
            counterparty = receiver if direction == "outbound" else sender
            ts_value = tx.get("_timestamp")
            if isinstance(ts_value, pd.Timestamp) and not pd.isna(ts_value):
                ts_iso = ts_value.tz_localize(timezone.utc).isoformat() if ts_value.tzinfo is None else ts_value.isoformat()
            else:
                ts_iso = str(tx["Timestamp"])

            tx_rows.append(
                {
                    "transactionId": str(tx.get("TransactionId") or ""),
                    "timestamp": ts_iso,
                    "direction": direction,
                    "counterpartyAccount": counterparty,
                    "amountPaid": round(float(tx.get("Amount Paid", 0.0)), 2),
                    "amountReceived": round(float(tx.get("Amount Received", 0.0)), 2),
                    "paymentFormat": str(tx.get("Payment Format") or ""),
                    "paymentCurrency": str(tx.get("Payment Currency") or ""),
                    "fraudProbability": round(float(tx.get("fraud_probability", 0.0)), 6),
                    "riskLevel": str(tx.get("risk_level") or ""),
                    "isFlagged": bool(int(tx.get("is_flagged", 0))),
                }
            )

        tx_by_account[account_id] = tx_rows

    flagged_tx_count = int(tx_predictions["is_flagged"].sum()) if not tx_predictions.empty else 0

    finished_at = utc_now()
    return {
        "status": "ok",
        "generatedAt": iso(finished_at),
        "lookbackHours": lookback_hours,
        "totalTransactions": int(len(tx_predictions)),
        "flaggedTransactions": flagged_tx_count,
        "flaggedAccounts": len(account_rows),
        "accounts": account_rows,
        "transactionsByAccount": tx_by_account,
        "scanDurationMs": int((finished_at - scan_started_at).total_seconds() * 1000),
        "error": None,
    }


def persist_predictions(
    tx_predictions: pd.DataFrame,
    *,
    lookback_hours: int,
) -> None:
    if tx_predictions.empty:
        return

    rows: list[tuple[Any, ...]] = []
    scanned_at = utc_now()
    for _, tx in tx_predictions.iterrows():
        transaction_id = str(tx.get("TransactionId") or "").strip()
        if not transaction_id:
            continue

        raw_ts = tx.get("Timestamp")
        parsed_ts = pd.to_datetime(raw_ts, errors="coerce")
        if isinstance(parsed_ts, pd.Timestamp) and not pd.isna(parsed_ts):
            if parsed_ts.tzinfo is None:
                created_at = parsed_ts.tz_localize(timezone.utc).to_pydatetime()
            else:
                created_at = parsed_ts.tz_convert(timezone.utc).to_pydatetime()
        else:
            created_at = scanned_at

        rows.append(
            (
                transaction_id,
                created_at,
                str(tx.get("Account") or "").strip(),
                str(tx.get("Account.1") or "").strip(),
                round(float(tx.get("Amount Paid", 0.0) or 0.0), 6),
                round(float(tx.get("Amount Received", 0.0) or 0.0), 6),
                str(tx.get("Payment Format") or "").strip(),
                str(tx.get("Payment Currency") or "").strip(),
                round(float(tx.get("fraud_probability", 0.0) or 0.0), 6),
                str(tx.get("risk_level") or "LOW").strip().upper() or "LOW",
                bool(int(tx.get("is_flagged", 0) or 0)),
                scanned_at,
                int(lookback_hours),
            )
        )

    if not rows:
        return

    with psycopg.connect(db_conninfo()) as conn:
        with conn.cursor() as cur:
            cur.executemany(
                f"""
                INSERT INTO {AML_FLAGS_TABLE} (
                    transaction_id,
                    created_at,
                    from_account,
                    to_account,
                    amount_paid,
                    amount_received,
                    payment_format,
                    payment_currency,
                    fraud_probability,
                    risk_level,
                    is_flagged,
                    scanned_at,
                    scan_lookback_hours
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (transaction_id) DO UPDATE
                SET
                    created_at = EXCLUDED.created_at,
                    from_account = EXCLUDED.from_account,
                    to_account = EXCLUDED.to_account,
                    amount_paid = EXCLUDED.amount_paid,
                    amount_received = EXCLUDED.amount_received,
                    payment_format = EXCLUDED.payment_format,
                    payment_currency = EXCLUDED.payment_currency,
                    fraud_probability = EXCLUDED.fraud_probability,
                    risk_level = EXCLUDED.risk_level,
                    is_flagged = EXCLUDED.is_flagged,
                    scanned_at = EXCLUDED.scanned_at,
                    scan_lookback_hours = EXCLUDED.scan_lookback_hours
                """,
                rows,
            )
        conn.commit()


def fetch_scored_transactions(
    *,
    lookback_hours: int,
    limit: int,
) -> pd.DataFrame:
    cutoff = utc_now() - timedelta(hours=lookback_hours)
    query = f"""
        SELECT
            transaction_id,
            created_at,
            from_account,
            to_account,
            amount_paid,
            amount_received,
            payment_format,
            payment_currency,
            fraud_probability,
            risk_level,
            is_flagged
        FROM {AML_FLAGS_TABLE}
        WHERE created_at >= %(cutoff)s
        ORDER BY created_at ASC
        LIMIT %(limit)s
    """
    with psycopg.connect(db_conninfo()) as conn:
        with conn.cursor() as cur:
            cur.execute(query, {"cutoff": cutoff, "limit": max(1000, int(limit))})
            rows = cur.fetchall()

    if not rows:
        return pd.DataFrame(
            columns=[
                "TransactionId",
                "Timestamp",
                "Account",
                "Account.1",
                "Amount Paid",
                "Amount Received",
                "Payment Format",
                "Payment Currency",
                "fraud_probability",
                "risk_level",
                "is_flagged",
            ],
        )

    prepared: list[dict[str, Any]] = []
    for (
        transaction_id,
        created_at,
        from_account,
        to_account,
        amount_paid,
        amount_received,
        payment_format,
        payment_currency,
        fraud_probability,
        risk_level,
        is_flagged,
    ) in rows:
        if isinstance(created_at, datetime):
            created = created_at.astimezone(timezone.utc).isoformat()
        else:
            created = str(created_at)
        prepared.append(
            {
                "TransactionId": str(transaction_id),
                "Timestamp": created,
                "Account": str(from_account or ""),
                "Account.1": str(to_account or ""),
                "Amount Paid": float(amount_paid or 0),
                "Amount Received": float(amount_received or 0),
                "Payment Format": str(payment_format or ""),
                "Payment Currency": str(payment_currency or ""),
                "fraud_probability": float(fraud_probability or 0),
                "risk_level": str(risk_level or "LOW"),
                "is_flagged": int(bool(is_flagged)),
            }
        )

    return pd.DataFrame(prepared)


def persist_result(result: dict[str, Any]) -> None:
    RESULTS_PATH.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )


def load_persisted_result() -> dict[str, Any] | None:
    if not RESULTS_PATH.exists():
        return None
    try:
        parsed = json.loads(RESULTS_PATH.read_text(encoding="utf-8"))
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        return None
    return None


def scan_once(lookback_hours: int | None = None, limit: int | None = None) -> dict[str, Any]:
    effective_lookback = max(1, int(lookback_hours or SCAN_LOOKBACK_HOURS))
    effective_limit = max(100, int(limit or SCAN_LIMIT))

    if not SCAN_LOCK.acquire(blocking=False):
        with STATE_LOCK:
            return {
                **LAST_RESULT,
                "status": "busy",
                "error": "An AML scan is already in progress.",
            }

    started = utc_now()
    try:
        ensure_aml_storage()
        batch = fetch_wallet_transactions(
            effective_lookback,
            effective_limit,
            only_unscanned=SCAN_ONLY_UNSCANNED,
        )
        scanned_count = int(len(batch))
        if not batch.empty:
            combined = STORE.combine_with_history(batch)
            current_mask = combined["is_current"] if "is_current" in combined else None
            engineered = engineer_features(
                df=combined,
                enc_payment_format=ARTIFACTS.enc_payment_format,
                enc_payment_currency=ARTIFACTS.enc_payment_currency,
                enc_receiving_currency=ARTIFACTS.enc_receiving_currency,
                fmt_fraud_rate_train=ARTIFACTS.fmt_fraud_rate_train,
                current_mask=current_mask,
            )
            tx_predictions = predict(engineered, ARTIFACTS)
            STORE.save(batch)
            persist_predictions(
                tx_predictions,
                lookback_hours=effective_lookback,
            )

        scored_transactions = fetch_scored_transactions(
            lookback_hours=effective_lookback,
            limit=OVERVIEW_LIMIT,
        )
        if scored_transactions.empty:
            result = {
                "status": "ok",
                "generatedAt": iso(),
                "lookbackHours": effective_lookback,
                "totalTransactions": 0,
                "flaggedTransactions": 0,
                "flaggedAccounts": 0,
                "accounts": [],
                "transactionsByAccount": {},
                "scanDurationMs": int((utc_now() - started).total_seconds() * 1000),
                "error": None,
                "scannedTransactions": scanned_count,
            }
        else:
            account_scores = aggregate_by_account(scored_transactions)
            result = build_scan_result(
                lookback_hours=effective_lookback,
                scan_started_at=started,
                tx_predictions=scored_transactions,
                account_scores=account_scores,
            )
            result["scannedTransactions"] = scanned_count

        with STATE_LOCK:
            LAST_RESULT.clear()
            LAST_RESULT.update(result)

        persist_result(result)
        return result
    except Exception as exc:
        result = {
            "status": "error",
            "generatedAt": iso(),
            "lookbackHours": effective_lookback,
            "totalTransactions": 0,
            "flaggedTransactions": 0,
            "flaggedAccounts": 0,
            "accounts": [],
            "transactionsByAccount": {},
            "scanDurationMs": int((utc_now() - started).total_seconds() * 1000),
            "error": str(exc),
            "scannedTransactions": 0,
        }
        with STATE_LOCK:
            LAST_RESULT.clear()
            LAST_RESULT.update(result)
        persist_result(result)
        return result
    finally:
        SCAN_LOCK.release()


def scheduler_loop() -> None:
    while not STOP_EVENT.wait(SCAN_INTERVAL_SECONDS):
        scan_once()


class AmlHandler(BaseHTTPRequestHandler):
    server_version = "AmlService/1.0"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)

        if path == "/healthz":
            self.write_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "service": "aml-service",
                    "modelFeatures": len(ARTIFACTS.feature_cols),
                    "threshold": ARTIFACTS.optimal_threshold,
                    "scanIntervalSeconds": SCAN_INTERVAL_SECONDS,
                    "scanLookbackHours": SCAN_LOOKBACK_HOURS,
                    "scanOnlyUnscanned": SCAN_ONLY_UNSCANNED,
                    "lastGeneratedAt": LAST_RESULT.get("generatedAt"),
                },
            )
            return

        if path == "/aml/status":
            with STATE_LOCK:
                summary = {
                    "status": LAST_RESULT.get("status"),
                    "generatedAt": LAST_RESULT.get("generatedAt"),
                    "lookbackHours": LAST_RESULT.get("lookbackHours"),
                    "totalTransactions": LAST_RESULT.get("totalTransactions"),
                    "flaggedTransactions": LAST_RESULT.get("flaggedTransactions"),
                    "flaggedAccounts": LAST_RESULT.get("flaggedAccounts"),
                    "scanDurationMs": LAST_RESULT.get("scanDurationMs"),
                    "scannedTransactions": LAST_RESULT.get("scannedTransactions"),
                    "error": LAST_RESULT.get("error"),
                }
            self.write_json(HTTPStatus.OK, summary)
            return

        if path == "/aml/accounts":
            limit = to_int(query.get("limit", ["50"])[0], default=50, minimum=1, maximum=500)
            offset = to_int(query.get("offset", ["0"])[0], default=0, minimum=0, maximum=100000)
            with STATE_LOCK:
                accounts = list(LAST_RESULT.get("accounts", []))
                generated_at = LAST_RESULT.get("generatedAt")
            items = accounts[offset : offset + limit]
            self.write_json(
                HTTPStatus.OK,
                {
                    "generatedAt": generated_at,
                    "total": len(accounts),
                    "limit": limit,
                    "offset": offset,
                    "items": items,
                },
            )
            return

        if path.startswith("/aml/accounts/") and path.endswith("/transactions"):
            prefix = "/aml/accounts/"
            raw_part = path[len(prefix) : -len("/transactions")]
            account_id = unquote(raw_part)
            limit = to_int(query.get("limit", ["200"])[0], default=200, minimum=1, maximum=1000)

            with STATE_LOCK:
                generated_at = LAST_RESULT.get("generatedAt")
                account_exists = any(
                    item.get("accountId") == account_id
                    for item in LAST_RESULT.get("accounts", [])
                )
                tx_map = LAST_RESULT.get("transactionsByAccount", {})
                txs = list(tx_map.get(account_id, []))

            if not account_exists:
                self.write_json(
                    HTTPStatus.NOT_FOUND,
                    {"message": f"Account {account_id} was not found in latest AML result."},
                )
                return

            self.write_json(
                HTTPStatus.OK,
                {
                    "generatedAt": generated_at,
                    "accountId": account_id,
                    "total": len(txs),
                    "items": txs[:limit],
                },
            )
            return

        self.write_json(HTTPStatus.NOT_FOUND, {"message": "Not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if path != "/aml/scan":
            self.write_json(HTTPStatus.NOT_FOUND, {"message": "Not found"})
            return

        payload = self.read_json_optional()
        lookback_hours = to_int(payload.get("lookbackHours"), default=SCAN_LOOKBACK_HOURS, minimum=1, maximum=24 * 30)
        limit = to_int(payload.get("limit"), default=SCAN_LIMIT, minimum=100, maximum=200000)

        result = scan_once(lookback_hours=lookback_hours, limit=limit)
        status = HTTPStatus.OK if result.get("status") != "error" else HTTPStatus.INTERNAL_SERVER_ERROR
        self.write_json(status, result)

    def log_message(self, fmt: str, *args: Any) -> None:
        if os.getenv("AML_ACCESS_LOG", "false").lower() == "true":
            super().log_message(fmt, *args)

    def read_json_optional(self) -> dict[str, Any]:
        length = int(self.headers.get("content-length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        if not raw:
            return {}
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {}
        if isinstance(payload, dict):
            return payload
        return {}

    def write_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(int(status))
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def to_int(
    value: Any,
    *,
    default: int,
    minimum: int,
    maximum: int,
) -> int:
    try:
        numeric = int(value)
    except (TypeError, ValueError):
        numeric = default
    return max(minimum, min(maximum, numeric))


def bootstrap_state() -> None:
    loaded = load_persisted_result()
    if loaded:
        LAST_RESULT.clear()
        LAST_RESULT.update(loaded)


def main() -> None:
    ensure_aml_storage()
    bootstrap_state()

    if SCAN_ON_START and LAST_RESULT.get("generatedAt") is None:
        scan_once()

    scheduler = threading.Thread(target=scheduler_loop, daemon=True)
    scheduler.start()

    server = ThreadingHTTPServer((HOST, PORT), AmlHandler)
    print(
        json.dumps(
            {
                "event": "aml_service_started",
                "host": HOST,
                "port": PORT,
                "scanIntervalSeconds": SCAN_INTERVAL_SECONDS,
                "scanLookbackHours": SCAN_LOOKBACK_HOURS,
                "threshold": ARTIFACTS.optimal_threshold,
            },
            separators=(",", ":"),
        ),
        flush=True,
    )

    try:
        server.serve_forever()
    finally:
        STOP_EVENT.set()


if __name__ == "__main__":
    main()
