#!/usr/bin/env python3
"""Génère la navigation du dépôt (idempotent) :

- en tête et en pied de chaque énoncé / corrigé : fil d'Ariane, précédent /
  suivant, lien énoncé <-> corrigé, et pour l'énoncé la liste des scripts ;
- en tête des pages de docs/ ;
- le tableau des modules du README racine et de docs/parcours.md.

Tout ce qui est généré est encadré par <!-- nav:début --> / <!-- nav:fin -->
(ou <!-- parcours:début --> / <!-- parcours:fin -->) : ne pas éditer à la
main, relancer `python3 tools/gen_nav.py` (ou `make nav`).
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workbook import ROOT, PARTS, items, item_dir, title_of, short_label, estimated_time  # noqa: E402

NAV_RE = re.compile(r"<!-- nav:début -->.*?<!-- nav:fin -->\n*", re.S)
PAR_RE = re.compile(r"(<!-- parcours:début -->\n).*?(<!-- parcours:fin -->)", re.S)
ANCHOR_RE = re.compile(r'<a id="([^"]+)"></a>\**\[?([A-Z][A-Z0-9.\-]*?)\]?[(*\s]')


def rel(target, frm):
    """Chemin relatif de target (Path) depuis le dossier du fichier frm."""
    import os
    return os.path.relpath(target, frm.parent).replace(os.sep, "/")


def strip_nav(text):
    return NAV_RE.sub("", text).lstrip("\n").rstrip("\n") + "\n"


def scripts_for(slug, readme_text):
    """[(chemin relatif au dépôt, libellé)] des scripts cités par l'énoncé."""
    if slug.startswith("P"):
        sdir = ROOT / "scripts" / "projects" / slug[:2]
        files = sorted(sdir.glob("*.sh"), key=lambda p: ({"setup": 0, "check": 1, "break": 2}.get(p.stem.split("_")[0], 3), p.name))
    else:
        n = slug[:2]
        files = (sorted((ROOT / "scripts" / "setup").glob(f"setup_M{n}*.sh"))
                 + sorted((ROOT / "scripts" / "check").glob(f"check_M{n}_*.sh"))
                 + sorted((ROOT / "scripts" / "break").glob(f"break_M{n}_*.sh")))
    lines = readme_text.split("\n")
    out = []
    for f in files:
        name = f.stem
        label = ""
        for i, l in enumerate(lines):
            if name in l:
                for k in range(i, -1, -1):
                    m = re.search(r'<a id="[^"]+"></a>(?:\*\*)?\[?([A-Z][A-Z0-9.\-]*)', lines[k])
                    if m:
                        label = m.group(1)
                        break
                break
        kind = "prépare le module" if name.startswith("setup") else (
            f"vérifie {label}" if name.startswith("check") else f"installe la panne {label}")
        if name.startswith("check") and not label:
            kind = "vérification"
        if name.startswith("break") and not label:
            kind = "installe une panne"
        out.append((f.relative_to(ROOT), kind.strip()))
    return out


def nav_item(idx, seq, which):
    part, slug = seq[idx]
    d = item_dir(slug)
    f = d / ("README.md" if which == "enonce" else "corrige.md")
    label = short_label(slug)
    title, _ = title_of(slug)
    home = rel(ROOT / "README.md", f)
    parcours = rel(ROOT / "docs" / "parcours.md", f)
    prev_ = seq[idx - 1][1] if idx > 0 else None
    next_ = seq[idx + 1][1] if idx + 1 < len(seq) else None
    tgt = "README.md" if which == "enonce" else "corrige.md"

    def link(s):
        return rel(item_dir(s) / tgt, f)

    crumbs = f"[Accueil]({home}) › [Parcours]({parcours}) › {part[0]} — {part[1]} › **{label}**"
    if which == "corrige":
        crumbs += " · corrigé"
    nav = []
    if prev_:
        nav.append(f"[← {short_label(prev_)}]({link(prev_)})")
    if which == "enonce":
        nav.append("[Corrigé](corrige.md)")
    else:
        nav.append("[Énoncé](README.md)")
    if next_:
        nav.append(f"[{short_label(next_)} →]({link(next_)})")
    top = ["<!-- nav:début -->", crumbs + "  ", " · ".join(nav)]
    if which == "enonce":
        sc = scripts_for(slug, strip_nav((d / "README.md").read_text(encoding="utf-8")))
        if sc:
            top += ["", f"<details><summary>Scripts du module ({len(sc)})</summary>", "",
                    "Sur la VM indiquée en section « Mise en place », depuis `~/workbook/scripts/`"
                    " (voir [chapitre 0](" + rel(ROOT / "docs" / "00-mise-en-place.md", f) + ")).", "",
                    "| Script | Rôle |", "|---|---|"]
            for p, kind in sc:
                top.append(f"| [`{p.name}`]({rel(ROOT / p, f)}) | {kind} |")
            top += ["", "</details>"]
    else:
        top += ["", "> [!TIP]",
                "> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, "
                "pas avant. Chaque identifiant renvoie à son énoncé."]
    top += ["<!-- nav:fin -->", ""]
    bottom = ["", "<!-- nav:début -->", "---", "", " · ".join(nav) + f" · [Parcours]({parcours}) · [Accueil]({home})",
              "<!-- nav:fin -->"]
    return "\n".join(top), "\n".join(bottom)


def apply_item_nav():
    seq = items()
    for idx, (part, slug) in enumerate(seq):
        d = item_dir(slug)
        for which, fname in (("enonce", "README.md"), ("corrige", "corrige.md")):
            f = d / fname
            body = strip_nav(f.read_text(encoding="utf-8"))
            top, bottom = nav_item(idx, seq, which)
            f.write_text(top + "\n" + body + bottom + "\n", encoding="utf-8")


DOCS = [("00-mise-en-place.md", "Chapitre 0 — Mise en place"), ("parcours.md", "Parcours"),
        ("annexes.md", "Annexes"), ("memo.md", "Mémo")]


def apply_docs_nav():
    for fname, label in DOCS:
        f = ROOT / "docs" / fname
        if not f.exists():
            continue
        body = strip_nav(f.read_text(encoding="utf-8"))
        links = [f"[Accueil](../README.md)"] + [
            (f"**{lab}**" if fn == fname else f"[{lab}]({fn})") for fn, lab in DOCS]
        top = "<!-- nav:début -->\n" + " · ".join(links) + "\n<!-- nav:fin -->\n\n"
        f.write_text(top + body, encoding="utf-8")


def parcours_table(frm):
    out = []
    for part in PARTS:
        out.append(f"### {part[0]} — {part[1]}")
        out.append("")
        out.append(f"{part[2]}")
        out.append("")
        out.append("| | Module | Durée | Énoncé | Corrigé |")
        out.append("|---|---|---|---|---|")
        for slug in part[3]:
            title, _ = title_of(slug)
            d = item_dir(slug)
            num = slug[:2] if not slug.startswith("P") else {"P1": "A", "P2": "B", "P3": "C"}[slug[:2]]
            out.append(f"| **{num}** | {title} | {estimated_time(slug)} | "
                       f"[énoncé]({rel(d / 'README.md', frm)}) | [corrigé]({rel(d / 'corrige.md', frm)}) |")
        out.append("")
    return "\n".join(out)


def apply_parcours():
    for f in (ROOT / "README.md", ROOT / "docs" / "parcours.md"):
        if not f.exists():
            continue
        t = f.read_text(encoding="utf-8")
        if "<!-- parcours:début -->" not in t:
            continue
        t = PAR_RE.sub(lambda m: m.group(1) + parcours_table(f) + "\n" + m.group(2), t)
        f.write_text(t, encoding="utf-8")


if __name__ == "__main__":
    apply_item_nav()
    apply_docs_nav()
    apply_parcours()
    print("navigation régénérée")
