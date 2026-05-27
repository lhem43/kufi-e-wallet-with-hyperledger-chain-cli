"""
inference.py
"""

from __future__ import annotations

import json
import pickle
from pathlib import Path
from typing import Any

import lightgbm as lgb
import numpy as np
import pandas as pd


class AMLArtifacts:
    def __init__(self, artifact_dir: str | Path = "output"):
        artifact_dir = Path(artifact_dir)

        model_path = artifact_dir / "lgbm_model.pkl"
        if not model_path.exists():
            raise FileNotFoundError(f"Cannot find model: {model_path}")
        with open(model_path, "rb") as f:
            self.model: lgb.LGBMClassifier = pickle.load(f)
        enc_path = artifact_dir / "label_encoders.pkl"
        if not enc_path.exists():
            raise FileNotFoundError(f"Cannot find label encoders: {enc_path}")
        with open(enc_path, "rb") as f:
            enc: dict[str, dict] = pickle.load(f)
        self.enc_payment_format: dict = enc["payment_format"]
        self.enc_payment_currency: dict = enc["payment_currency"]
        self.enc_receiving_currency: dict = enc["receiving_currency"]

        cfg_path = artifact_dir / "model_config.json"
        if not cfg_path.exists():
            raise FileNotFoundError(f"Cannot find model_config: {cfg_path}")
        with open(cfg_path) as f:
            cfg: dict[str, Any] = json.load(f)

        self.feature_cols: list[str] = cfg["feature_cols"]
        self.optimal_threshold: float = cfg["optimal_threshold"]
        self.fmt_fraud_rate_train: dict = cfg["fmt_fraud_rate_train"]

    def summary(self) -> None:
        print(f"  Model type: {type(self.model).__name__}")
        print(f"  Features: {len(self.feature_cols)}")
        print(f"  Threshold: {self.optimal_threshold:.4f}")
        print(f"  Fmt categories: {len(self.fmt_fraud_rate_train)}")

def predict(
    df_engineered: pd.DataFrame,
    artifacts: AMLArtifacts,
) -> pd.DataFrame:
    """
    Run model
    """
    missing = [c for c in artifacts.feature_cols if c not in df_engineered.columns]
    if missing:
        raise ValueError(f"DataFrame misses features: {missing}")

    X_pred = df_engineered[artifacts.feature_cols].copy()

    X_pred.columns = artifacts.model.feature_name_

    proba = artifacts.model.predict_proba(X_pred)[:, 1]

    flagged = (proba >= artifacts.optimal_threshold).astype(int)

    df_out = df_engineered.copy()
    df_out["fraud_probability"] = proba.round(4)
    df_out["is_flagged"] = flagged
    df_out["risk_level"] = pd.cut(
        proba,
        bins  = [0.0, 0.3, 0.6, 0.8, 1.0],
        labels = ["LOW", "MEDIUM", "HIGH", "CRITICAL"],
        include_lowest = True,
    )
    return df_out


def aggregate_by_account(df_pred: pd.DataFrame) -> pd.DataFrame:
    """
    Resulf from transaction-level → account-level verdict.

    Args:
        df_pred : Output from predict().
    """
    all_accounts = pd.unique(
        pd.concat([df_pred["Account"], df_pred["Account.1"]])
    )

    rows = []
    for acct in all_accounts:
        as_sender = df_pred[df_pred["Account"]   == acct]
        as_receiver = df_pred[df_pred["Account.1"] == acct]
        all_tx = pd.concat([as_sender, as_receiver]).drop_duplicates()

        n_total = len(all_tx)
        n_flagged = int(all_tx["is_flagged"].sum())

        rows.append({
            "account_id": acct,
            "is_money_laundering": int(n_flagged > 0),
            "max_fraud_prob": round(float(all_tx["fraud_probability"].max()), 4),
            "avg_fraud_prob": round(float(all_tx["fraud_probability"].mean()), 4),
            "n_transactions" : n_total,
            "n_flagged_tx": n_flagged,
            "flag_rate_pct": round(n_flagged / n_total * 100, 1) if n_total else 0.0,
            "total_sent_usd": round(float(as_sender["Amount Paid"].sum()), 2),
            "total_received_usd": round(float(as_receiver["Amount Received"].sum()), 2),
            "is_mule_account": int(all_tx["is_mule_account"].max()) if "is_mule_account" in all_tx else 0,
        })

    return (
        pd.DataFrame(rows)
        .sort_values("max_fraud_prob", ascending=False)
        .reset_index(drop=True)
    )