#!/usr/bin/env python3
"""Assemble les Markdown en un document LaTeX puis en PDF (pandoc + XeLaTeX)."""
import re, subprocess, sys, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC, BUILD, TEX = ROOT / "src", ROOT / "build", ROOT / "tex"
BUILD.mkdir(exist_ok=True)

PARTS = [
    ("Partie I", "Fondamentaux du shell et du système de fichiers",
     "Tout ce qu'un administrateur manipule cent fois par jour : le shell, "
     "l'arborescence, les droits, les comptes, le texte.",
     ["01-shell-bases", "02-filesystem-fhs", "03-permissions",
      "04-users-groups-sudo", "05-text-processing", "06-vim-archives"]),
    ("Partie II", "Administration système",
     "Scripter, superviser les processus, installer, stocker, connecter, "
     "accéder à distance : le socle d'un serveur en production.",
     ["07-bash-scripting", "08-processus-systemd", "09-paquets",
      "10-stockage-lvm", "11-reseau", "12-ssh"]),
    ("Partie III", "Exploitation, sécurité et incidents",
     "Ce qui distingue un serveur qui tourne d'un serveur qu'on exploite : "
     "journaux, planification, durcissement, dépannage.",
     ["13-logs-monitoring", "14-cron-timers", "15-securite",
      "16-troubleshooting-perf"]),
    ("Projet A", "Factura : plateforme multi-services, à la main",
     "Premier projet fil rouge. Tu déploies, sécurises, sauvegardes et "
     "supervises une plateforme complète avec les seuls modules 1 à 16.",
     ["P1-factura"]),
    ("Partie IV", "Socle DevOps",
     "Versionner, conteneuriser, automatiser, provisionner, livrer en continu, "
     "orchestrer et observer.",
     ["17-git", "18-docker", "19-ansible", "20-iac-terraform", "21-cicd",
      "22-kubernetes-observabilite"]),
    ("Projet B", "Factura v2 : industrialisation DevOps",
     "La même plateforme, reconstruite par le code : OpenTofu, Ansible, "
     "Compose, CI/CD, observabilité, k3s.",
     ["P2-factura-devops"]),
    ("Projet C", "Une semaine d'astreinte",
     "Examen final : cinq journées de tickets, d'incidents et de "
     "post-mortems sur la plateforme Factura.",
     ["P3-astreinte"]),
]


def tex_escape(s):
    return (s.replace("\\", r"\textbackslash{}").replace("&", r"\&").replace("%", r"\%")
             .replace("#", r"\#").replace("_", r"\_").replace("$", r"\$"))


def raw(latex):
    return "\n```{=latex}\n" + latex + "\n```\n\n"


def cover(title, subtitle, desc, rows):
    tab = "\\begin{tabular}{@{}ll@{}}" + "".join(
        f"\\textbf{{{tex_escape(k)}}} & {tex_escape(v)}\\\\" for k, v in rows) + "\\end{tabular}"
    return raw(f"\\coverpage{{{tex_escape(title)}}}{{{tex_escape(subtitle)}}}{{{desc}}}{{{tab}}}")


def part(num, title, desc, mods, kind):
    items = []
    for m in mods:
        p = SRC / kind / f"{m}.md"
        first = p.read_text(encoding="utf-8").splitlines()[0].lstrip("# ").strip()
        items.append(f"\\item {tex_escape(first)}")
    body = (f"{tex_escape(desc)}\\par\\vspace{{10pt}}\\begin{{itemize}}[nosep]\\normalsize"
            + "".join(items) + "\\end{itemize}")
    return raw(f"\\partpage{{{tex_escape(num)}}}{{{tex_escape(title)}}}{{{body}}}")


def clean_md(text):
    # les Markdown se terminent proprement ; on isole chaque fichier
    return text.rstrip() + "\n\n"


def assemble(kind):
    parts = []
    if kind == "labs":
        parts.append(cover(
            "Énoncés", "Quiz, exercices, labs, Break & Fix, projets",
            "22 modules et 3 projets fil rouge pour devenir opérationnel sur Linux "
            "puis sur le socle DevOps : Git, Docker, Ansible, OpenTofu, CI/CD, Kubernetes, "
            "observabilité. Chaque module se joue sur ton laboratoire Proxmox et se corrige "
            "avec le volume \\emph{Corrigés \\& explications}.",
            [("Volume", "1 / 3 — Énoncés"), ("Niveau", "Intermédiaire → confirmé"),
             ("Durée conseillée", "12 à 16 semaines"),
             ("Compagnons", "Corrigés & explications · Mémo · scripts.zip")]))
        parts.append(raw("\\tableofcontents\\clearpage"))
        parts.append(clean_md((SRC / "00-mise-en-place.md").read_text(encoding="utf-8")))
        for num, title, desc, mods in PARTS:
            parts.append(part(num, title, desc, mods, "labs"))
            for m in mods:
                parts.append(clean_md((SRC / "labs" / f"{m}.md").read_text(encoding="utf-8")))
        parts.append(clean_md((SRC / "99-annexes.md").read_text(encoding="utf-8")))
        title, foot = "Workbook Linux \\& DevOps — Énoncés", "Énoncés"
    elif kind == "solutions":
        parts.append(cover(
            "Corrigés & explications", "Réponses, mécanismes, pièges et diagnostics",
            "Le corrigé de chaque question, exercice, lab, Break \\& Fix et projet du volume "
            "\\emph{Énoncés}, avec pour chaque item l'explication du mécanisme sous-jacent et "
            "l'erreur classique à ne pas commettre. À ouvrir après vingt minutes de recherche, "
            "pas avant.",
            [("Volume", "2 / 3 — Corrigés"),
             ("Identifiants", "Q7.3 · QO7.1 · E7.12 · L7.2 · BF7.1 · D7"),
             ("Compagnons", "Énoncés · Mémo · scripts.zip")]))
        parts.append(raw("\\tableofcontents\\clearpage"))
        for num, title, desc, mods in PARTS:
            parts.append(part(num, title + " — corrigés", desc, mods, "solutions"))
            for m in mods:
                parts.append(clean_md((SRC / "solutions" / f"{m}.md").read_text(encoding="utf-8")))
        title, foot = "Workbook Linux \\& DevOps — Corrigés", "Corrigés \\& explications"
    else:
        parts.append(cover(
            "Mémo", "Aide-mémoire Linux & DevOps",
            "Les commandes, options et fichiers de configuration qui servent vraiment, module "
            "par module, plus les tableaux de référence (signaux, codes de sortie, ports, "
            "permissions, codes HTTP, états TCP) et la checklist des 60 secondes.",
            [("Volume", "3 / 3 — Mémo"), ("Usage", "À imprimer et garder à côté du clavier")]))
        parts.append(raw("\\tableofcontents\\clearpage"))
        parts.append(clean_md((SRC / "memo.md").read_text(encoding="utf-8")))
        title, foot = "Mémo Linux \\& DevOps", "Mémo"
    md = BUILD / f"{kind}.md"
    md.write_text("".join(parts), encoding="utf-8")
    return md, title, foot


def build(kind, name):
    md, title, foot = assemble(kind)
    tex = BUILD / f"{kind}.tex"
    subprocess.run(
        ["pandoc", str(md), "-f", "markdown+fenced_divs+pipe_tables+smart+raw_attribute-yaml_metadata_block",
         "--lua-filter", str(TEX / "divs.lua"), "--template", str(TEX / "template.tex"),
         "--top-level-division=chapter", "--highlight-style=pygments",
         "-V", f"footer-title={foot}", "-V", f"title={title}", "-o", str(tex)],
        check=True)
    log = None
    for i in range(3):
        r = subprocess.run(["xelatex", "-interaction=nonstopmode", "-halt-on-error",
                            f"-output-directory={BUILD}", str(tex)],
                           capture_output=True, text=True)
        log = r.stdout
        if r.returncode != 0:
            errs = [l for l in log.splitlines() if l.startswith("!") or l.startswith("l.")]
            print("\n".join(errs[:20]), file=sys.stderr)
            raise SystemExit(f"xelatex a échoué pour {kind} (passe {i+1})")
        if "Rerun to get" not in log and i >= 1:
            break
    pdf = BUILD / f"{kind}.pdf"
    out = BUILD / name
    shutil.copy(pdf, out)
    pages = re.search(r"Output written on .*? \((\d+) pages", log).group(1)
    over = log.count("Overfull \\hbox")
    print(f"{name}: {pages} pages, {over} overfull hbox")
    return out


if __name__ == "__main__":
    names = {"labs": "Workbook-Linux-DevOps-1-Enonces.pdf",
             "solutions": "Workbook-Linux-DevOps-2-Corriges.pdf",
             "memo": "Workbook-Linux-DevOps-3-Memo.pdf"}
    for k in (sys.argv[1:] or ["memo", "labs", "solutions"]):
        build(k, names[k])
