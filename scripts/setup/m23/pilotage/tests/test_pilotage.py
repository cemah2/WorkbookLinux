"""Tests de pilotage : aucune lecture réelle de /proc, aucune commande."""

import subprocess
from collections import namedtuple

import pytest

from pilotage import cli, collecte

STAT1 = "cpu  100 0 50 800 20 0 0 5\ncpu0 1 2 3 4 5 6 7 8\n"
STAT2 = "cpu  200 0 100 900 60 0 0 15\ncpu0 1 2 3 4 5 6 7 8\n"
MEMINFO = (
    "MemTotal:       2048000 kB\nMemFree:  10 kB\nMemAvailable:    204800 kB\n"
)
MOUNTS = (
    "/dev/sda1 / ext4 rw,relatime 0 0\n"
    "tmpfs /run tmpfs rw,nosuid 0 0\n"
    "/dev/sdb1 /srv xfs rw 0 0\n"
    "/dev/sr0 /media iso9660 ro 0 0\n"
)
Vfs = namedtuple("Vfs", "f_blocks f_bfree f_bavail f_files f_favail")


def test_cpu_delta():
    c = collecte.cpu(STAT1, STAT2)
    # delta total = 300 ; user 100, system 50, iowait 40, steal 10
    assert (c.us, c.sy, c.wa, c.st) == (33.3, 16.7, 13.3, 3.3)


def test_cpu_sans_ligne_cpu():
    with pytest.raises(ValueError):
        collecte.cpu("rien\n", "rien\n")


def test_memoire_et_pourcentage():
    m = collecte.memoire(MEMINFO)
    assert (m.total_mo, m.dispo_mo) == (2000, 200)
    assert m.pct_dispo == pytest.approx(10.0)


def test_systemes_fichiers_filtre_et_inodes():
    def faux_statvfs(point):
        # f_blocks, f_bfree, f_bavail, f_files, f_favail
        return {
            "/": Vfs(100, 4, 4, 1000, 950),
            "/srv": Vfs(100, 50, 50, 1000, 50),
        }[point]

    fs = collecte.systemes_fichiers(MOUNTS, statvfs=faux_statvfs)
    assert [f.point for f in fs] == ["/", "/srv"]  # ni tmpfs ni ro
    assert fs[0].pct_espace == 96.0 and fs[0].pct_inodes == 5.0
    assert fs[1].pct_inodes == 95.0


def test_commande_absente(monkeypatch):
    monkeypatch.setattr(collecte.shutil, "which", lambda x: None)
    assert collecte.commande(["iostat", "-x"]) is None


def test_commande_echec_simule(monkeypatch):
    def faux_run(argv, **kw):
        raise subprocess.CalledProcessError(1, argv)

    monkeypatch.setattr(collecte.shutil, "which", lambda x: "/bin/x")
    monkeypatch.setattr(subprocess, "run", faux_run)
    assert collecte.commande(["systemctl", "list-units"]) is None


def test_unites_en_echec_parse():
    texte = (
        "nginx.service loaded failed failed A\n"
        "foo.timer loaded failed failed B\n"
    )
    assert collecte.unites_en_echec(texte) == ["nginx.service", "foo.timer"]
    assert collecte.unites_en_echec("") == []


def test_evaluer_codes():
    s = cli.Seuils()
    cpu = collecte.Cpu(10, 5, 1, 0)
    mem = collecte.Memoire(2000, 1000)
    sain = cli.evaluer(s, (0.5, 0.5, 0.5), 2, cpu, mem, False, [], [])
    assert sain.code == 0
    lent = cli.evaluer(s, (4.0, 1, 1), 2, cpu, mem, False, [], [])
    assert lent.code == 1 and "charge" in lent.avertissements[0]
    fs = [collecte.SystemeFichiers("/var", 40.0, 99.0)]
    plein = cli.evaluer(s, (0.5, 1, 1), 2, cpu, mem, False, fs, [])
    assert plein.code == 2 and "inodes" in plein.critiques[0]
    casse = cli.evaluer(s, (0.5, 1, 1), 2, cpu, mem, True, [], ["x.service"])
    assert casse.code == 2 and len(casse.critiques) == 2
