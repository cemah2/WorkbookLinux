"""Tests unitaires de l'API — sans PostgreSQL ni Redis (CI rapide)."""
import os

import pytest

os.environ.setdefault("APP_VERSION", "test")
os.environ.setdefault("APP_COLOR", "blue")

import app as factura  # noqa: E402


@pytest.fixture
def client():
    factura.app.config["TESTING"] = True
    with factura.app.test_client() as c:
        yield c


def test_montant_ttc():
    assert factura.montant_ttc(100) == 120.0
    assert factura.montant_ttc(10.10) == 12.12
    with pytest.raises(ValueError):
        factura.montant_ttc(-1)


def test_route_label():
    assert factura.route_label("/api/factures/42") == "/api/factures/<id>"
    assert factura.route_label("/health") == "/health"


def test_version(client):
    r = client.get("/version")
    assert r.status_code == 200
    body = r.get_json()
    assert body["version"] == "test"
    assert body["color"] == "blue"


def test_metrics(client):
    client.get("/version")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"factura_http_requests_total" in r.data


def test_post_invalide(client):
    r = client.post("/api/factures", json={"client": "ACME"})
    assert r.status_code == 400
