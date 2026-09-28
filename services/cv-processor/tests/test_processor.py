"""Unit tests for cv-processor. Postgres + MinIO are mocked so tests run offline."""
import io
from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def client():
    # Patch backends before importing the app so module-level init() is inert.
    with patch("psycopg2.connect"), patch("minio.Minio"):
        from app import main

        main.app.testing = True
        yield main.app.test_client()


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200


def test_process_extracts_pagecount(client):
    fake_conn = MagicMock()
    fake_cur = MagicMock()
    fake_conn.__enter__.return_value = fake_conn
    fake_conn.cursor.return_value.__enter__.return_value = fake_cur

    minimal_pdf = (
        b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
        b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
        b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 100 100]>>endobj\n"
        b"trailer<</Root 1 0 R>>\n%%EOF"
    )
    with patch("app.main.db", return_value=fake_conn), patch("app.main.object_store"):
        data = {
            "file": (io.BytesIO(minimal_pdf), "cv.pdf"),
            "name": "Ada",
            "email": "ada@example.com",
        }
        r = client.post("/internal/cvs", data=data, content_type="multipart/form-data")
    assert r.status_code == 201
    assert "id" in r.get_json()
