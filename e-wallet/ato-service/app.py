import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")

import joblib
import numpy as np


BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = Path(os.getenv("ATO_MODEL_PATH", BASE_DIR / "models" / "lgbm_fraud_final.pkl"))
METADATA_PATH = Path(
    os.getenv("ATO_METADATA_PATH", BASE_DIR / "models" / "model_metadata.json")
)
HOST = os.getenv("ATO_HOST", "0.0.0.0")
PORT = int(os.getenv("ATO_PORT", "3010"))

MODEL = joblib.load(MODEL_PATH)
METADATA = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
FEATURES = METADATA["features"]
THRESHOLD = float(METADATA["best_threshold"])
MODEL_VERSION = (
    f'{METADATA.get("model_type", "model")}'
    f':lgbm-{METADATA.get("lightgbm_version", "unknown")}'
    f':features-{METADATA.get("n_features", len(FEATURES))}'
)


class AtoHandler(BaseHTTPRequestHandler):
    server_version = "AtoInference/1.0"

    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/healthz":
            self.write_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "modelVersion": MODEL_VERSION,
                    "features": FEATURES,
                    "threshold": THRESHOLD,
                },
            )
            return
        self.write_json(HTTPStatus.NOT_FOUND, {"message": "Not found"})

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/score":
            self.write_json(HTTPStatus.NOT_FOUND, {"message": "Not found"})
            return

        try:
            payload = self.read_json()
            feature_payload = payload.get("features", payload)
            vector = self.vectorize(feature_payload)
            probability = float(MODEL.predict_proba(vector)[0, 1])
            verdict = "ATO_SUSPECTED" if probability >= THRESHOLD else "LEGITIMATE"
            self.write_json(
                HTTPStatus.OK,
                {
                    "verdict": verdict,
                    "probability": round(probability, 6),
                    "threshold": THRESHOLD,
                    "modelVersion": MODEL_VERSION,
                },
            )
        except ValueError as exc:
            self.write_json(HTTPStatus.BAD_REQUEST, {"message": str(exc)})
        except Exception as exc:
            self.write_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"message": f"ATO inference failed: {exc}"},
            )

    def log_message(self, fmt: str, *args: Any) -> None:
        if os.getenv("ATO_ACCESS_LOG", "false").lower() == "true":
            super().log_message(fmt, *args)

    def read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("content-length", "0") or "0")
        if length <= 0:
            raise ValueError("JSON body is required")
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError("Invalid JSON body") from exc
        if not isinstance(payload, dict):
            raise ValueError("JSON object body is required")
        return payload

    def vectorize(self, payload: Any) -> np.ndarray:
        if not isinstance(payload, dict):
            raise ValueError("features must be an object")

        values: list[float] = []
        missing: list[str] = []
        for name in FEATURES:
            if name not in payload:
                missing.append(name)
                continue
            try:
                values.append(float(payload[name]))
            except (TypeError, ValueError) as exc:
                raise ValueError(f"feature {name} must be numeric") from exc

        if missing:
            raise ValueError(f"missing features: {', '.join(missing)}")

        return np.asarray([values], dtype=np.float32)

    def write_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(int(status))
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), AtoHandler)
    print(
        json.dumps(
            {
                "event": "ato_service_started",
                "host": HOST,
                "port": PORT,
                "modelVersion": MODEL_VERSION,
                "threshold": THRESHOLD,
            },
            separators=(",", ":"),
        ),
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
