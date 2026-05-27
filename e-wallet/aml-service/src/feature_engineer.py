"""
feature_engineer.py
"""

from __future__ import annotations

import numpy as np
import pandas as pd

OFF_HOURS = range(0, 6)   
MULE_MIN_RECV = 10_000        
MULE_FLOW_LOW = 0.9      
MULE_FLOW_HIGH = 1.1         
MULE_MIN_TX = 2           
EPSILON = 1e-9         

def validate(df: pd.DataFrame) -> None:
    required = [
        "Timestamp", "Account", "Account.1",
        "From Bank", "To Bank",
        "Amount Paid", "Amount Received",
        "Payment Format", "Payment Currency", "Receiving Currency",
    ]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"[feature_engineer] Thiếu columns: {missing}")


def encode(series: pd.Series, mapping: dict) -> pd.Series:
    return series.map(mapping).fillna(-1).astype("int16")

def engineer_features(
    df: pd.DataFrame,
    enc_payment_format: dict,
    enc_payment_currency: dict,
    enc_receiving_currency: dict,
    fmt_fraud_rate_train: dict,
    current_mask: pd.Series | None = None,
) -> pd.DataFrame:
    """
    Tính features từ raw transaction DataFrame.
    """
    validate(df)

    df = df.copy()
    if not pd.api.types.is_datetime64_any_dtype(df["Timestamp"]):
        df["Timestamp"] = pd.to_datetime(df["Timestamp"], format="%Y/%m/%d %H:%M")
    df = df.sort_values("Timestamp").reset_index(drop=True)

    if current_mask is not None:
        if "is_current" not in df.columns:
            raise ValueError(
                "When using current_mask, DataFrame must contain 'is_current'"
            )
        current_mask_aligned = df["is_current"].astype(bool)
    else:
        current_mask_aligned = pd.Series(True, index=df.index)

    df["hour_of_day"] = df["Timestamp"].dt.hour.astype("int8")
    df["day_of_week"] = df["Timestamp"].dt.dayofweek.astype("int8")
    df["is_off_hours"] = df["hour_of_day"].isin(OFF_HOURS).astype("int8")
    df["is_weekend"] = (df["day_of_week"] >= 5).astype("int8")

    df["amount_diff"] = df["Amount Paid"] - df["Amount Received"]
    df["amount_ratio"] = df["Amount Received"] / (df["Amount Paid"] + EPSILON)
    df["log_amount_paid"] = np.log1p(df["Amount Paid"])
    df["log_amount_received"] = np.log1p(df["Amount Received"])

    df["is_same_bank"] = (df["From Bank"] == df["To Bank"]).astype("int8")

    df["sender_tx_count"] = df.groupby("Account").cumcount()
    df["sender_total_volume"] = df.groupby("Account")["Amount Paid"].cumsum()
    df["receiver_tx_count"] = df.groupby("Account.1").cumcount()
    df["receiver_total_volume"] = df.groupby("Account.1")["Amount Received"].cumsum()
    df["sender_sent_to_received_ratio"] = (df["sender_total_volume"] / (df["receiver_total_volume"] + EPSILON))

    sender_unique_recv = df.groupby("Account")["Account.1"].nunique()
    receiver_unique_send = df.groupby("Account.1")["Account"].nunique()

    df["sender_unique_receivers"] = df["Account"].map(sender_unique_recv).fillna(0)
    df["receiver_unique_senders"] = df["Account.1"].map(receiver_unique_send).fillna(0)

    edge_set = set(zip(df["Account"], df["Account.1"]))
    df["is_reciprocal"] = [int((recv, send) in edge_set) for send, recv in zip(df["Account"], df["Account.1"])]

    df["payment_format_enc"] = encode(df["Payment Format"], enc_payment_format)
    df["payment_currency_enc"] = encode(df["Payment Currency"], enc_payment_currency)
    df["receiving_currency_enc"] = encode(df["Receiving Currency"], enc_receiving_currency)

    df["payment_format_fraud_rate"] = (
        df["Payment Format"]
        .map(fmt_fraud_rate_train)
        .fillna(0.0)
        .astype("float32")
    )

    recv_vol = df.groupby("Account.1")["Amount Received"].sum()
    sent_vol = df.groupby("Account")["Amount Paid"].sum()
    tx_count = df.groupby("Account")["Amount Paid"].count()

    acct_stats = pd.DataFrame({
        "total_received": recv_vol,
        "total_sent": sent_vol,
        "tx_count": tx_count,
    }).fillna(0)
    acct_stats["flow_ratio"] = acct_stats["total_sent"] / (acct_stats["total_received"] + EPSILON)

    mule_accounts = acct_stats[
        (acct_stats["total_received"] >= MULE_MIN_RECV)
        & (acct_stats["flow_ratio"].between(MULE_FLOW_LOW, MULE_FLOW_HIGH))
        & (acct_stats["tx_count"] >= MULE_MIN_TX)
    ].index

    df["is_mule_account"] = df["Account"].isin(mule_accounts).astype("int8")
    return df[current_mask_aligned].copy()