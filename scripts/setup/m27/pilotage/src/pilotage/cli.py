"""Point d'entrée : rapport Markdown sur stdout, journal sur stderr,
code 0 (rien), 1 (avertissement), 2 (critique)."""

from __future__ import annotations

import argparse
import logging
import os
import socket
import sys
from dataclasses import dataclass, field
from datetime import datetime

from pilotage import __version__, collecte

log = logging.getLogger("pilotage")


@dataclass
class Seuils:
    ratio: float = 1.5
    wa: float = 20
    mem_pct: float = 15
    fs: float = 90
    fs_crit: float = 95
    inodes: float = 90
    st: float = 5


@dataclass
class Verdict:
    avertissements: list[str] = field(default_factory=list)
    critiques: list[str] = field(default_factory=list)

    def avert(self, msg: str) -> None:
        self.avertissements.append(msg)

    def crit(self, msg: str) -> None:
        self.critiques.append(msg)

    @property
    def code(self) -> int:
        return 2 if self.critiques else 1 if self.avertissements else 0


def evaluer(
    s: Seuils,
    charge: tuple[float, float, float],
    coeurs: int,
    cpu: collecte.Cpu,
    mem: collecte.Memoire,
    swap: bool,
    fs: list[collecte.SystemeFichiers],
    echecs: list[str],
) -> Verdict:
    """Toute la logique de décision, pure : c'est elle qu'on teste."""
    v = Verdict()
    ratio = charge[0] / coeurs
    if ratio > s.ratio:
        v.avert(f"charge/cœur = {ratio:.2f}")
    if cpu.wa > s.wa:
        v.avert(f"%wa = {cpu.wa}")
    if cpu.st > s.st:
        v.avert(f"%st = {cpu.st} (hyperviseur)")
    if mem.pct_dispo < s.mem_pct:
        v.avert(f"mémoire disponible {mem.pct_dispo:.0f} %")
    if swap:
        v.crit("swap actif")
    for f in fs:
        if f.pct_espace >= s.fs_crit and f.point in ("/", "/var"):
            v.crit(f"{f.point} à {f.pct_espace} % d'espace")
        elif f.pct_espace >= s.fs:
            v.avert(f"{f.point} à {f.pct_espace} % d'espace")
        if f.pct_inodes >= s.inodes:
            v.crit(f"{f.point} à {f.pct_inodes} % d'inodes")
    if echecs:
        v.crit(
            f"{len(echecs)} unité(s) systemd en échec : " + ", ".join(echecs)
        )
    return v


def rapport(delai: float) -> tuple[str, int]:
    s = Seuils()
    out: list[str] = []
    p = out.append
    coeurs = os.cpu_count() or 1
    p(
        f"# État de santé — {socket.getfqdn()} — "
        f"{datetime.now().astimezone().isoformat(timespec='seconds')}\n"
    )
    p(f"* cœurs : {coeurs}   pilotage {__version__}")
    with open("/proc/uptime", encoding="utf-8") as fu:
        secondes = float(fu.read().split()[0])
    p(f"* uptime : {secondes / 3600:.1f} h\n")

    ch = collecte.charge()
    p("## Charge\n")
    p(f"{ch[0]} {ch[1]} {ch[2]} — ratio/cœur {ch[0] / coeurs:.2f}\n")

    cpu = collecte.cpu(delai=delai)
    p("## CPU\n")
    p(f"us={cpu.us} sy={cpu.sy} wa={cpu.wa} st={cpu.st}\n")

    mem = collecte.memoire()
    swap = collecte.swap_actif()
    p("## Mémoire\n")
    p(
        f"total {mem.total_mo} Mo, disponible {mem.dispo_mo} Mo "
        f"({mem.pct_dispo:.0f} %), swap {'ACTIF' if swap else 'inactif'}\n"
    )

    fs = collecte.systemes_fichiers()
    p("## Systèmes de fichiers\n")
    for f in fs:
        p(f"* {f.point} : {f.pct_espace} % espace, {f.pct_inodes} % inodes")
    p("")

    par_cpu, par_rss = collecte.top_processus()
    p("## Processus\n")
    p("```\n" + "\n".join(par_cpu) + "\n```\n")
    p("```\n" + "\n".join(par_rss) + "\n```\n")

    p("## /var/log\n")
    for octets, chemin in collecte.gros_fichiers():
        p(f"* {octets // 2**20} Mo  {chemin}")
    p("")

    taille, nb_err, dernieres = collecte.journal()
    p("## Journal\n")
    p(f"* {taille}")
    p(f"* entrées err depuis le boot : {nb_err}\n")
    p("```\n" + "\n".join(dernieres) + "\n```\n")

    echecs = collecte.unites_en_echec()
    p("## Unités en échec\n")
    p("\n".join(f"* {u}" for u in echecs) or "aucune")
    p("")

    v = evaluer(s, ch, coeurs, cpu, mem, swap, fs, echecs)
    p("## VERDICT\n")
    if not v.avertissements and not v.critiques:
        p("Aucune anomalie.")
    for c in v.critiques:
        p(f"* CRITIQUE      {c}")
    for a in v.avertissements:
        p(f"* AVERTISSEMENT {a}")
    return "\n".join(out) + "\n", v.code


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="sante-serveur", description=__doc__.split("\n")[0]
    )
    ap.add_argument(
        "--delai",
        type=float,
        default=2.0,
        help="secondes entre les deux lectures CPU",
    )
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--version", action="version", version=__version__)
    args = ap.parse_args(argv)
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(message)s",
        stream=sys.stderr,
    )
    texte, code = rapport(args.delai)
    sys.stdout.write(texte)
    return code


if __name__ == "__main__":
    sys.exit(main())
