#!/usr/bin/env python3
"""factura_exporter.py — exporter Prometheus « métier » sans dépendance.

Expose sur /metrics le nombre et le montant des factures par statut, lus à
CHAQUE scrape (modèle pull : la valeur est fraîche, jamais mise en cache)
depuis un CSV ou, avec [source].dsn, depuis PostgreSQL (psycopg 3).

Configuration TOML (défaut /etc/factura/exporter.toml) :
    [http]
    port = 9105
    [source]
    csv = "/srv/factura/data/factures.csv"    # ou dsn = "host=... dbname=..."

Le format d'exposition texte est écrit à la main : c'est volontaire, pour
voir ce que prometheus_client produit. En production, prends la bibliothèque.
"""

from __future__ import annotations

import argparse
import csv
import logging
import signal
import sys
import time
import tomllib
from collections import Counter, defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

log = logging.getLogger("exporter")
STATUTS = ("brouillon", "emise", "payee", "annulee")


# --- collecte ----------------------------------------------------------------
def lire_csv(chemin: Path) -> list[dict[str, str]]:
    with chemin.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter=";"))


def lire_postgres(dsn: str) -> list[dict[str, str]]:
    import psycopg  # pip install "psycopg[binary]"

    with psycopg.connect(dsn, connect_timeout=3) as conn:
        rows = conn.execute("SELECT statut, montant FROM factures").fetchall()
    return [{"statut": s, "montant": str(m)} for s, m in rows]


def agreger(lignes: list[dict[str, str]]) -> dict[str, dict[str, float]]:
    nb: Counter[str] = Counter()
    montant: defaultdict[str, float] = defaultdict(float)
    for ligne in lignes:
        statut = ligne.get("statut", "inconnu")
        nb[statut] += 1
        try:
            montant[statut] += float(ligne.get("montant", "0"))
        except ValueError:
            log.warning("montant illisible : %r", ligne)
    return {"nb": dict(nb), "montant": dict(montant)}


def exposition(
    agg: dict[str, dict[str, float]], duree: float, ok: bool
) -> str:
    """Format texte Prometheus : # HELP, # TYPE, puis une ligne par série."""
    lignes = [
        "# HELP factura_factures_total Nombre de factures par statut.",
        "# TYPE factura_factures_total gauge",
    ]
    for statut in sorted(set(STATUTS) | set(agg["nb"])):
        lignes.append(
            f'factura_factures_total{{statut="{statut}"}} '
            f"{agg['nb'].get(statut, 0)}"
        )
    lignes += [
        "# HELP factura_montant_euros Montant cumulé par statut.",
        "# TYPE factura_montant_euros gauge",
    ]
    for statut, m in sorted(agg["montant"].items()):
        lignes.append(f'factura_montant_euros{{statut="{statut}"}} {m:.2f}')
    lignes += [
        "# HELP factura_collecte_duree_seconds Durée de la lecture.",
        "# TYPE factura_collecte_duree_seconds gauge",
        f"factura_collecte_duree_seconds {duree:.4f}",
        "# HELP factura_collecte_ok 1 si la source a répondu, 0 sinon.",
        "# TYPE factura_collecte_ok gauge",
        f"factura_collecte_ok {int(ok)}",
    ]
    return "\n".join(lignes) + "\n"


def collecter(conf: dict[str, Any]) -> str:
    debut = time.monotonic()
    ok = True
    try:
        src = conf["source"]
        lignes = (
            lire_postgres(src["dsn"])
            if src.get("dsn")
            else lire_csv(Path(src["csv"]))
        )
    except Exception as exc:  # noqa: BLE001 — l'exporter doit rester vivant
        log.error("collecte impossible : %s", exc)
        lignes, ok = [], False
    return exposition(agreger(lignes), time.monotonic() - debut, ok)


# --- serveur HTTP ------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    conf: dict[str, Any] = {}

    def do_GET(self) -> None:  # noqa: N802 — nom imposé par http.server
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        corps = collecter(self.conf).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def log_message(self, fmt: str, *args: Any) -> None:
        log.debug(fmt, *args)  # sinon http.server écrit sur stderr


def charger(chemin: Path) -> dict[str, Any]:
    with chemin.open("rb") as f:  # tomllib exige le mode binaire
        conf = tomllib.load(f)
    if "source" not in conf or not (
        conf["source"].get("csv") or conf["source"].get("dsn")
    ):
        raise ValueError("[source] doit définir csv ou dsn")
    return conf


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument(
        "-c", "--config", type=Path, default=Path("/etc/factura/exporter.toml")
    )
    p.add_argument(
        "--once",
        action="store_true",
        help="afficher les métriques et sortir (test)",
    )
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    try:
        conf = charger(args.config)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as exc:
        log.error("configuration : %s", exc)
        return 1
    if args.once:
        sys.stdout.write(collecter(conf))
        return 0
    port = int(conf.get("http", {}).get("port", 9105))
    Handler.conf = conf
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    def arreter(signum: int, frame: Any) -> None:
        log.info("signal %d reçu, arrêt", signum)
        raise SystemExit(0)  # SystemExit : le with/finally s'exécutent

    signal.signal(signal.SIGTERM, arreter)
    log.info("exporter à l'écoute sur :%d/metrics", port)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
