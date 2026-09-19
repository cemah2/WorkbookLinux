#!/usr/bin/env python3
"""Factura v2 — API minimale (workbook, projet B).

Endpoints :
  GET  /health         état de l'API, de PostgreSQL et de Redis
  GET  /version        version et couleur (blue/green) de l'instance
  GET  /metrics        exposition Prometheus
  GET  /api/factures   liste des factures
  POST /api/factures   crée une facture et pousse un job au worker
  GET  /api/factures/<id>

Configuration par variables d'environnement :
  APP_VERSION, APP_COLOR, DATABASE_URL, REDIS_URL, LOG_LEVEL
"""
import json
import logging
import os
import sys
import time

import psycopg
import redis as redislib
from flask import Flask, Response, g, jsonify, request
from prometheus_client import (CONTENT_TYPE_LATEST, Counter, Histogram,
                               generate_latest)

VERSION = os.environ.get("APP_VERSION", "dev")
COLOR = os.environ.get("APP_COLOR", "none")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

REQUESTS = Counter(
    "factura_http_requests_total", "Requêtes HTTP traitées",
    ["method", "path", "status"])
LATENCY = Histogram(
    "factura_http_request_seconds", "Latence des requêtes HTTP", ["path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5))
JOBS = Counter("factura_jobs_enqueued_total", "Jobs poussés vers le worker")


class JsonFormatter(logging.Formatter):
    """Une ligne JSON par événement : Loki/promtail les parse sans regex."""

    def format(self, record):
        doc = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "version": VERSION,
            "color": COLOR,
        }
        if record.exc_info:
            doc["exc"] = self.formatException(record.exc_info)
        return json.dumps(doc, ensure_ascii=False)


def setup_logging():
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(LOG_LEVEL)


def montant_ttc(montant_ht, taux=0.20):
    """Calcule le TTC arrondi au centime. Fonction pure, testée en CI."""
    if montant_ht < 0:
        raise ValueError("montant négatif")
    return round(float(montant_ht) * (1 + taux), 2)


def route_label(path):
    """Regroupe /api/factures/42 sous /api/factures/<id> (cardinalité)."""
    parts = path.strip("/").split("/")
    if len(parts) == 3 and parts[:2] == ["api", "factures"]:
        return "/api/factures/<id>"
    return path


def create_app():
    setup_logging()
    app = Flask(__name__)
    log = logging.getLogger("factura.api")

    def db():
        return psycopg.connect(DATABASE_URL, connect_timeout=3)

    def queue():
        return redislib.from_url(REDIS_URL, socket_connect_timeout=2)

    @app.before_request
    def _start():
        g.t0 = time.perf_counter()

    @app.after_request
    def _observe(resp):
        label = route_label(request.path)
        REQUESTS.labels(request.method, label, resp.status_code).inc()
        if hasattr(g, "t0"):
            LATENCY.labels(label).observe(time.perf_counter() - g.t0)
        return resp

    @app.get("/health")
    def health():
        status = {"status": "ok", "db": "ok", "redis": "ok"}
        code = 200
        try:
            with db() as conn:
                conn.execute("SELECT 1")
        except Exception as exc:  # noqa: BLE001
            status["db"] = f"ko: {exc.__class__.__name__}"
            status["status"] = "degraded"
            code = 503
        try:
            queue().ping()
        except Exception as exc:  # noqa: BLE001
            status["redis"] = f"ko: {exc.__class__.__name__}"
            status["status"] = "degraded"
            code = 503
        return jsonify(status), code

    @app.get("/version")
    def version():
        return jsonify({"app": "factura-api", "version": VERSION,
                        "color": COLOR})

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    @app.get("/api/factures")
    def list_factures():
        with db() as conn:
            rows = conn.execute(
                "SELECT id, client, montant_ht, montant_ttc, statut, "
                "created_at FROM factures ORDER BY id DESC LIMIT 100"
            ).fetchall()
        return jsonify([_row(r) for r in rows])

    @app.get("/api/factures/<int:fid>")
    def get_facture(fid):
        with db() as conn:
            row = conn.execute(
                "SELECT id, client, montant_ht, montant_ttc, statut, "
                "created_at FROM factures WHERE id = %s", (fid,)).fetchone()
        if row is None:
            return jsonify({"error": "introuvable"}), 404
        return jsonify(_row(row))

    @app.post("/api/factures")
    def create_facture():
        data = request.get_json(silent=True) or {}
        client = str(data.get("client", "")).strip()
        try:
            ht = float(data.get("montant_ht"))
            ttc = montant_ttc(ht)
        except (TypeError, ValueError):
            return jsonify({"error": "montant_ht invalide"}), 400
        if not client:
            return jsonify({"error": "client requis"}), 400
        with db() as conn:
            row = conn.execute(
                "INSERT INTO factures (client, montant_ht, montant_ttc) "
                "VALUES (%s, %s, %s) RETURNING id", (client, ht, ttc)
            ).fetchone()
            conn.commit()
        fid = row[0]
        try:
            queue().rpush("factura:jobs", json.dumps({"id": fid}))
            JOBS.inc()
        except Exception:  # noqa: BLE001
            log.exception("job non poussé pour la facture %s", fid)
        log.info("facture créée id=%s client=%s ttc=%s", fid, client, ttc)
        return jsonify({"id": fid, "montant_ttc": ttc,
                        "statut": "nouvelle"}), 201

    return app


def _row(r):
    return {"id": r[0], "client": r[1], "montant_ht": float(r[2]),
            "montant_ttc": float(r[3]), "statut": r[4],
            "created_at": r[5].isoformat() if r[5] else None}


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
