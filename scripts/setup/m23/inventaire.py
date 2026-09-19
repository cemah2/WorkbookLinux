#!/usr/bin/env python3
"""inventaire.py — inventaire Ansible généré depuis l'API Proxmox.

Deux sources :
  --fixture FICHIER.json   réponses figées de l'API (travail hors ligne)
  --url https://10.10.10.1:8006 + variable PVE_TOKEN (user@realm!id=uuid)

Règles : seules les VM qemu sont prises ; les templates sont ignorés ; les
VM arrêtées sont ignorées sauf --all ; un groupe par tag Proxmox ; l'adresse
vient de ipconfig0 (cloud-init), à défaut de la résolution DNS de
<nom>.lab.local, à défaut la VM est signalée et omise.

Codes de sortie : 0 ok, 1 erreur API/fichier, 2 usage, 4 aucune VM.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import socket
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

log = logging.getLogger("inventaire")


# --- modèle ----------------------------------------------------------------
@dataclass(frozen=True)
class Machine:
    nom: str
    vmid: int
    node: str
    statut: str
    adresse: str | None
    tags: tuple[str, ...] = field(default_factory=tuple)


# --- sources : même interface, deux implémentations -----------------------
class Source(Protocol):
    def ressources(self) -> list[dict[str, Any]]: ...

    def config(self, node: str, vmid: int) -> dict[str, Any]: ...


class Fixture:
    """Lit un JSON qui imite les deux appels API."""

    def __init__(self, chemin: Path) -> None:
        with chemin.open(encoding="utf-8") as f:
            self.data = json.load(f)

    def ressources(self) -> list[dict[str, Any]]:
        return self.data["resources"]

    def config(self, node: str, vmid: int) -> dict[str, Any]:
        return self.data["configs"].get(str(vmid), {})


class ApiProxmox:
    """Appels REST authentifiés par token (Authorization: PVEAPIToken=...)."""

    def __init__(self, url: str, token: str, verify: bool | str) -> None:
        import requests  # import tardif : le mode --fixture n'en a pas besoin

        self.base = url.rstrip("/") + "/api2/json"
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"PVEAPIToken={token}"
        self.s.verify = verify

    def _get(self, chemin: str, **params: Any) -> Any:
        r = self.s.get(self.base + chemin, params=params, timeout=(3.05, 15))
        r.raise_for_status()  # 401/403/5xx -> exception, jamais un faux vide
        return r.json()["data"]

    def ressources(self) -> list[dict[str, Any]]:
        return self._get("/cluster/resources", type="vm")

    def config(self, node: str, vmid: int) -> dict[str, Any]:
        return self._get(f"/nodes/{node}/qemu/{vmid}/config")


# --- logique métier (pure : testable sans réseau) --------------------------
def adresse_depuis_ipconfig(ipconfig: str | None) -> str | None:
    """'ip=10.10.10.11/24,gw=10.10.10.1' -> '10.10.10.11' ; dhcp -> None."""
    if not ipconfig:
        return None
    for champ in ipconfig.split(","):
        cle, _, val = champ.partition("=")
        if cle == "ip" and val != "dhcp":
            try:
                return str(ipaddress.ip_interface(val).ip)
            except ValueError:
                log.warning("ipconfig0 illisible : %r", val)
    return None


def resoudre(nom: str, domaine: str) -> str | None:
    try:
        return socket.gethostbyname(f"{nom}.{domaine}")
    except OSError:
        return None


def collecter(
    src: Source, inclure_arretees: bool, domaine: str
) -> list[Machine]:
    machines: list[Machine] = []
    for r in src.ressources():
        if r.get("type") != "qemu" or r.get("template"):
            continue
        if r.get("status") != "running" and not inclure_arretees:
            continue
        conf = src.config(r["node"], r["vmid"])
        adresse = adresse_depuis_ipconfig(conf.get("ipconfig0"))
        if adresse is None:
            adresse = resoudre(r["name"], domaine)
        tags = tuple(t for t in (r.get("tags") or "").split(";") if t)
        if adresse is None:
            log.warning(
                "%s (vmid %s) : aucune adresse, omise", r["name"], r["vmid"]
            )
            continue
        machines.append(
            Machine(
                r["name"], r["vmid"], r["node"], r["status"], adresse, tags
            )
        )
    return sorted(machines, key=lambda m: m.nom)


def par_groupe(machines: list[Machine]) -> dict[str, list[Machine]]:
    groupes: dict[str, list[Machine]] = {}
    for m in machines:
        for t in m.tags or ("sans_tag",):
            groupes.setdefault(t, []).append(m)
    return dict(sorted(groupes.items()))


def rendre_ini(machines: list[Machine]) -> str:
    lignes = ["[all]"]
    lignes += [
        f"{m.nom} ansible_host={m.adresse} vmid={m.vmid}" for m in machines
    ]
    for groupe, membres in par_groupe(machines).items():
        lignes += ["", f"[{groupe}]"] + [m.nom for m in membres]
    return "\n".join(lignes) + "\n"


def rendre_yaml(machines: list[Machine]) -> str:
    import yaml  # PyYAML : pip install PyYAML

    doc = {
        "all": {
            "hosts": {
                m.nom: {
                    "ansible_host": m.adresse,
                    "vmid": m.vmid,
                    "proxmox_node": m.node,
                }
                for m in machines
            },
            "children": {
                g: {"hosts": {m.nom: None for m in membres}}
                for g, membres in par_groupe(machines).items()
            },
        }
    }
    return yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)


# --- interface ---------------------------------------------------------------
def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--fixture", type=Path, help="JSON de réponses API")
    src.add_argument("--url", help="ex. https://10.10.10.1:8006")
    p.add_argument("--format", choices=("ini", "yaml"), default="ini")
    p.add_argument(
        "--all", action="store_true", help="inclure les VM arrêtées"
    )
    p.add_argument("--domaine", default="lab.local")
    p.add_argument("--ca", help="chemin du CA à faire confiance")
    p.add_argument(
        "--insecure",
        action="store_true",
        help="ne pas vérifier le certificat (lab uniquement)",
    )
    p.add_argument("-o", "--output", type=Path, help="fichier de sortie")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )
    try:
        if args.fixture:
            src: Source = Fixture(args.fixture)
        else:
            token = os.environ.get("PVE_TOKEN")
            if not token:
                log.error("PVE_TOKEN absent (user@realm!id=uuid)")
                return 2
            verify: bool | str = args.ca if args.ca else not args.insecure
            src = ApiProxmox(args.url, token, verify)
        machines = collecter(src, args.all, args.domaine)
    except (OSError, ValueError, KeyError) as exc:
        # requests.RequestException hérite d'OSError : réseau, HTTP 4xx/5xx,
        # fichier absent et JSON invalide finissent tous ici, sans traceback.
        log.error("source injoignable ou illisible : %s", exc)
        return 1
    if not machines:
        log.error("aucune VM retenue")
        return 4
    texte = (
        rendre_yaml(machines)
        if args.format == "yaml"
        else rendre_ini(machines)
    )
    if args.output:
        args.output.write_text(texte, encoding="utf-8")
        log.info("%d hôtes écrits dans %s", len(machines), args.output)
    else:
        sys.stdout.write(texte)
    return 0


if __name__ == "__main__":
    sys.exit(main())
