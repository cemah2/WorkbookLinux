"""Tests de logstats.py."""

import io

import pytest

import logstats

LIGNE = (
    '198.51.100.12 - - [18/Sep/2026:14:02:11 +0200] "GET /api/v1/x HTTP/1.1"'
    ' {code} 512 "-" "curl/8.5.0" {duree}\n'
)


def flux(*couples):
    return io.StringIO(
        "".join(LIGNE.format(code=c, duree=d) for c, d in couples)
    )


def test_percentile_nearest_rank():
    assert logstats.percentile([0.1, 0.2, 0.3, 0.4], 50) == 0.2
    assert logstats.percentile([0.1, 0.2, 0.3, 0.4], 95) == 0.4
    assert logstats.percentile([], 95) == 0.0


def test_analyser_compte_et_trie():
    st = logstats.analyser(
        flux((200, "0.010"), (500, "1.500"), (200, "0.020"))
    )
    assert st.lignes == 3 and st.rejetees == 0
    assert st.codes == {"200": 2, "500": 1}
    assert st.durees == [0.010, 0.020, 1.500]
    assert st.urls_5xx == {"/api/v1/x": 1}


def test_analyser_rejette_sans_planter():
    st = logstats.analyser(
        io.StringIO("n'importe quoi\n" + LIGNE.format(code=200, duree="0.1"))
    )
    assert (st.lignes, st.rejetees) == (1, 1)


def test_ouvrir_gz(tmp_path):
    import gzip

    p = tmp_path / "a.log.gz"
    with gzip.open(p, "wt") as f:
        f.write(LIGNE.format(code=200, duree="0.3"))
    with logstats.ouvrir(str(p)) as f:
        assert logstats.analyser(f).lignes == 1


@pytest.mark.parametrize("chemin, code", [("/nexiste/pas", 1)])
def test_main_erreurs(chemin, code):
    assert logstats.main([chemin]) == code


def test_main_fichier_vide(tmp_path):
    p = tmp_path / "vide.log"
    p.write_text("")
    assert logstats.main([str(p)]) == 3
