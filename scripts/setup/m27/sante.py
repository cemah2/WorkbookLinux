#!/usr/bin/env python3
"""sante.py — santé multi-services : rapport JSON, code de sortie Nagios.

Types de vérification (fichier YAML, clé `verifications`) :
  tcp      hote, port                      le port accepte une connexion
  http     url, [attendu=200], [contient]  code HTTP attendu (+ texte)
  tls      hote, port, [jours_min=14]      certificat valide, non expirant
  disque   chemin, [pct_max=90]            usage du système de fichiers
  commande argv (liste), [timeout]         code de retour 0

Codes de sortie (convention Nagios) : 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN.
stdout : le rapport (JSON, ou texte avec --text). stderr : le journal.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

log = logging.getLogger("sante")

OK, WARNING, CRITICAL, UNKNOWN = 0, 1, 2, 3
LIBELLE = {
    OK: "OK",
    WARNING: "WARNING",
    CRITICAL: "CRITICAL",
    UNKNOWN: "UNKNOWN",
}


@dataclass
class Resultat:
    nom: str
    type: str
    code: int
    detail: str
    duree_ms: int = 0

    @property
    def statut(self) -> str:
        return LIBELLE[self.code]


# --- une fonction par type : (spec, timeout) -> (code, détail) -------------
def verif_tcp(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    hote, port = spec["hote"], int(spec["port"])
    try:
        with socket.create_connection((hote, port), timeout=timeout):
            return OK, f"{hote}:{port} accepte les connexions"
    except OSError as exc:  # refus, timeout, DNS : tous des OSError
        return CRITICAL, f"{hote}:{port} injoignable ({exc})"


def verif_http(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    url, attendu = spec["url"], int(spec.get("attendu", 200))
    req = urllib.request.Request(url, headers={"User-Agent": "sante.py"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as rep:
            code = rep.status
            corps = rep.read(65536).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:  # réponse reçue, code >= 400
        code, corps = exc.code, ""
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return CRITICAL, f"{url} : {exc}"
    if code != attendu:
        return CRITICAL, f"{url} : code {code}, attendu {attendu}"
    if (motif := spec.get("contient")) and motif not in corps:
        return WARNING, f"{url} : {code} mais sans {motif!r}"
    return OK, f"{url} : {code}"


def verif_tls(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    hote, port = spec["hote"], int(spec.get("port", 443))
    jours_min = int(spec.get("jours_min", 14))
    ctx = ssl.create_default_context()
    if spec.get("ca"):
        ctx.load_verify_locations(spec["ca"])
    try:
        with (
            socket.create_connection((hote, port), timeout=timeout) as s,
            ctx.wrap_socket(s, server_hostname=hote) as tls,
        ):
            cert = tls.getpeercert()
    except ssl.SSLCertVerificationError as exc:
        return CRITICAL, f"{hote}:{port} certificat refusé : {exc.reason}"
    except OSError as exc:
        return CRITICAL, f"{hote}:{port} injoignable ({exc})"
    if not cert or "notAfter" not in cert:
        return UNKNOWN, f"{hote}:{port} certificat sans date d'expiration"
    fin = ssl.cert_time_to_seconds(str(cert["notAfter"]))
    restant = (fin - time.time()) / 86400
    if restant < 0:
        return CRITICAL, f"{hote}:{port} certificat expiré"
    if restant < jours_min:
        return WARNING, f"{hote}:{port} expire dans {restant:.0f} j"
    return OK, f"{hote}:{port} expire dans {restant:.0f} j"


def verif_disque(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    chemin, pct_max = spec["chemin"], float(spec.get("pct_max", 90))
    try:
        u = shutil.disk_usage(chemin)
    except OSError as exc:
        return UNKNOWN, f"{chemin} : {exc}"
    pct = 100 * u.used / u.total
    detail = f"{chemin} utilisé à {pct:.1f} % ({u.free // 2**20} Mo libres)"
    if pct >= pct_max:
        return CRITICAL, detail
    if pct >= pct_max - 10:
        return WARNING, detail
    return OK, detail


def verif_commande(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    argv = spec["argv"]
    if isinstance(argv, str) or not all(isinstance(a, str) for a in argv):
        # une chaîne = un seul mot, pas un shell ; et YAML lit `true`
        # comme un booléen : on exige une liste de chaînes, rien d'autre.
        return UNKNOWN, "argv doit être une liste de chaînes"
    try:
        p = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=spec.get("timeout", timeout),
        )
    except FileNotFoundError:
        return UNKNOWN, f"{argv[0]} introuvable"
    except subprocess.TimeoutExpired:
        return CRITICAL, f"{argv[0]} : délai dépassé"
    sortie = (p.stdout or p.stderr).strip().splitlines()
    premiere = sortie[0] if sortie else ""
    if p.returncode != 0:
        return CRITICAL, f"{' '.join(argv)} -> {p.returncode} {premiere}"
    return OK, f"{' '.join(argv)} -> 0 {premiere}"


VERIFS: dict[str, Callable[[dict[str, Any], float], tuple[int, str]]] = {
    "tcp": verif_tcp,
    "http": verif_http,
    "tls": verif_tls,
    "disque": verif_disque,
    "commande": verif_commande,
}


# --- orchestration ---------------------------------------------------------
def executer(spec: dict[str, Any], timeout: float) -> Resultat:
    nom, type_ = spec.get("nom", "?"), spec.get("type", "?")
    debut = time.monotonic()
    fonction = VERIFS.get(type_)
    if fonction is None:
        code, detail = UNKNOWN, f"type inconnu : {type_}"
    else:
        try:
            code, detail = fonction(spec, timeout)
        except KeyError as exc:  # clé manquante dans le YAML
            code, detail = UNKNOWN, f"paramètre manquant : {exc}"
    duree = int((time.monotonic() - debut) * 1000)
    log.info("%-8s %-24s %s (%d ms)", LIBELLE[code], nom, detail, duree)
    return Resultat(nom, type_, code, detail, duree)


def charger_config(chemin: Path) -> dict[str, Any]:
    import yaml

    with chemin.open(encoding="utf-8") as f:
        conf = yaml.safe_load(f) or {}
    if not isinstance(conf.get("verifications"), list):
        raise ValueError("clé 'verifications' absente ou invalide")
    return conf


def rapport(resultats: list[Resultat]) -> dict[str, Any]:
    pire = max((r.code for r in resultats), default=UNKNOWN)
    return {
        "horodatage": datetime.now(UTC).isoformat(timespec="seconds"),
        "hote": socket.gethostname(),
        "statut": LIBELLE[pire],
        "code": pire,
        "nb": {
            lib: sum(1 for r in resultats if r.code == c)
            for c, lib in LIBELLE.items()
        },
        "verifications": [asdict(r) | {"statut": r.statut} for r in resultats],
    }


def ecrire_atomique(chemin: Path, texte: str) -> None:
    """Écrit dans un temporaire du MÊME répertoire, puis rename atomique."""
    fd, tmp = tempfile.mkstemp(dir=chemin.parent, prefix=".sante-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(texte)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, chemin)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def rendre_texte(rap: dict[str, Any]) -> str:
    lignes = [f"{rap['statut']} — {rap['hote']} — {rap['horodatage']}"]
    lignes += [
        f"  [{v['statut']:8}] {v['nom']}: {v['detail']}"
        for v in rap["verifications"]
    ]
    return "\n".join(lignes) + "\n"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument(
        "-c", "--config", type=Path, default=Path("/etc/factura/sante.yaml")
    )
    p.add_argument("--only", metavar="NOM", help="une seule vérification")
    p.add_argument("--timeout", type=float, default=3.0)
    p.add_argument("--text", action="store_true", help="sortie lisible")
    p.add_argument(
        "-o", "--output", type=Path, help="écrire le JSON ici (atomiquement)"
    )
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    try:
        conf = charger_config(args.config)
    except (OSError, ValueError) as exc:
        log.error("configuration %s : %s", args.config, exc)
        print(
            json.dumps(
                {"statut": "UNKNOWN", "code": UNKNOWN, "detail": str(exc)}
            )
        )
        return UNKNOWN
    specs = conf["verifications"]
    if args.only:
        specs = [s for s in specs if s.get("nom") == args.only]
    timeout = float(conf.get("timeout", args.timeout))
    resultats = [executer(s, timeout) for s in specs]
    rap = rapport(resultats)
    texte = json.dumps(rap, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        try:
            ecrire_atomique(args.output, texte)
        except OSError as exc:
            log.error("écriture de %s : %s", args.output, exc)
            return UNKNOWN
    sys.stdout.write(rendre_texte(rap) if args.text else texte)
    return rap["code"]


if __name__ == "__main__":
    sys.exit(main())
