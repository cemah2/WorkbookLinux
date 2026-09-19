#!/usr/bin/env python3
"""logstats.py — statistiques d'un access.log nginx (combined + temps).

Lit le journal ligne par ligne (fichier, .gz ou stdin), sans le charger en
mémoire, et produit : top des IP, répartition des codes HTTP, latences
(moyenne, p50, p95, p99, max) et top des URL en erreur 5xx.

Usage : logstats.py [--top N] [--json] [--since ISO] FICHIER|-
Codes de sortie : 0 ok, 1 fichier illisible, 2 usage, 3 aucune ligne valide.
"""

from __future__ import annotations

import argparse
import gzip
import json
import logging
import math
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import IO

log = logging.getLogger("logstats")

# combined + " $request_time" : on ne capture que ce qu'on exploite.
LIGNE = re.compile(
    r"^(?P<ip>\S+) \S+ \S+ \[(?P<date>[^\]]+)\] "
    r'"(?P<methode>[A-Z]+) (?P<url>\S+) [^"]*" '
    r'(?P<code>\d{3}) (?P<octets>\d+|-) "[^"]*" "[^"]*" '
    r"(?P<duree>\d+\.\d+)$"
)
FORMAT_DATE = "%d/%b/%Y:%H:%M:%S %z"


@dataclass
class Stats:
    """Accumulateur : on ne garde que les compteurs et la liste des durées."""

    lignes: int = 0
    rejetees: int = 0
    ips: Counter = field(default_factory=Counter)
    codes: Counter = field(default_factory=Counter)
    urls_5xx: Counter = field(default_factory=Counter)
    durees: list[float] = field(default_factory=list)

    def ajouter(self, m: re.Match) -> None:
        self.lignes += 1
        self.ips[m["ip"]] += 1
        code = m["code"]
        self.codes[code] += 1
        if code.startswith("5"):
            self.urls_5xx[m["url"]] += 1
        self.durees.append(float(m["duree"]))


def ouvrir(chemin: str) -> IO[str]:
    """Rend un flux texte : stdin pour '-', gzip transparent pour '.gz'."""
    if chemin == "-":
        return sys.stdin
    p = Path(chemin)
    if p.suffix == ".gz":
        return gzip.open(p, "rt", encoding="utf-8", errors="replace")
    return p.open(encoding="utf-8", errors="replace")


def analyser(flux: IO[str], depuis: datetime | None = None) -> Stats:
    """Consomme le flux ligne à ligne : un log de 10 Go tient en RAM."""
    st = Stats()
    for ligne in flux:
        m = LIGNE.match(ligne.rstrip("\n"))
        if m is None:
            st.rejetees += 1
            log.debug("ligne rejetée : %s", ligne[:80])
            continue
        if depuis is not None:
            quand = datetime.strptime(m["date"], FORMAT_DATE)
            if quand < depuis:
                continue
        st.ajouter(m)
    st.durees.sort()
    return st


def percentile(valeurs: list[float], p: float) -> float:
    """Rang le plus proche (nearest-rank) sur une liste TRIÉE."""
    if not valeurs:
        return 0.0
    k = max(1, math.ceil(p / 100 * len(valeurs)))
    return valeurs[k - 1]


def resume(st: Stats, top: int) -> dict:
    d = st.durees
    return {
        "lignes": st.lignes,
        "rejetees": st.rejetees,
        "top_ip": st.ips.most_common(top),
        "codes": dict(sorted(st.codes.items())),
        "latence": {
            "moyenne": round(sum(d) / len(d), 3) if d else 0.0,
            "p50": percentile(d, 50),
            "p95": percentile(d, 95),
            "p99": percentile(d, 99),
            "max": d[-1] if d else 0.0,
        },
        "top_5xx": st.urls_5xx.most_common(top),
    }


def afficher(r: dict) -> None:
    print(f"lignes : {r['lignes']}  (rejetées : {r['rejetees']})")
    print("\n== Top IP ==")
    for ip, n in r["top_ip"]:
        print(f"{n:>7}  {ip}")
    print("\n== Codes HTTP ==")
    for code, n in r["codes"].items():
        pct = 100 * n / r["lignes"]
        print(f"{code}  {n:>7}  {pct:5.1f} %")
    lat = r["latence"]
    print("\n== Latence (s) ==")
    print(
        f"moyenne {lat['moyenne']:.3f}  p50 {lat['p50']:.3f}  "
        f"p95 {lat['p95']:.3f}  p99 {lat['p99']:.3f}  max {lat['max']:.3f}"
    )
    if r["top_5xx"]:
        print("\n== URL en 5xx ==")
        for url, n in r["top_5xx"]:
            print(f"{n:>7}  {url}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Statistiques d'un access.log nginx.",
        epilog="Codes de sortie : 0 ok, 1 fichier illisible, 3 aucune ligne.",
    )
    p.add_argument("fichier", help="access.log, .gz, ou - pour stdin")
    p.add_argument("--top", type=int, default=10, help="taille des tops")
    p.add_argument("--json", action="store_true", help="sortie JSON")
    p.add_argument(
        "--since", metavar="ISO", help="ignorer avant cette date (ISO 8601)"
    )
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    depuis = None
    if args.since:
        depuis = datetime.fromisoformat(args.since)
        if depuis.tzinfo is None:
            depuis = depuis.astimezone()  # heure locale du serveur
    try:
        with ouvrir(args.fichier) as flux:
            st = analyser(flux, depuis)
    except OSError as exc:
        log.error("impossible de lire %s : %s", args.fichier, exc)
        return 1
    if st.lignes == 0:
        log.error("aucune ligne valide dans %s", args.fichier)
        return 3
    r = resume(st, args.top)
    if args.json:
        json.dump(r, sys.stdout, indent=2)
        print()
    else:
        afficher(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
