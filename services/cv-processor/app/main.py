"""
cv-processor — internal service (namespace: backend).

Owns ALL data. Extracts basic info from each PDF (page count, first ~500
characters), stores the file in object storage and metadata in PostgreSQL.
Never exposed to the public; only public-api may reach it (enforced by
NetworkPolicy). Must not reach the internet.

Object storage backend is chosen at runtime, so the SAME image runs locally
and on GCP without a rebuild:
  * GCP  — native Google Cloud Storage via Application Default Credentials.
           On GKE these resolve to the pod's Workload Identity (KSA -> GSA),
           so writes are keyless: no access keys, no HMAC. Selected when
           GCS_BUCKET is set.
  * Local — S3-compatible object store (MinIO / s3mock) via the minio client.
           Hermetic `make up`; selected when GCS_BUCKET is empty.
"""
import io
import os
import uuid

import psycopg2
import psycopg2.extras
from flask import Flask, jsonify, request
from prometheus_flask_exporter import PrometheusMetrics
from pypdf import PdfReader

app = Flask(__name__)
metrics = PrometheusMetrics(app, group_by="endpoint")
metrics.info("cv_processor_info", "cv-processor build info", version="1.0.0")

# --- Config -----------------------------------------------------------------
PG_DSN = os.environ.get(
    "PG_DSN",
    "host=postgres.backend.svc.cluster.local dbname=cvs user=cvuser password=changeme",
)
# GCP object storage (native GCS via Workload Identity). Empty -> use S3/MinIO.
GCS_BUCKET = os.environ.get("GCS_BUCKET", "").strip()

# S3-compatible object storage (local MinIO / s3mock).
MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "minio.backend.svc.cluster.local:9000")
MINIO_ACCESS = os.environ.get("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.environ.get("MINIO_SECRET_KEY", "minioadmin")
MINIO_BUCKET = os.environ.get("MINIO_BUCKET", "cvs")
MINIO_SECURE = os.environ.get("MINIO_SECURE", "false").lower() == "true"

SNIPPET_CHARS = int(os.environ.get("SNIPPET_CHARS", "500"))
CONTENT_TYPE = "application/pdf"


def db():
    return psycopg2.connect(PG_DSN)


# --- Object storage abstraction ---------------------------------------------
class GcsStore:
    """Native Google Cloud Storage. Credentials come from ADC / Workload
    Identity — no static keys. The bucket is provisioned by Terraform, and the
    cv-processor identity is granted objectAdmin (object-level) but NOT
    bucket-create, so we never attempt to create it here (least privilege)."""

    backend = "gcs"

    def __init__(self, bucket):
        from google.cloud import storage  # lazy import so local builds need not install it

        self._bucket = storage.Client().bucket(bucket)
        self.name = bucket

    def ensure_bucket(self):
        return  # Terraform owns the bucket; creating it is not our privilege.

    def put(self, key, raw):
        blob = self._bucket.blob(key)
        blob.upload_from_file(io.BytesIO(raw), size=len(raw), content_type=CONTENT_TYPE)

    def remove(self, key):
        self._bucket.blob(key).delete()


class S3Store:
    """S3-compatible store (MinIO / s3mock) for local, hermetic runs."""

    backend = "s3"

    def __init__(self):
        from minio import Minio

        self._mc = Minio(MINIO_ENDPOINT, access_key=MINIO_ACCESS, secret_key=MINIO_SECRET, secure=MINIO_SECURE)
        self.name = MINIO_BUCKET

    def ensure_bucket(self):
        if not self._mc.bucket_exists(self.name):
            self._mc.make_bucket(self.name)

    def put(self, key, raw):
        from minio.error import S3Error

        try:
            self._mc.put_object(self.name, key, io.BytesIO(raw), length=len(raw), content_type=CONTENT_TYPE)
        except S3Error as e:
            # Self-heal the boot-ordering race (bucket not yet present): create
            # it and retry once, so a cold start can never wedge on NoSuchBucket.
            if getattr(e, "code", "") == "NoSuchBucket":
                self._mc.make_bucket(self.name)
                self._mc.put_object(self.name, key, io.BytesIO(raw), length=len(raw), content_type=CONTENT_TYPE)
            else:
                raise

    def remove(self, key):
        self._mc.remove_object(self.name, key)


def object_store():
    return GcsStore(GCS_BUCKET) if GCS_BUCKET else S3Store()


def init():
    """Create table (+ bucket for the local S3 store) if absent. Idempotent."""
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS cvs (
                id          UUID PRIMARY KEY,
                name        TEXT NOT NULL,
                email       TEXT NOT NULL,
                object_key  TEXT NOT NULL,
                page_count  INTEGER,
                snippet     TEXT,
                created_at  TIMESTAMPTZ DEFAULT now()
            );
            """
        )
        conn.commit()
    object_store().ensure_bucket()


@app.get("/health")
def health():
    return jsonify(status="ok"), 200


@app.post("/internal/cvs")
def process_cv():
    f = request.files.get("file")
    name = (request.form.get("name") or "").strip()
    email = (request.form.get("email") or "").strip()
    if not f or not name or not email:
        return jsonify(error="missing fields"), 400

    raw = f.read()
    cv_id = str(uuid.uuid4())
    object_key = f"{cv_id}.pdf"

    page_count, snippet = None, ""
    try:
        reader = PdfReader(io.BytesIO(raw))
        page_count = len(reader.pages)
        if reader.pages:
            snippet = (reader.pages[0].extract_text() or "")[:SNIPPET_CHARS]
    except Exception:
        page_count = None

    object_store().put(object_key, raw)

    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO cvs (id, name, email, object_key, page_count, snippet) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (cv_id, name, email, object_key, page_count, snippet),
        )
        conn.commit()

    return jsonify(id=cv_id, page_count=page_count), 201


@app.get("/internal/cvs/<cv_id>")
def get_cv(cv_id):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT id, name, email, page_count, snippet, created_at FROM cvs WHERE id = %s",
            (cv_id,),
        )
        row = cur.fetchone()
    if not row:
        return jsonify(error="not found"), 404
    row["id"] = str(row["id"])
    row["created_at"] = row["created_at"].isoformat() if row["created_at"] else None
    return jsonify(row), 200


@app.delete("/internal/cvs/<cv_id>")
def delete_cv(cv_id):
    """GDPR erasure — remove object + metadata row together."""
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT object_key FROM cvs WHERE id = %s", (cv_id,))
        row = cur.fetchone()
        if not row:
            return jsonify(error="not found"), 404
        object_key = row[0]
        cur.execute("DELETE FROM cvs WHERE id = %s", (cv_id,))
        conn.commit()
    try:
        object_store().remove(object_key)
    except Exception:
        pass
    return jsonify(status="deleted", id=cv_id), 200


try:
    init()
except Exception as e:
    app.logger.warning("init deferred: %s", e)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)
