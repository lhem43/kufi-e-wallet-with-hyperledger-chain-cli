"""
transaction_store.py
Purpose:
    - After each inference, save current batch into store.
    - Next inference, load history and combine with new batch 
API:
    store = TransactionStore(path)
    store.load_history()              
    store.save(df_batch)              
    store.combine_with_history(df_new)
    store.clear()                     
    store.info()                     
"""

from __future__ import annotations

import warnings
from pathlib import Path

import pandas as pd


CURRENT_FLAG = "is_current"
RAW_COLS = [
    "TransactionId",
    "Timestamp", "Account", "Account.1",
    "From Bank", "To Bank",
    "Amount Paid", "Amount Received",
    "Payment Format", "Payment Currency", "Receiving Currency",
]


def save_files() -> str:
    try:
        import importlib
        if importlib.util.find_spec("pyarrow") or importlib.util.find_spec("fastparquet"):
            return "parquet"
    except Exception:
        pass
    return "csv"

class TransactionStore:
    """
    Save transaction history to a file.
    Args:
        store_path : "data/transaction_history.parquet" (.parquet or .csv) 
    """

    def __init__(self, store_path: str | Path = "data/transaction_history.parquet"):
        self._path = Path(store_path)
        self._backend = save_files()

        if self._path.suffix == "":
            ext = ".parquet" if self._backend == "parquet" else ".csv"
            self._path = self._path.with_suffix(ext)

        self._path.parent.mkdir(parents=True, exist_ok=True)


    @property
    def path(self) -> Path:
        return self._path

    @property
    def exists(self) -> bool:
        return self._path.exists()

    def load_history(self) -> pd.DataFrame | None:
        """
        Read history
        """
        if not self.exists:
            return None

        try:
            if self._backend == "parquet":
                df = pd.read_parquet(self._path)
            else:
                df = pd.read_csv(self._path, parse_dates=["Timestamp"])

            if not pd.api.types.is_datetime64_any_dtype(df["Timestamp"]):
                df["Timestamp"] = pd.to_datetime(df["Timestamp"])

            return df

        except Exception as e:
            return None

    def save(self, df_batch: pd.DataFrame) -> None:
        """
        Append new batch into store.
        """
        cols_to_save = [c for c in RAW_COLS if c in df_batch.columns]
        df_new = df_batch[cols_to_save].copy()

        if not pd.api.types.is_datetime64_any_dtype(df_new["Timestamp"]):
            df_new["Timestamp"] = pd.to_datetime(df_new["Timestamp"])

        existing = self.load_history()
        if existing is not None:
            combined = pd.concat([existing[cols_to_save], df_new], ignore_index=True)
        else:
            combined = df_new

        dedup_keys = (
            ["TransactionId"]
            if "TransactionId" in combined.columns
            else ["Timestamp", "Account", "Account.1"]
        )
        combined = (
            combined
            .drop_duplicates(subset=dedup_keys)
            .sort_values("Timestamp")
            .reset_index(drop=True)
        )

        try:
            if self._backend == "parquet":
                combined.to_parquet(self._path, index=False)
            else:
                combined.to_csv(self._path, index=False)
        except Exception as e:
            warnings.warn(f"[TransactionStore] Không ghi được store ({e}).", stacklevel=2)

    def combine_with_history(self, df_new: pd.DataFrame) -> pd.DataFrame:
        """
        Merge history with new batch. Mark new batch with column 'is_current'.

        Returns:
            df_combined : DataFrame including [history rows] + [current rows],

        Notes:
            - History rows has is_current = False -> compute feature but not predict
            - Current rows has is_current = True -> tính feature and predict
        """
        if not pd.api.types.is_datetime64_any_dtype(df_new["Timestamp"]):
            df_new = df_new.copy()
            df_new["Timestamp"] = pd.to_datetime(df_new["Timestamp"])

        # Mark current batch
        df_current = df_new.copy()
        df_current[CURRENT_FLAG] = True

        history = self.load_history()

        if history is None or history.empty:
            df_current[CURRENT_FLAG] = True
            return df_current.sort_values("Timestamp").reset_index(drop=True)

        hist_cols = [c for c in RAW_COLS if c in history.columns]
        df_hist = history[hist_cols].copy()
        df_hist[CURRENT_FLAG] = False

        dedup_keys = (
            ["TransactionId"]
            if "TransactionId" in df_current.columns and "TransactionId" in df_hist.columns
            else ["Timestamp", "Account", "Account.1"]
        )

        if dedup_keys == ["TransactionId"]:
            current_keys = set(df_current["TransactionId"])
            mask_not_dup = ~df_hist["TransactionId"].isin(current_keys)
        else:
            current_keys = set(
                zip(df_current["Timestamp"], df_current["Account"], df_current["Account.1"])
            )
            mask_not_dup = ~df_hist.apply(
                lambda r: (r["Timestamp"], r["Account"], r["Account.1"]) in current_keys,
                axis=1,
            )
        df_hist = df_hist[mask_not_dup]

        combined = (
            pd.concat([df_hist, df_current], ignore_index=True)
            .sort_values("Timestamp")
            .reset_index(drop=True)
        )

        n_hist    = int((~combined[CURRENT_FLAG]).sum())
        n_current = int(combined[CURRENT_FLAG].sum())
        print(
            f"[TransactionStore] Combined: {n_hist} history rows + "
            f"{n_current} current rows = {len(combined)} total"
        )

        return combined

    def clear(self) -> None:
        """Clear history"""
        if self.exists:
            self._path.unlink()
            print(f"[TransactionStore] Cleared: {self._path}")
        else:
            print("[TransactionStore] Store doesn't exist")

    def info(self) -> dict:
        """Return current store"""
        if not self.exists:
            return {"exists": False, "path": str(self._path)}

        df = self.load_history()
        if df is None or df.empty:
            return {"exists": True, "rows": 0, "path": str(self._path)}

        return {
            "exists": True,
            "path" : str(self._path),
            "backend": self._backend,
            "rows" : len(df),
            "accounts": int(pd.unique(pd.concat([df["Account"], df["Account.1"]])).shape[0]),
            "date_from": str(df["Timestamp"].min()),
            "date_to": str(df["Timestamp"].max()),
            "size_kb": round(self._path.stat().st_size / 1024, 1),
        }
