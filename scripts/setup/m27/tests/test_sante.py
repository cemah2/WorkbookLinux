"""Tests de sante.py : aucun réseau, tout est simulé avec monkeypatch."""

import socket
import subprocess
from collections import namedtuple

import sante

Usage = namedtuple("Usage", "total used free")


def test_tcp_ok(monkeypatch):
    class FauxSocket:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    monkeypatch.setattr(
        socket, "create_connection", lambda *a, **k: FauxSocket()
    )
    code, _ = sante.verif_tcp({"hote": "lab-web", "port": 22}, 1.0)
    assert code == sante.OK


def test_tcp_refuse(monkeypatch):
    def refuse(*a, **k):
        raise ConnectionRefusedError(111, "Connection refused")

    monkeypatch.setattr(socket, "create_connection", refuse)
    code, detail = sante.verif_tcp({"hote": "lab-web", "port": 22}, 1.0)
    assert code == sante.CRITICAL and "22" in detail


def test_disque_seuils(monkeypatch):
    monkeypatch.setattr(
        sante.shutil, "disk_usage", lambda p: Usage(100, 95, 5)
    )
    assert sante.verif_disque({"chemin": "/"}, 1.0)[0] == sante.CRITICAL
    monkeypatch.setattr(
        sante.shutil, "disk_usage", lambda p: Usage(100, 85, 15)
    )
    assert sante.verif_disque({"chemin": "/"}, 1.0)[0] == sante.WARNING
    monkeypatch.setattr(
        sante.shutil, "disk_usage", lambda p: Usage(100, 10, 90)
    )
    assert sante.verif_disque({"chemin": "/"}, 1.0)[0] == sante.OK


def test_commande_simulee(monkeypatch):
    appels = []

    def faux_run(argv, **kw):
        appels.append((argv, kw))
        return subprocess.CompletedProcess(argv, 3, "", "inactive\n")

    monkeypatch.setattr(subprocess, "run", faux_run)
    code, detail = sante.verif_commande(
        {"argv": ["systemctl", "is-active", "nginx"]}, 2.0
    )
    assert code == sante.CRITICAL and "inactive" in detail
    assert appels[0][0] == ["systemctl", "is-active", "nginx"]
    assert appels[0][1]["timeout"] == 2.0 and "shell" not in appels[0][1]


def test_commande_refuse_une_chaine():
    code, _ = sante.verif_commande({"argv": "rm -rf /"}, 1.0)
    assert code == sante.UNKNOWN


def test_executer_type_inconnu_et_cle_manquante():
    assert sante.executer({"nom": "x", "type": "zzz"}, 1).code == sante.UNKNOWN
    r = sante.executer({"nom": "x", "type": "tcp", "hote": "h"}, 1)
    assert r.code == sante.UNKNOWN and "port" in r.detail


def test_rapport_prend_le_pire():
    rs = [
        sante.Resultat("a", "tcp", sante.OK, ""),
        sante.Resultat("b", "tcp", sante.WARNING, ""),
    ]
    assert sante.rapport(rs)["statut"] == "WARNING"
    assert sante.rapport([])["code"] == sante.UNKNOWN


def test_ecrire_atomique(tmp_path):
    cible = tmp_path / "sante.json"
    sante.ecrire_atomique(cible, "{}\n")
    assert cible.read_text() == "{}\n"
    assert [p.name for p in tmp_path.iterdir()] == ["sante.json"]


def test_main_config_absente(tmp_path, capsys):
    assert sante.main(["-c", str(tmp_path / "nope.yaml")]) == sante.UNKNOWN
    assert '"UNKNOWN"' in capsys.readouterr().out
