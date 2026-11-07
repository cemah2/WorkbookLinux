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


def cover(title, subtitle, desc, rows, badge):
    tab = "\\begin{tabular}{@{}ll@{}}" + "".join(
        f"\\textbf{{{tex_escape(k)}}} & {tex_escape(v)}\\\\[2pt]" for k, v in rows) + "\\end{tabular}"
    return raw(f"\\coverpage{{{tex_escape(title)}}}{{{tex_escape(subtitle)}}}{{{desc}}}{{{tab}}}{{{tex_escape(badge)}}}")


def part(num, title, desc, mods, kind):
    items = []
    for m in mods:
        p = SRC / kind / f"{m}.md"
        first = p.read_text(encoding="utf-8").splitlines()[0].lstrip("# ").strip()
        items.append(f"\\item {tex_escape(first)}")
    body = (f"{tex_escape(desc)}\\par\\vspace{{10pt}}\\begin{{itemize}}[nosep]\\normalsize"
            + "".join(items) + "\\end{itemize}")
    big = num.split()[-1]
    return raw(f"\\partpage{{{tex_escape(num)}}}{{{tex_escape(title)}}}{{{body}}}{{{tex_escape(big)}}}")


def clean_md(text):
    # les Markdown se terminent proprement ; on isole chaque fichier
    return text.rstrip() + "\n\n"


def assemble(kind):
    parts = []
    if kind == "labs":
        parts.append(cover(
            "Énoncés", "Quiz, exercices, labs, Break & Fix, projets",
            "27 modules et 3 projets fil rouge pour devenir opérationnel sur Linux "
            "puis sur le socle DevOps : Git, Docker, Ansible, OpenTofu, CI/CD, Kubernetes, "
            "observabilité. Chaque module se joue sur ton laboratoire Proxmox et se corrige "
            "avec le volume \\emph{Corrigés \\& explications}.\\par\\vspace{8pt}"
            "\\textbf{Partie I} Fondamentaux · \\textbf{Partie II} Administration système · "
            "\\textbf{Partie III} Exploitation, sécurité, incidents · \\textbf{Projet A} Factura à la main · "
            "\\textbf{Partie IV} Socle DevOps · \\textbf{Projet B} Factura industrialisée · "
            "\\textbf{Projet C} Une semaine d'astreinte · \\textbf{Annexes} progression, certifications, modèles.",
            [("Volume", "1 / 3 — Énoncés"), ("Niveau", "Intermédiaire → confirmé"),
             ("Durée conseillée", "14 à 19 semaines"),
             ("Compagnons", "Corrigés & explications · Mémo · scripts.zip")], "VOLUME 1 / 3"))
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
             ("Compagnons", "Énoncés · Mémo · scripts.zip")], "VOLUME 2 / 3"))
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
            [("Volume", "3 / 3 — Mémo"), ("Usage", "À imprimer et garder à côté du clavier")], "VOLUME 3 / 3"))
        parts.append(raw("\\tableofcontents\\clearpage"))
        parts.append(clean_md((SRC / "memo.md").read_text(encoding="utf-8")))
        title, foot = "Mémo Linux \\& DevOps", "Mémo"
    md = BUILD / f"{kind}.md"
    md.write_text("".join(parts), encoding="utf-8")
    return md, title, foot


def build(kind, name, a5=False):
    md, title, foot = assemble(kind)
    if a5:
        md2 = BUILD / f"{kind}-a5.md"; md2.write_text(md.read_text(encoding="utf-8"), encoding="utf-8")
        md, kind = md2, f"{kind}-a5"
    tex = BUILD / f"{kind}.tex"
    import os
    env = dict(os.environ, LANG="C.UTF-8", LC_ALL="C.UTF-8", WB_INDEX="1" if kind == "labs" else "0",
               WB_INDEX_FILE=str(TEX / "index-commands.txt"))
    subprocess.run(
        ["pandoc", str(md), "-f", "markdown+fenced_divs+pipe_tables+smart+raw_attribute-yaml_metadata_block-tex_math_dollars",
         "--lua-filter", str(TEX / "divs.lua"), "--template", str(TEX / "template.tex"),
         "--top-level-division=chapter", "--highlight-style=pygments",
         "-V", f"footer-title={foot}", "-V", f"title={title}",
         "-V", f"fontdir={ROOT / 'fonts'}", "-V", f"texdir={TEX}", "-o", str(tex)]
        + (["-V", "index=true"] if kind == "labs" else [])
        + (["-V", "a5=true"] if a5 else []),
        check=True, env=env)
    log = None
    for i in range(4):
        r = subprocess.run(["xelatex", "-interaction=nonstopmode", "-halt-on-error",
                            f"-output-directory={BUILD}", str(tex)],
                           capture_output=True, text=True)
        log = r.stdout
        if r.returncode != 0:
            errs = [l for l in log.splitlines() if l.startswith("!") or l.startswith("l.")]
            print("\n".join(errs[:20]), file=sys.stderr)
            raise SystemExit(f"xelatex a échoué pour {kind} (passe {i+1})")
        if kind == "labs" and (BUILD / f"{kind}.idx").exists():
            subprocess.run(["makeindex", "-q", f"{kind}.idx"], capture_output=True, cwd=BUILD)
        if "Rerun to get" not in log and i >= 1:
            break
    pdf = BUILD / f"{kind}.pdf"
    out = BUILD / name
    shutil.copy(pdf, out)
    pages = re.search(r"Output written on .*? \((\d+) pages", log).group(1)
    over = log.count("Overfull \\hbox")
    print(f"{name}: {pages} pages, {over} overfull hbox")
    return out


def booklet(src, dst):
    """Impose des pages A5 en livret sur des feuilles A4 paysage (recto/verso, bord court)."""
    from pypdf import PdfReader, PdfWriter, Transformation, PageObject
    r = PdfReader(str(src)); n = len(r.pages)
    total = (n + 3) // 4 * 4
    A4W, A4H = 841.89, 595.28   # paysage
    A5W = A4W / 2
    def page(i):
        return r.pages[i] if i < n else None
    order = []
    lo, hi = 0, total - 1
    while lo < hi:
        order.append((hi, lo)); order.append((lo + 1, hi - 1))
        lo += 2; hi -= 2
    w = PdfWriter()
    for left, right in order:
        sheet = PageObject.create_blank_page(width=A4W, height=A4H)
        for src_i, x in ((left, 0), (right, A5W)):
            p = page(src_i)
            if p is None: continue
            pw = float(p.mediabox.width); ph = float(p.mediabox.height)
            sc = min(A5W / pw, A4H / ph)
            t = Transformation().scale(sc, sc).translate(x + (A5W - pw * sc) / 2, (A4H - ph * sc) / 2)
            sheet.merge_transformed_page(p, t)
        w.add_page(sheet)
    w.add_metadata({"/Title": "Mémo Linux & DevOps — livret A5 (imprimer recto/verso, retourner sur le bord court)"})
    with open(dst, "wb") as f: w.write(f)
    print(f"{dst.name}: {len(order)} faces A4 ({total} pages A5)")


if __name__ == "__main__":
    names = {"labs": "Workbook-Linux-DevOps-1-Enonces.pdf",
             "solutions": "Workbook-Linux-DevOps-2-Corriges.pdf",
             "memo": "Workbook-Linux-DevOps-3-Memo.pdf",
             "memo-a5": "Workbook-Linux-DevOps-3-Memo-livret-A5.pdf"}
    for k in (sys.argv[1:] or ["memo", "memo-a5", "labs", "solutions"]):
        if k == "memo-a5":
            pdf = build("memo", "memo-a5-pages.pdf", a5=True)
            booklet(pdf, BUILD / names[k])
        else:
            build(k, names[k])
