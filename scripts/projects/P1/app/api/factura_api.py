#!/usr/bin/env python3
"""Factura — API interne de facturation (projet A du workbook).

Routes :
  GET  /health                 état de l'API, de PostgreSQL et de Redis
  GET  /invoices?limit=N       liste des factures (50 par défaut)
  POST /invoices               crée une facture, la met en file d'export
  GET  /invoices/<id>          détail d'une facture
  POST /invoices/<id>/requeue  remet une facture dans la file d'export
  GET  /metrics                métriques au format texte Prometheus

Configuration par variables d'environnement (voir /etc/factura/api.env) :
  FACTURA_DB_URL     postgresql://factura_app:motdepasse@lab-db:5432/factura
  FACTURA_REDIS_URL  redis://:motdepasse@lab-db:6379/0
  FACTURA_QUEUE      nom de la liste Redis (défaut : factura:jobs)
  FACTURA_LOG_LEVEL  INFO par défaut

Lancement : gunicorn -b 127.0.0.1:8000 factura_api:app
"""
import json
import logging
import os
import time

import psycopg
import redis
from flask import Flask, Response, jsonify, request
from psycopg.rows import dict_row

VERSION = "1.0.0"
DB_URL = os.environ.get(
    "FACTURA_DB_URL", "postgresql://factura_app@127.0.0.1:5432/factura")
REDIS_URL = os.environ.get("FACTURA_REDIS_URL", "redis://127.0.0.1:6379/0")
QUEUE = os.environ.get("FACTURA_QUEUE", "factura:jobs")
METRICS_KEY = "factura:metrics"
HEARTBEAT_KEY = "factura:worker:heartbeat"

logging.basicConfig(
    level=os.environ.get("FACTURA_LOG_LEVEL", "INFO"),
    format="%(asctime)s factura-api %(levelname)s %(message)s")
log = logging.getLogger("factura-api")

app = Flask(__name__)
_redis = redis.Redis.from_url(REDIS_URL, socket_timeout=2,
                              socket_connect_timeout=2,
                              decode_responses=True)


def db():
    """Une connexion par requête : simple, sans pool, suffisant ici."""
    return psycopg.connect(DB_URL, connect_timeout=3, row_factory=dict_row)


def count_request(status):
    try:
        _redis.hincrby(METRICS_KEY, f"http_{status}", 1)
    except redis.RedisError:
        pass


@app.after_request
def after(resp):
    count_request(resp.status_code)
    return resp


@app.errorhandler(Exception)
def on_error(exc):
    log.error("erreur non geree: %s", exc)
    return jsonify(error=str(exc)), 500


@app.get("/health")
def health():
    state = {"status": "ok", "version": VERSION, "db": "ok", "redis": "ok"}
    try:
        with db() as conn:
            conn.execute("SELECT 1")
    except Exception as exc:  # noqa: BLE001
        state["db"] = f"ko: {exc}".strip()
    try:
        _redis.ping()
    except redis.RedisError as exc:
        state["redis"] = f"ko: {exc}"
    if state["db"] != "ok" or state["redis"] != "ok":
        state["status"] = "degraded"
        return jsonify(state), 503
    return jsonify(state)


@app.get("/invoices")
def list_invoices():
    limit = min(int(request.args.get("limit", 50)), 500)
    with db() as conn:
        rows = conn.execute(
            "SELECT id, number, customer, amount_cents, currency, status, "
            "pdf_path, created_at, exported_at FROM invoices "
            "ORDER BY id DESC LIMIT %s", (limit,)).fetchall()
    return jsonify(rows)


@app.post("/invoices")
def create_invoice():
    data = request.get_json(silent=True) or {}
    customer = str(data.get("customer", "")).strip()
    try:
        amount_cents = int(round(float(data.get("amount", 0)) * 100))
    except (TypeError, ValueError):
        return jsonify(error="amount invalide"), 400
    if not customer or amount_cents <= 0:
        return jsonify(error="customer et amount (> 0) obligatoires"), 400
    currency = str(data.get("currency", "EUR")).upper()[:3]
    with db() as conn:
        row = conn.execute(
            "INSERT INTO invoices (number, customer, amount_cents, currency) "
            "VALUES (next_invoice_number(), %s, %s, %s) "
            "RETURNING id, number, status", (customer, amount_cents, currency)
        ).fetchone()
    _redis.lpush(QUEUE, json.dumps({"invoice_id": row["id"],
                                    "enqueued_at": time.time()}))
    log.info("facture %s creee (id=%s) pour %s", row["number"], row["id"],
             customer)
    return jsonify(row), 201


@app.get("/invoices/<int:inv_id>")
def get_invoice(inv_id):
    with db() as conn:
        row = conn.execute("SELECT * FROM invoices WHERE id = %s",
                           (inv_id,)).fetchone()
    if row is None:
        return jsonify(error="facture inconnue"), 404
    return jsonify(row)


@app.post("/invoices/<int:inv_id>/requeue")
def requeue_invoice(inv_id):
    with db() as conn:
        row = conn.execute(
            "UPDATE invoices SET status = 'pending', pdf_path = NULL, "
            "exported_at = NULL WHERE id = %s RETURNING id, number",
            (inv_id,)).fetchone()
    if row is None:
        return jsonify(error="facture inconnue"), 404
    _redis.lpush(QUEUE, json.dumps({"invoice_id": inv_id,
                                    "enqueued_at": time.time()}))
    log.info("facture %s remise en file", row["number"])
    return jsonify(row), 202


@app.get("/metrics")
def metrics():
    lines = [f'factura_api_info{{version="{VERSION}"}} 1']
    try:
        with db() as conn:
            for r in conn.execute("SELECT status, count(*) AS n "
                                  "FROM invoices GROUP BY status"):
                lines.append(
                    f'factura_invoices_total{{status="{r["status"]}"}} '
                    f'{r["n"]}')
        lines.append("factura_db_up 1")
    except Exception:  # noqa: BLE001
        lines.append("factura_db_up 0")
    try:
        lines.append(f"factura_queue_length {_redis.llen(QUEUE)}")
        for k, v in _redis.hgetall(METRICS_KEY).items():
            code = k.removeprefix("http_")
            lines.append(f'factura_http_requests_total{{code="{code}"}} {v}')
        hb = _redis.get(HEARTBEAT_KEY)
        alive = 1 if hb and time.time() - float(hb) < 30 else 0
        lines.append(f"factura_worker_alive {alive}")
        lines.append("factura_redis_up 1")
    except redis.RedisError:
        lines.append("factura_redis_up 0")
    return Response("\n".join(lines) + "\n", mimetype="text/plain")


if __name__ == "__main__":  # lancement de dev uniquement
    app.run(host="127.0.0.1", port=8000)
