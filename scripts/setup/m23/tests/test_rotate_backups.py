"""Tests de rotate_backups.py — lancer avec : pytest -q tests/"""

from datetime import date, timedelta
from pathlib import Path

import pytest

import rotate_backups as rb


def jours(n: int, fin: date = date(2026, 9, 18)) -> list[date]:
    """n dates consécutives se terminant le 18/09/2026."""
    return [fin - timedelta(days=i) for i in range(n)][::-1]


def creer(rep: Path, dates: list[date], prefixe: str = "factura") -> None:
    for d in dates:
        (rep / f"{prefixe}-{d.isoformat()}.tar.gz").write_bytes(b"x")


def test_selection_garde_7_quotidiennes():
    garder = rb.selection(jours(30), rb.Politique(7, 0, 0))
    assert sorted(garder) == jours(7)
    assert set(garder.values()) == {"quotidienne"}


def test_selection_hebdo_prend_la_derniere_de_chaque_semaine():
    garder = rb.selection(jours(60), rb.Politique(0, 4, 0))
    assert len(garder) == 4
    # le 18/09/2026 est un vendredi : dernière archive de sa semaine ISO
    assert date(2026, 9, 18) in garder
    # les trois autres sont des dimanches (fin de semaine ISO)
    dimanches = [d for d in garder if d != date(2026, 9, 18)]
    assert all(d.isoweekday() == 7 for d in dimanches)


def test_selection_mensuelle_prend_la_premiere_du_mois():
    garder = rb.selection(jours(200), rb.Politique(0, 0, 6))
    assert len(garder) == 6
    assert date(2026, 9, 1) in garder and date(2026, 4, 1) in garder


def test_selection_union_sur_120_jours():
    garder = rb.selection(jours(120), rb.Politique())
    # 7 + 4 + 6 moins les recouvrements (le 18/09 est à la fois fils et père)
    assert 12 <= len(garder) <= 17
    assert date(2026, 9, 18) in garder


def test_inventorier_ignore_les_intrus(tmp_path):
    creer(tmp_path, jours(3))
    (tmp_path / "export final.tar.gz").write_bytes(b"x")
    (tmp_path / "factura-2026-13-45.tar.gz").write_bytes(b"x")  # date fausse
    (tmp_path / "autre-2026-09-01.tar.gz").write_bytes(b"x")
    noms = [a.chemin.name for a in rb.inventorier(tmp_path, "factura")]
    assert noms == [f"factura-{d.isoformat()}.tar.gz" for d in jours(3)]


def test_dry_run_ne_supprime_rien(tmp_path):
    creer(tmp_path, jours(40))
    bilan = rb.appliquer(
        rb.inventorier(tmp_path, "factura"), rb.Politique(), dry_run=True
    )
    assert len(bilan["supprimees"]) > 0
    assert len(list(tmp_path.iterdir())) == 40


def test_appliquer_supprime_et_garde_l_intrus(tmp_path):
    creer(tmp_path, jours(40))
    intrus = tmp_path / "export final.tar.gz"
    intrus.write_bytes(b"x")
    bilan = rb.appliquer(
        rb.inventorier(tmp_path, "factura"), rb.Politique(), dry_run=False
    )
    restants = {p.name for p in tmp_path.iterdir()}
    assert intrus.name in restants
    assert restants - {intrus.name} == set(bilan["gardees"])
    assert not (restants & set(bilan["supprimees"]))


def test_main_repertoire_absent(tmp_path, caplog):
    # le message part par logging, pas par print : caplog, pas capsys
    assert rb.main([str(tmp_path / "nope")]) == 1
    assert "pas un répertoire" in caplog.text


@pytest.mark.parametrize("args", [["--daily", "-1"], ["--weekly", "x"]])
def test_main_usage_incorrect(tmp_path, args):
    with pytest.raises(SystemExit) as exc:
        rb.main([str(tmp_path), *args])
    assert exc.value.code == 2
