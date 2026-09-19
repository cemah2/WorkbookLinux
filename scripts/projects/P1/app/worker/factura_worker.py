#!/usr/bin/env python3
"""Factura — worker d'export (projet A du workbook).

Boucle : BRPOP sur la liste Redis FACTURA_QUEUE, lecture de la facture dans
PostgreSQL, génération d'un PDF factice dans FACTURA_EXPORT_DIR, mise à jour
du statut (exported / error). Un battement de cœur est posé dans Redis toutes
les 5 s (clé factura:worker:heartbeat), lu par /metrics de l'API.

Configuration par variables d'environnement (voir /etc/factura/worker.env) :
  FACTURA_DB_URL      postgresql://factura_app:motdepasse@lab-db:5432/factura
  FACTURA_REDIS_URL   redis://:motdepasse@lab-db:6379/0
  FACTURA_QUEUE       factura:jobs (défaut)
  FACTURA_EXPORT_DIR  /srv/factura/exports (défaut)
  FACTURA_LOG_LEVEL   INFO (défaut)

Le worker s'arrête proprement sur SIGTERM/SIGINT : il termine le job en
cours puis sort avec le code 0.
"""
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import psycopg
import redis
from psycopg.rows import dict_row

DB_URL = os.environ.get(
    "FACTURA_DB_URL", "postgresql://factura_app@127.0.0.1:5432/factura")
REDIS_URL = os.environ.get("FACTURA_REDIS_URL", "redis://127.0.0.1:6379/0")
QUEUE = os.environ.get("FACTURA_QUEUE", "factura:jobs")
FAILED = QUEUE + ":failed"
EXPORT_DIR = Path(os.environ.get("FACTURA_EXPORT_DIR", "/srv/factura/exports"))
HEARTBEAT_KEY = "factura:worker:heartbeat"

logging.basicConfig(
    level=os.environ.get("FACTURA_LOG_LEVEL", "INFO"),
    format="%(asctime)s factura-worker %(levelname)s %(message)s")
log = logging.getLogger("factura-worker")

STOP = False


def ask_stop(signum, _frame):
    global STOP
    log.info("signal %s recu, arret apres le job en cours", signum)
    STOP = True


def pdf_escape(text):
    text = text.encode("latin-1", "replace").decode("latin-1")
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def make_pdf(lines):
    """Fabrique un PDF 1.4 minimal mais valide (une page, Helvetica)."""
    body = "BT /F1 12 Tf 50 780 Td 16 TL " + " ".join(
        f"({pdf_escape(l)}) Tj T*" for l in lines) + " ET"
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
        "/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(body)} >>\nstream\n{body}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = "%PDF-1.4\n"
    offsets = []
    for i, obj in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{obj}\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n"
    out += "".join(f"{o:010d} 00000 n \n" for o in offsets)
    out += (f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref}\n%%EOF\n")
    return out.encode("latin-1")


def export_invoice(conn, inv_id):
    inv = conn.execute("SELECT * FROM invoices WHERE id = %s",
                       (inv_id,)).fetchone()
    if inv is None:
        raise LookupError(f"facture id={inv_id} inconnue")
    amount = f"{inv['amount_cents'] / 100:.2f} {inv['currency']}"
    lines = [
        "FACTURA - Facture " + inv["number"],
        "Client : " + inv["customer"],
        "Montant : " + amount,
        "Emise le : " + inv["created_at"].strftime("%Y-%m-%d %H:%M"),
        "Document genere automatiquement - lab Factura",
    ]
    target = EXPORT_DIR / f"{inv['number']}.pdf"
    tmp = target.with_suffix(".pdf.tmp")
    tmp.write_bytes(make_pdf(lines))
    os.chmod(tmp, 0o640)
    tmp.replace(target)          # renommage atomique
    conn.execute(
        "UPDATE invoices SET status = 'exported', pdf_path = %s, "
        "exported_at = %s WHERE id = %s",
        (str(target), datetime.now(timezone.utc), inv_id))
    return target


def main():
    signal.signal(signal.SIGTERM, ask_stop)
    signal.signal(signal.SIGINT, ask_stop)
    log.info("demarrage, file=%s, exports=%s", QUEUE, EXPORT_DIR)
    r = redis.Redis.from_url(REDIS_URL, socket_timeout=10,
                             socket_connect_timeout=3, decode_responses=True)
    conn = None
    while not STOP:
        item = None
        try:
            r.set(HEARTBEAT_KEY, time.time(), ex=30)
            if conn is None or conn.closed:
                conn = psycopg.connect(DB_URL, connect_timeout=3,
                                       autocommit=True, row_factory=dict_row)
            item = r.brpop(QUEUE, timeout=5)
            if item is None:
                continue
            job = json.loads(item[1])
            inv_id = int(job["invoice_id"])
            t0 = time.monotonic()
            try:
                target = export_invoice(conn, inv_id)
                log.info("facture id=%s exportee vers %s en %.0f ms",
                         inv_id, target, (time.monotonic() - t0) * 1000)
            except (OSError, LookupError) as exc:
                log.error("export id=%s impossible : %s", inv_id, exc)
                conn.execute("UPDATE invoices SET status = 'error' "
                             "WHERE id = %s", (inv_id,))
                r.lpush(FAILED, item[1])
        except redis.RedisError as exc:
            log.error("redis indisponible : %s (nouvel essai dans 5 s)", exc)
            time.sleep(5)
        except psycopg.Error as exc:
            log.error("postgresql indisponible : %s (nouvel essai dans 5 s)",
                      exc)
            conn = None
            if item is not None:      # le job repart en file, rien n'est perdu
                try:
                    r.rpush(QUEUE, item[1])
                except redis.RedisError:
                    pass
            time.sleep(5)
    log.info("arret propre")
    return 0


if __name__ == "__main__":
    sys.exit(main())
