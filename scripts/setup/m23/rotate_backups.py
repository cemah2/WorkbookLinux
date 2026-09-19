#!/usr/bin/env python3
"""rotate_backups.py — rétention GFS (grand-père, père, fils) d'archives.

Les archives se nomment <prefixe>-AAAA-MM-JJ.<ext>. La date est lue dans le
NOM, jamais dans le mtime (une copie ou une restauration le modifie).

Politique par défaut : garder les 7 dernières quotidiennes, la dernière
archive de chacune des 4 dernières semaines ISO, la première archive de
chacun des 6 derniers mois. Tout le reste est supprimé — sauf en --dry-run.

Codes de sortie : 0 ok, 1 répertoire illisible, 2 usage.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

log = logging.getLogger("rotate")


@dataclass(frozen=True)
class Politique:
    quotidiennes: int = 7
    hebdomadaires: int = 4
    mensuelles: int = 6


@dataclass(frozen=True)
class Archive:
    chemin: Path
    quand: date


def motif(prefixe: str) -> re.Pattern[str]:
    return re.compile(
        rf"^{re.escape(prefixe)}-(\d{{4}})-(\d{{2}})-(\d{{2}})\.[\w.]+$"
    )


def inventorier(rep: Path, prefixe: str) -> list[Archive]:
    """Ne retient que les fichiers au bon format ; les autres sont ignorés."""
    rx = motif(prefixe)
    archives = []
    for p in rep.iterdir():
        m = rx.match(p.name)
        if not m or not p.is_file():
            log.debug("ignoré : %s", p.name)
            continue
        try:
            quand = date(int(m[1]), int(m[2]), int(m[3]))
        except ValueError:
            log.warning("date invalide dans le nom : %s", p.name)
            continue
        archives.append(Archive(p, quand))
    return sorted(archives, key=lambda a: a.quand)


def selection(dates: list[date], pol: Politique) -> dict[date, str]:
    """Rend {date: raison} pour les dates à conserver. Fonction pure."""
    dates = sorted(set(dates))
    garder: dict[date, str] = {}

    def derniers(n: int, seq: list) -> list:
        # PIÈGE : seq[-0:] rend TOUTE la liste, pas une liste vide.
        return seq[-n:] if n > 0 else []

    # fils : les N dates les plus récentes
    for d in derniers(pol.quotidiennes, dates):
        garder.setdefault(d, "quotidienne")

    # pères : la DERNIÈRE archive de chaque semaine ISO, N semaines
    par_semaine: dict[tuple[int, int], date] = {}
    for d in dates:
        an, sem, _ = d.isocalendar()
        par_semaine[(an, sem)] = d  # la liste est triée : la dernière gagne
    for _, d in derniers(pol.hebdomadaires, sorted(par_semaine.items())):
        garder.setdefault(d, "hebdomadaire")

    # grands-pères : la PREMIÈRE archive de chaque mois, N mois
    par_mois: dict[tuple[int, int], date] = {}
    for d in dates:
        par_mois.setdefault((d.year, d.month), d)  # la première reste
    for _, d in derniers(pol.mensuelles, sorted(par_mois.items())):
        garder.setdefault(d, "mensuelle")
    return garder


def appliquer(
    archives: list[Archive], pol: Politique, dry_run: bool
) -> dict[str, list[str]]:
    garder = selection([a.quand for a in archives], pol)
    bilan: dict[str, list[str]] = {"gardees": [], "supprimees": []}
    for a in archives:
        if a.quand in garder:
            log.debug("garde   %s (%s)", a.chemin.name, garder[a.quand])
            bilan["gardees"].append(a.chemin.name)
            continue
        bilan["supprimees"].append(a.chemin.name)
        if dry_run:
            log.info("[dry-run] supprimerait %s", a.chemin.name)
        else:
            log.info("supprime %s", a.chemin.name)
            a.chemin.unlink()
    return bilan


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("repertoire", type=Path)
    p.add_argument("--prefix", default="factura")
    p.add_argument("--daily", type=int, default=7)
    p.add_argument("--weekly", type=int, default=4)
    p.add_argument("--monthly", type=int, default=6)
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("--json", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    a = p.parse_args(argv)
    if min(a.daily, a.weekly, a.monthly) < 0:
        p.error("les rétentions sont des entiers positifs ou nuls")
    return a


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )
    if not args.repertoire.is_dir():
        log.error("%s n'est pas un répertoire", args.repertoire)
        return 1
    pol = Politique(args.daily, args.weekly, args.monthly)
    try:
        archives = inventorier(args.repertoire, args.prefix)
        bilan = appliquer(archives, pol, args.dry_run)
    except OSError as exc:
        log.error("%s", exc)
        return 1
    if args.json:
        json.dump(bilan | {"dry_run": args.dry_run}, sys.stdout, indent=2)
        print()
    else:
        print(
            f"{len(bilan['gardees'])} gardée(s), "
            f"{len(bilan['supprimees'])} supprimée(s)"
            f"{' (simulation)' if args.dry_run else ''}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
