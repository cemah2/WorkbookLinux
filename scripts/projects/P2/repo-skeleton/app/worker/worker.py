#!/usr/bin/env python3
"""Factura v2 — worker : consomme factura:jobs et passe la facture en
statut « traitee ». Expose ses métriques sur :9200."""
import json
import logging
import os
import signal
import sys
import time

import psycopg
import redis as redislib
from prometheus_client import Counter, start_http_server

DATABASE_URL = os.environ["DATABASE_URL"]
REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
VERSION = os.environ.get("APP_VERSION", "dev")
DELAI = float(os.environ.get("WORKER_DELAI", "0.5"))

TRAITES = Counter("factura_jobs_processed_total", "Jobs traités", ["result"])
running = True


def stop(*_):
    global running
    running = False


def log(level, msg, **kv):
    doc = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "level": level,
           "logger": "factura.worker", "msg": msg, "version": VERSION}
    doc.update(kv)
    print(json.dumps(doc, ensure_ascii=False), flush=True)


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    start_http_server(9200)
    q = redislib.from_url(REDIS_URL)
    log("INFO", "worker démarré")
    while running:
        try:
            item = q.blpop("factura:jobs", timeout=2)
        except redislib.exceptions.ConnectionError as exc:
            log("ERROR", "redis injoignable", err=str(exc))
            time.sleep(2)
            continue
        if item is None:
            continue
        fid = json.loads(item[1])["id"]
        try:
            time.sleep(DELAI)  # simule un traitement
            with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
                conn.execute("UPDATE factures SET statut='traitee' "
                             "WHERE id=%s", (fid,))
                conn.commit()
            TRAITES.labels("ok").inc()
            log("INFO", "facture traitée", id=fid)
        except Exception as exc:  # noqa: BLE001
            TRAITES.labels("error").inc()
            log("ERROR", "échec de traitement", id=fid, err=str(exc))
            q.rpush("factura:jobs", json.dumps({"id": fid}))
            time.sleep(1)
    log("INFO", "arrêt propre")


if __name__ == "__main__":
    logging.basicConfig(stream=sys.stdout, level="WARNING")
    main()
