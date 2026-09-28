"""
public-api — public entry point (namespace: frontend).

Stateless. Validates uploads and proxies to cv-processor. Owns NO data.
This separation is deliberate: a compromise of public-api must not yield
direct access to storage (see docs/ARCHITECTURE_AND_THREATS.md, threat #1).
"""
import os
import re
import uuid

import requests
from flask import Flask, jsonify, request
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
# Exposes /metrics with http_request_duration_seconds + http_request_total
# (status-labelled), which back the availability + latency SLOs (Part 6).
metrics = PrometheusMetrics(app, group_by="endpoint")
metrics.info("public_api_info", "public-api build info", version="1.0.0")

# --- Config (all via env; no secrets baked in) -------------------------------
CV_PROCESSOR_URL = os.environ.get("CV_PROCESSOR_URL", "http://cv-processor.backend.svc.cluster.local:8081")
MAX_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))  # 10 MiB
REQUEST_TIMEOUT = float(os.environ.get("UPSTREAM_TIMEOUT_S", "10"))

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PDF_MAGIC = b"%PDF-"


def _valid_cv_id(cv_id: str) -> bool:
    """Path params are forwarded into the upstream URL, so accept ONLY a strict
    UUID. This ensures a caller can never inject a scheme/host/path segment into
    the server-side request (mitigates the SSRF / path-injection class)."""
    try:
        uuid.UUID(str(cv_id))
        return True
    except (ValueError, AttributeError, TypeError):
        return False


@app.get("/health")
def health():
    return jsonify(status="ok"), 200


@app.post("/cvs")
def upload_cv():
    # --- Validate multipart fields ------------------------------------------
    if "file" not in request.files:
        return jsonify(error="missing 'file'"), 400
    name = (request.form.get("name") or "").strip()
    email = (request.form.get("email") or "").strip()
    if not name:
        return jsonify(error="missing 'name'"), 400
    if not EMAIL_RE.match(email):
        return jsonify(error="invalid 'email'"), 400

    f = request.files["file"]
    data = f.read(MAX_BYTES + 1)
    if len(data) == 0:
        return jsonify(error="empty file"), 400
    if len(data) > MAX_BYTES:
        return jsonify(error=f"file exceeds {MAX_BYTES} bytes"), 413

    # --- Validate content type by magic bytes, not trusting the filename -----
    if not data.startswith(PDF_MAGIC):
        return jsonify(error="only PDF uploads are accepted"), 415

    # --- Forward to the internal processor -----------------------------------
    try:
        resp = requests.post(
            f"{CV_PROCESSOR_URL}/internal/cvs",
            files={"file": ("upload.pdf", data, "application/pdf")},
            data={"name": name, "email": email},
            timeout=REQUEST_TIMEOUT,
        )
    except requests.RequestException:
        return jsonify(error="processor unavailable"), 502

    if resp.status_code >= 400:
        return jsonify(error="processing failed"), 502
    return jsonify(resp.json()), 201


@app.get("/cvs/<cv_id>")
def get_cv(cv_id):
    if not _valid_cv_id(cv_id):
        return jsonify(error="invalid id"), 400
    try:
        # cv_id is a validated UUID (above) and CV_PROCESSOR_URL is a fixed
        # internal env var, so the destination is not attacker-controlled.
        resp = requests.get(  # nosemgrep: python.flask.security.injection.ssrf-requests.ssrf-requests
            f"{CV_PROCESSOR_URL}/internal/cvs/{cv_id}", timeout=REQUEST_TIMEOUT
        )
    except requests.RequestException:
        return jsonify(error="processor unavailable"), 502
    return jsonify(resp.json()), resp.status_code


@app.delete("/cvs/<cv_id>")
def delete_cv(cv_id):
    """GDPR erasure — deletes the file and all metadata via the processor."""
    if not _valid_cv_id(cv_id):
        return jsonify(error="invalid id"), 400
    try:
        # cv_id is a validated UUID (above) and CV_PROCESSOR_URL is a fixed
        # internal env var, so the destination is not attacker-controlled.
        resp = requests.delete(  # nosemgrep: python.flask.security.injection.ssrf-requests.ssrf-requests
            f"{CV_PROCESSOR_URL}/internal/cvs/{cv_id}", timeout=REQUEST_TIMEOUT
        )
    except requests.RequestException:
        return jsonify(error="processor unavailable"), 502
    if resp.status_code == 404:
        return jsonify(error="not found"), 404
    return jsonify(status="deleted", id=cv_id), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
