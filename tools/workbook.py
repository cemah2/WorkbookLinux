"""Structure du workbook : source unique pour la navigation, le README,
et la vérification des identifiants.

Ajouter un module = créer modules/NN-slug/{README.md,corrige.md} puis
l'inscrire ici, dans la bonne partie.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent

PARTS = [
    ("Partie I", "Fondamentaux du shell et du système de fichiers",
     "Tout ce qu'un administrateur manipule cent fois par jour : le shell, "
     "l'arborescence, les droits, les comptes, le texte.",
     ["01-shell-bases", "02-filesystem-fhs", "03-permissions",
      "04-users-groups-sudo", "05-text-processing", "06-vim-archives"]),
    ("Partie II", "Administration système",
     "Scripter, piloter les processus et le noyau, installer, stocker, connecter, "
     "accéder à distance : le socle d'un serveur en production.",
     ["07-bash-scripting", "08-processus-systemd", "09-noyau-demarrage", "10-paquets",
      "11-stockage-lvm", "12-reseau", "13-reseau-avance", "14-ssh"]),
    ("Partie III", "Exploitation, sécurité et incidents",
     "Ce qui distingue un serveur qui tourne d'un serveur qu'on exploite : services, "
     "journaux, planification, durcissement, dépannage.",
     ["15-services-applicatifs", "16-logs-monitoring", "17-cron-timers", "18-securite",
      "19-troubleshooting-perf"]),
    ("Projet A", "Factura : plateforme multi-services, à la main",
     "Premier projet fil rouge. Tu déploies, sécurises, sauvegardes et "
     "supervises une plateforme complète avec les seuls modules 1 à 19.",
     ["P1-factura"]),
    ("Partie IV", "Socle DevOps",
     "Virtualiser, versionner, conteneuriser, automatiser, provisionner, livrer en continu, "
     "orchestrer, observer, outiller en Python.",
     ["20-virtualisation-kvm", "21-git", "22-docker", "23-ansible", "24-iac-terraform",
      "25-cicd", "26-kubernetes-observabilite", "27-python-ops"]),
    ("Projet B", "Factura v2 : industrialisation DevOps",
     "La même plateforme, reconstruite par le code : OpenTofu, Ansible, "
     "Compose, CI/CD, observabilité, k3s.",
     ["P2-factura-devops"]),
    ("Partie V", "Expertise système",
     "Ce qui fait passer d'administrateur à expert : identité centralisée, haute "
     "disponibilité, sauvegarde et reprise, traçage du noyau, systèmes de fichiers "
     "avancés, empaquetage.",
     ["28-identite-centralisee"]),
    ("Projet C", "Une semaine d'astreinte",
     "Examen final : cinq journées de tickets, d'incidents et de "
     "post-mortems sur la plateforme Factura.",
     ["P3-astreinte"]),
]


def item_dir(slug):
    return ROOT / ("projets" if slug.startswith("P") else "modules") / slug


def items():
    """Liste ordonnée (partie, slug)."""
    out = []
    for part in PARTS:
        for slug in part[3]:
            out.append((part, slug))
    return out


def title_of(slug):
    """Titre H1 de l'énoncé, sans le préfixe « Module NN — »."""
    first = (item_dir(slug) / "README.md").read_text(encoding="utf-8")
    for line in first.split("\n"):
        if line.startswith("# "):
            t = line[2:].strip()
            return re.sub(r"^(Module \d+|Projet [A-Z]) — ", "", t), t
    return slug, slug


def short_label(slug):
    if slug.startswith("P"):
        return "Projet " + {"P1": "A", "P2": "B", "P3": "C"}[slug[:2]]
    return "Module " + slug[:2]


def estimated_time(slug):
    txt = (item_dir(slug) / "README.md").read_text(encoding="utf-8")
    m = re.search(r"Temps estimé(?:\*\*)?\s*:\s*([^\n]+)", txt)
    if not m:
        return ""
    return re.split(r",| \(", m.group(1).strip().rstrip("."))[0].strip()
