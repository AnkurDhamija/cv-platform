"""Unit tests for public-api. Upstream cv-processor is mocked."""
import io
from unittest.mock import patch

import pytest

from app.main import app


@pytest.fixture
def client():
    app.testing = True
    return app.test_client()


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_upload_rejects_non_pdf(client):
    data = {
        "file": (io.BytesIO(b"not a pdf"), "x.pdf"),
        "name": "Ada",
        "email": "ada@example.com",
    }
    r = client.post("/cvs", data=data, content_type="multipart/form-data")
    assert r.status_code == 415


def test_upload_rejects_bad_email(client):
    data = {
        "file": (io.BytesIO(b"%PDF-1.4 ..."), "x.pdf"),
        "name": "Ada",
        "email": "not-an-email",
    }
    r = client.post("/cvs", data=data, content_type="multipart/form-data")
    assert r.status_code == 400


def test_upload_forwards_valid_pdf(client):
    class FakeResp:
        status_code = 201

        def json(self):
            return {"id": "abc-123", "page_count": 1}

    with patch("app.main.requests.post", return_value=FakeResp()):
        data = {
            "file": (io.BytesIO(b"%PDF-1.4 hello"), "cv.pdf"),
            "name": "Ada",
            "email": "ada@example.com",
        }
        r = client.post("/cvs", data=data, content_type="multipart/form-data")
    assert r.status_code == 201
    assert r.get_json()["id"] == "abc-123"


def test_get_rejects_non_uuid_id(client):
    # A non-UUID path param must be rejected before any upstream request is made
    # (SSRF / path-injection mitigation).
    r = client.get("/cvs/not-a-uuid")
    assert r.status_code == 400


def test_delete_rejects_non_uuid_id(client):
    r = client.delete("/cvs/12345-not-a-uuid")
    assert r.status_code == 400
