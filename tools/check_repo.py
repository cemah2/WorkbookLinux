#!/usr/bin/env python3
"""Contrôles de cohérence du dépôt (lancés par la CI et par `make check`).

1. Identifiants : chaque item d'un énoncé (Q, QO, E, L, BF, D, PA, PB, PC,
   INC) a son ancre dans le corrigé, et réciproquement.
2. Liens relatifs : le fichier cible existe ; une ancre #id existe dans la
   cible (ancres explicites <a id> ou titres).
3. Schémas : chaque image assets/figures/*.svg citée existe, chaque source
   TikZ (assets/figures/src/) a son SVG, et chaque bloc Mermaid est non vide.
4. Scripts : chaque script setup/check/break cité dans un énoncé existe,
   et chaque script check/break est cité quelque part.
5. Structure : blocs de code fermés, aucune syntaxe étrangère au Markdown
   GitHub (::: ou @fig) hors code, alertes GitHub avec un libellé connu.

Sortie non nulle au premier problème trouvé dans une catégorie.
"""
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workbook import ROOT, items, item_dir  # noqa: E402

FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
ANCHOR = re.compile(r'<a id="([^"]+)"></a>')
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
IMG = re.compile(r'<img src="([^"]+)"|!\[[^\]]*\]\(([^)\s]+)\)')
LABELS = {"Objectifs", "Astuce", "Attention", "Variante Rocky / RHEL", "Contexte", "Pourquoi",
          "Piège", "Critère de succès", "Note"}

problems = {}


def bad(cat, msg):
    problems.setdefault(cat, []).append(msg)


def md_files():
    out = [ROOT / "README.md"] + sorted((ROOT / "docs").glob("*.md"))
    for _, slug in items():
        d = item_dir(slug)
        out += [d / "README.md", d / "corrige.md"]
    for extra in ("CONTRIBUTING.md", "CONVENTIONS.md", "CHANGELOG.md", "scripts/README.md", "reponses/README.md"):
        if (ROOT / extra).exists():
            out.append(ROOT / extra)
    return out


def gh_slug(heading):
    """Ancre automatique GitHub d'un titre."""
    h = heading.strip().lower()
    h = re.sub(r"<[^>]+>", "", h)
    h = "".join(c for c in h if c.isalnum() or c in " -_" or unicodedata.category(c).startswith("L"))
    return h.replace(" ", "-")


def anchors_of(path, cache={}):
    if path in cache:
        return cache[path]
    a = set()
    inf = False
    for l in path.read_text(encoding="utf-8").split("\n"):
        if FENCE.match(l):
            inf = not inf
            continue
        if inf:
            continue
        a.update(ANCHOR.findall(l))
        m = re.match(r"^#{1,6} (.*)$", l)
        if m:
            a.add(gh_slug(m.group(1)))
    cache[path] = a
    return a


def code_free_lines(path):
    inf = False
    for i, l in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        if FENCE.match(l.lstrip("> ")):
            inf = not inf
            yield i, l, True
            continue
        yield i, l, inf


# 1. identifiants ----------------------------------------------------------
for _, slug in items():
    d = item_dir(slug)
    e = set(ANCHOR.findall((d / "README.md").read_text(encoding="utf-8")))
    c = set(ANCHOR.findall((d / "corrige.md").read_text(encoding="utf-8")))
    for x in sorted(e - c):
        bad("identifiants", f"{slug} : {x} sans corrigé")
    for x in sorted(c - e):
        bad("identifiants", f"{slug} : {x} présent dans le corrigé seulement")

# 2. liens et 3. images ----------------------------------------------------
for f in md_files():
    for i, l, incode in code_free_lines(f):
        if incode:
            continue
        l = re.sub(r"(`+)(?:(?!\1).)+?\1", "", l)   # pas de liens dans le code inline
        for m in LINK.finditer(l):
            target = m.group(1)
            if re.match(r"^[a-z]+:", target) or target.startswith("#") and False:
                continue
            path, _, frag = target.partition("#")
            tp = (f.parent / path).resolve() if path else f
            if path and not tp.exists():
                bad("liens", f"{f.relative_to(ROOT)}:{i} : cible absente {target}")
                continue
            if frag and tp.suffix == ".md" and frag not in anchors_of(tp):
                bad("liens", f"{f.relative_to(ROOT)}:{i} : ancre absente {target}")
        for m in IMG.finditer(l):
            src = m.group(1) or m.group(2)
            if re.match(r"^[a-z]+:", src):
                continue
            if not (f.parent / src).resolve().exists():
                bad("schémas", f"{f.relative_to(ROOT)}:{i} : image absente {src}")
for tex in sorted((ROOT / "assets/figures/src").glob("[!_]*.tex")):
    if not (ROOT / "assets/figures" / (tex.stem + ".svg")).exists():
        bad("schémas", f"{tex.stem}.svg manquant : bash tools/render_figures.sh {tex.stem}")
for f in md_files():
    blocs = re.findall(r"^```mermaid\n(.*?)^```", f.read_text(encoding="utf-8"), re.M | re.S)
    for b in blocs:
        if not b.strip():
            bad("schémas", f"{f.relative_to(ROOT)} : bloc Mermaid vide")

# 4. scripts ---------------------------------------------------------------
all_text = "\n".join(p.read_text(encoding="utf-8") for p in md_files())
cited = set(re.findall(r"\b((?:setup|check|break)_(?:M\d{2}(?:_\d{2})?[a-z_]*|P[A-C](?:_\d+)+|P\d))\.sh\b", all_text))
for name in sorted(cited):
    if not list((ROOT / "scripts").rglob(name + ".sh")):
        bad("scripts", f"{name}.sh cité mais absent de scripts/")
for p in sorted(list((ROOT / "scripts/check").glob("*.sh")) + list((ROOT / "scripts/break").glob("*.sh"))
                + list((ROOT / "scripts/projects").rglob("check_*.sh")) + list((ROOT / "scripts/projects").rglob("break_*.sh"))):
    if p.stem not in cited:
        bad("scripts", f"{p.relative_to(ROOT)} n'est cité nulle part")

# 5. structure -------------------------------------------------------------
for f in md_files():
    lines = f.read_text(encoding="utf-8").split("\n")
    inf = None
    for i, l in enumerate(lines, 1):
        body = re.sub(r"^(>\s?)+", "", l)
        m = FENCE.match(body)
        if m:
            if inf is None:
                inf = m.group(1)
            elif body.strip().startswith(inf[0] * len(inf)) and body.strip() == body.strip()[:len(body.strip())] and set(body.strip()) <= {inf[0]}:
                inf = None
            continue
        if inf:
            continue
        if re.match(r"^:::", l) or l.startswith("@fig("):
            bad("structure", f"{f.relative_to(ROOT)}:{i} : syntaxe hors Markdown GitHub : {l[:40]}")
        if re.match(r"^> \[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]", l) and i < len(lines):
            nxt = lines[i]
            mm = re.match(r"^> \*\*(.+)\*\*\s*$", nxt)
            if f.parent.parent.name in ("modules", "projets") and (not mm or mm.group(1) not in LABELS):
                if "nav:" not in "".join(lines[max(0, i - 3):i]) and "Règle des 20 minutes" not in nxt:
                    bad("structure", f"{f.relative_to(ROOT)}:{i} : alerte sans libellé connu")
    if inf:
        bad("structure", f"{f.relative_to(ROOT)} : bloc de code non fermé")

# bilan --------------------------------------------------------------------
total = sum(len(v) for v in problems.values())
for cat in ("identifiants", "liens", "schémas", "scripts", "structure"):
    v = problems.get(cat, [])
    print(f"{cat:13s} : {'OK' if not v else str(len(v)) + ' problème(s)'}")
    for msg in v[:25]:
        print("   -", msg)
    if len(v) > 25:
        print(f"   … et {len(v) - 25} autres")
sys.exit(1 if total else 0)
