"""Lecture des sources système. Chaque fonction accepte le TEXTE brut en
paramètre optionnel pour être testable sans /proc ni commandes."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger("pilotage")

FS_IGNORES = {
    "tmpfs",
    "devtmpfs",
    "squashfs",
    "overlay",
    "proc",
    "sysfs",
    "cgroup2",
    "efivarfs",
    "fuse.lxcfs",
}


@dataclass(frozen=True)
class Cpu:
    us: float
    sy: float
    wa: float
    st: float


@dataclass(frozen=True)
class Memoire:
    total_mo: int
    dispo_mo: int

    @property
    def pct_dispo(self) -> float:
        return 100 * self.dispo_mo / self.total_mo if self.total_mo else 0.0


@dataclass(frozen=True)
class SystemeFichiers:
    point: str
    pct_espace: float
    pct_inodes: float


def lire(chemin: str) -> str:
    return Path(chemin).read_text(encoding="utf-8")


def charge(texte: str | None = None) -> tuple[float, float, float]:
    l1, l5, l15, *_ = (texte or lire("/proc/loadavg")).split()
    return float(l1), float(l5), float(l15)


def _cpu_brut(texte: str) -> tuple[int, int, int, int, int]:
    """Rend (user+nice, system, iowait, steal, total) en jiffies."""
    for ligne in texte.splitlines():
        if ligne.startswith("cpu "):
            v = [int(x) for x in ligne.split()[1:]]
            v += [0] * (8 - len(v))
            return v[0] + v[1], v[2], v[4], v[7], sum(v[:8])
    raise ValueError("ligne 'cpu ' absente de /proc/stat")


def cpu(
    avant: str | None = None, apres: str | None = None, delai: float = 2.0
) -> Cpu:
    """Delta entre deux lectures : /proc/stat cumule depuis le boot."""
    if avant is None or apres is None:
        avant = lire("/proc/stat")
        time.sleep(delai)
        apres = lire("/proc/stat")
    u1, s1, w1, t1, tot1 = _cpu_brut(avant)
    u2, s2, w2, t2, tot2 = _cpu_brut(apres)
    d = (tot2 - tot1) or 1
    pct = lambda a, b: round(100 * (b - a) / d, 1)  # noqa: E731
    return Cpu(pct(u1, u2), pct(s1, s2), pct(w1, w2), pct(t1, t2))


def memoire(texte: str | None = None) -> Memoire:
    val: dict[str, int] = {}
    for ligne in (texte or lire("/proc/meminfo")).splitlines():
        cle, _, reste = ligne.partition(":")
        val[cle] = int(reste.split()[0])  # en ko
    return Memoire(val["MemTotal"] // 1024, val["MemAvailable"] // 1024)


def swap_actif(texte: str | None = None) -> bool:
    for ligne in (texte or lire("/proc/swaps")).splitlines()[1:]:
        champs = ligne.split()
        if len(champs) >= 4 and int(champs[3]) > 0:
            return True
    return False


def systemes_fichiers(
    mounts: str | None = None, statvfs=os.statvfs
) -> list[SystemeFichiers]:
    """Un enregistrement par montage rw réel, espace ET inodes."""
    resultats = []
    for ligne in (mounts or lire("/proc/mounts")).splitlines():
        _, point, fstype, options, *_ = ligne.split()
        if fstype in FS_IGNORES or "ro" in options.split(","):
            continue
        try:
            st = statvfs(point)
        except OSError as exc:
            log.warning("statvfs %s : %s", point, exc)
            continue
        utilise = st.f_blocks - st.f_bfree
        if utilise + st.f_bavail == 0:
            continue
        # comme df : utilisé / (utilisé + disponible pour un non-root)
        pct_e = 100 * utilise / (utilise + st.f_bavail)
        pct_i = 100 * (1 - st.f_favail / st.f_files) if st.f_files else 0.0
        resultats.append(
            SystemeFichiers(point, round(pct_e, 1), round(pct_i, 1))
        )
    return resultats


def commande(argv: list[str], timeout: float = 10) -> str | None:
    """stdout de la commande, ou None si absente/en échec (dégradation)."""
    if shutil.which(argv[0]) is None:
        log.warning("%s absent : section dégradée", argv[0])
        return None
    try:
        p = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, check=True
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        log.warning("%s : %s", " ".join(argv), exc)
        return None
    return p.stdout


def top_processus(n: int = 5) -> tuple[list[str], list[str]]:
    par_cpu = commande(["ps", "-eo", "pid,pcpu,rss,comm", "--sort=-pcpu"])
    par_rss = commande(["ps", "-eo", "pid,pcpu,rss,comm", "--sort=-rss"])
    couper = lambda s: s.splitlines()[1 : n + 1] if s else []  # noqa: E731
    return couper(par_cpu), couper(par_rss)


def gros_fichiers(
    racine: str = "/var/log", n: int = 5
) -> list[tuple[int, str]]:
    tailles = []
    for rep, _, fichiers in os.walk(racine):
        for f in fichiers:
            p = os.path.join(rep, f)
            try:
                tailles.append((os.lstat(p).st_size, p))
            except OSError:
                continue
    return sorted(tailles, reverse=True)[:n]


def unites_en_echec(texte: str | None = None) -> list[str]:
    if texte is None:
        texte = commande(
            [
                "systemctl",
                "list-units",
                "--state=failed",
                "--no-legend",
                "--plain",
                "--no-pager",
            ]
        )
    return [x.split()[0] for x in (texte or "").splitlines() if x.strip()]


def journal() -> tuple[str, int, list[str]]:
    taille = commande(["journalctl", "--disk-usage"]) or "indisponible"
    err = (
        commande(
            [
                "journalctl",
                "-b",
                "-p",
                "err",
                "-q",
                "--no-pager",
                "-o",
                "short-iso",
            ]
        )
        or ""
    )
    lignes = err.splitlines()
    return taille.strip(), len(lignes), lignes[-10:]
