#!/usr/bin/env python3
"""Génère les fiches interactives (site statique) à partir des énoncés et
des corrigés Markdown.

    python3 tools/gen_fiches.py [--sortie _site] [--strict]

Une page par module et par projet : QCM à cocher et corrigés au clic,
zones de texte pour les questions ouvertes, exercices, labs, Break & Fix et
défis, corrigé dépliable, grille d'auto-évaluation cochable. Les réponses
restent dans le navigateur (localStorage) et s'exportent en Markdown.

Dépendance : markdown-it-py (pip install markdown-it-py).
--strict : échoue si un QCM n'a pas d'options ou de réponse lisible.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import workbook  # noqa: E402
import aides as A  # noqa: E402

try:
    from markdown_it import MarkdownIt
except ImportError:  # pragma: no cover
    sys.exit("markdown-it-py absent : pip install markdown-it-py")

ROOT = workbook.ROOT
DEPOT = "https://github.com/cemah2/WorkbookLinux"
BLOB = DEPOT + "/blob/main/"

MD = MarkdownIt("commonmark", {"html": True, "typographer": False}).enable(["table", "strikethrough"])

NAV_RE = re.compile(r"<!-- nav:début -->.*?<!-- nav:fin -->\n?", re.S)
ANCRE_RE = re.compile(r'^(#{1,6} )?<a id="([a-z0-9.-]+)"></a>(.*)$')
FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
OPTION_RE = re.compile(r"^([a-h])\) (.*)$")
TYPES = {
    "q": "qcm", "qo": "ouverte", "e": "exercice", "l": "lab", "bf": "breakfix",
    "d": "defi", "pa": "jalon", "pb": "jalon", "pc": "incident", "inc": "incident",
}
LIBELLES = {
    "qcm": "QCM", "ouverte": "Question ouverte", "exercice": "Exercice guidé",
    "lab": "Lab", "breakfix": "Break & Fix", "defi": "Défi", "jalon": "Jalon",
    "incident": "Incident",
}
PLACEHOLDER = {
    "ouverte": "Ta réponse, comme en entretien : le mécanisme, puis l'exemple…",
    "exercice": "Les commandes que tu as tapées et ce qu'elles affichent…",
    "lab": "Ton compte rendu : commandes, sorties utiles, choix faits, résultat du check…",
    "breakfix": "Ta démarche : symptôme, hypothèses, commandes de diagnostic, cause racine, correctif, prévention…",
    "defi": "Ton livrable ou le lien vers lui, et ce que tu en retiens…",
    "jalon": "Ce que tu as fait, les commandes clés, ce qui reste à faire…",
    "incident": "Chronologie, diagnostic, cause racine, correctif, actions de suivi…",
}
REPLIEES = ("Objectifs", "Mise en place", "Rappel express", "Présentation", "Architecture",
            "Pour l'entretien", "Grille d'évaluation", "Du manuel")

avertissements: list[str] = []


# =============================================================================
# Markdown -> HTML
# =============================================================================
def type_item(ident: str) -> str:
    m = re.match(r"[a-z]+", ident)
    return TYPES.get(m.group(0) if m else "", "ouverte")


def alertes(md: str) -> str:
    """Transforme les alertes GitHub (> [!NOTE] …) en blocs HTML."""
    lignes = md.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lignes):
        m = re.match(r"^>\s?\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$", lignes[i])
        if not m:
            out.append(lignes[i])
            i += 1
            continue
        genre = m.group(1).lower()
        i += 1
        bloc: list[str] = []
        while i < len(lignes) and lignes[i].startswith(">"):
            bloc.append(re.sub(r"^>\s?", "", lignes[i]))
            i += 1
        titre = ""
        while bloc and not bloc[0].strip():
            bloc.pop(0)
        if bloc and re.match(r"^\*\*[^*]+\*\*\s*$", bloc[0]):
            titre = bloc.pop(0).strip().strip("*")
        interieur = rendu("\n".join(bloc))
        t = f'<p class="alerte-titre">{html.escape(titre)}</p>' if titre else ""
        out.append(f'\n<div class="alerte alerte-{genre}">{t}{interieur}</div>\n')
    return "\n".join(out)


def rendu(md: str) -> str:
    h = MD.render(alertes(md))
    h = re.sub(r'<pre><code class="language-mermaid">(.*?)</code></pre>',
               r'<pre class="mermaid">\1</pre>', h, flags=re.S)
    return h


def liens(h: str, src: Path) -> str:
    """Réécrit les liens et images relatifs d'un fichier source vers le site."""
    base = src.parent

    def cible(url: str, image: bool) -> str:
        if re.match(r"^(https?:|mailto:|#|data:)", url):
            return url
        chemin, _, frag = url.partition("#")
        frag = ("#" + frag) if frag else ""
        if not chemin:
            return frag or url
        p = (base / chemin).resolve()
        try:
            rel = p.relative_to(ROOT).as_posix()
        except ValueError:
            return url
        if image and rel.startswith("assets/figures/"):
            return "assets/figures/" + Path(rel).name
        m = re.match(r"^(modules|projets)/([^/]+)/(README|corrige)\.md$", rel)
        if m:
            if m.group(2) == src.parent.name:
                return frag or "#"
            return f"{m.group(2)}.html{frag}"
        return BLOB + rel + frag

    h = re.sub(r'href="([^"]*)"', lambda m: f'href="{cible(html.unescape(m.group(1)), False)}"', h)
    h = re.sub(r'src="([^"]*)"', lambda m: f'src="{cible(html.unescape(m.group(1)), True)}"', h)
    return h


def sans_lien_id(texte: str) -> str:
    """**[Q1.1](corrige.md#q1-1)** -> **Q1.1**, [PC.1.1](…) -> PC.1.1."""
    return re.sub(r"\[([A-Z]+(?:[-.]?[0-9A-Z]+)*)\]\((?:corrige|README)\.md#[^)]*\)", r"\1", texte)


# =============================================================================
# Découpage d'un fichier en sections et en items
# =============================================================================
def segments(texte: str) -> list[dict]:
    """[{kind: 'section'|'item'|'texte', ...}] en respectant les blocs de code."""
    texte = NAV_RE.sub("", texte)
    out: list[dict] = []
    cour: dict = {"kind": "texte", "lignes": []}
    fence = ""

    def pousser():
        if cour["kind"] != "texte" or any(x.strip() for x in cour["lignes"]):
            out.append(cour)

    for ligne in texte.split("\n"):
        f = FENCE_RE.match(ligne)
        if fence:
            cour["lignes"].append(ligne)
            if f and f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence) \
                    and not ligne.strip()[len(f.group(1)):].strip():
                fence = ""
            continue
        if f:
            fence = f.group(1)
            cour["lignes"].append(ligne)
            continue
        if ligne.startswith("# "):
            pousser()
            out.append({"kind": "titre", "texte": ligne[2:].strip()})
            cour = {"kind": "texte", "lignes": []}
            continue
        if ligne.startswith("## "):
            pousser()
            out.append({"kind": "section", "titre": ligne[3:].strip()})
            cour = {"kind": "texte", "lignes": []}
            continue
        m = ANCRE_RE.match(ligne)
        if m:
            pousser()
            cour = {"kind": "item", "id": m.group(2), "niveau": m.group(1) or "",
                    "tete": m.group(3), "lignes": []}
            continue
        if cour["kind"] == "item" and re.match(r"^---\s*$", ligne):
            pousser()
            cour = {"kind": "texte", "lignes": []}
            continue
        cour["lignes"].append(ligne)
    pousser()
    return out


def corriges(path: Path) -> dict[str, dict]:
    """id -> {'md': corps, 'rep': ['a', 'c'] | None}."""
    if not path.exists():
        return {}
    out: dict[str, dict] = {}
    for s in segments(path.read_text(encoding="utf-8")):
        if s["kind"] != "item":
            continue
        lignes = list(s["lignes"])
        tete = s["tete"]
        # titre en italique sur plusieurs lignes : « — *début … » puis « … fin.* »
        if re.search(r"— \*[^*]*$", tete):
            while lignes and lignes[0].strip():
                tete += " " + lignes.pop(0).strip()
                if tete.rstrip().endswith("*"):
                    break
        corps = "\n".join(lignes).strip("\n")
        rep = None
        titre = sans_lien_id(tete).strip()
        m = re.search(r"^\*\*R[ée]ponses? ?:\s*(.+?)\*\*", corps, re.M | re.S)
        if not m:   # variante : **[Q5.1](…) — b)** dans la ligne d'en-tête
            m = re.match(r"^\*\*[A-Z]+[0-9.]+\s*—\s*(.+?)\*\*", titre)
        if m:
            lettres = re.findall(r"(?:^|[\s,:(—])([a-h])\)", m.group(1))
            rep = sorted(set(lettres)) or None
        out[s["id"]] = {"md": corps, "rep": rep, "titre": titre}
    return out


def qcm(lignes: list[str]) -> tuple[str, list[tuple[str, str]], str]:
    """Sépare l'énoncé d'un QCM, ses options (lettre, texte) et la suite."""
    tronc: list[str] = []
    options: list[list[str]] = []
    suite: list[str] = []
    fence = ""
    for ligne in lignes:
        f = FENCE_RE.match(ligne)
        if fence or f:
            if fence and f and f.group(1)[0] == fence[0]:
                fence = ""
            elif not fence:
                fence = f.group(1)
            (suite if options else tronc).append(ligne)
            continue
        m = OPTION_RE.match(ligne)
        if m and not suite:
            options.append([m.group(1), m.group(2)])
            continue
        if options and not suite and re.match(r"^\s{2,}\S", ligne):
            options[-1][1] += " " + ligne.strip()
            continue
        if options and ligne.strip():
            suite.append(ligne)
        elif options:
            if suite:
                suite.append(ligne)
        else:
            tronc.append(ligne)
    return "\n".join(tronc), [(a, b) for a, b in options], "\n".join(suite)


# =============================================================================
# Pages
# =============================================================================
def esc(t: str) -> str:
    return html.escape(t, quote=True)


def bloc_aides(slug: str, code: str, liste: list[tuple[str, str]], src: Path) -> tuple[str, str]:
    """(HTML des aides, bouton) ; liste = [(titre, markdown)]."""
    if not liste:
        avertissements.append(f"{slug} {code} : aucune aide")
        return "", ""
    morceaux = []
    for n, (titre, md) in enumerate(liste, 1):
        t = f"Aide {n}" + (f" — {esc(titre)}" if titre else "")
        morceaux.append(f'<div class="aide" data-n="{n}" hidden><p class="aide-titre">{t}</p>'
                        f'{liens(rendu(md), src)}</div>')
    bouton = (f'<button type="button" class="aide-suivante" data-total="{len(liste)}">'
              f'Aide 1<span class="sur"> / {len(liste)}</span></button>')
    return f'<div class="aides">{"".join(morceaux)}</div>', bouton


def carte_item(slug: str, s: dict, corr: dict, src: Path, redigees: dict) -> tuple[str, dict]:
    ident = s["id"]
    genre = type_item(ident)
    tete = sans_lien_id(s["tete"]).strip()
    code_re = r"([A-Z]+(?:[-.]?[0-9A-Z]+)*)"
    m = re.match(r"^\*\*" + code_re + r"\*\*\s*(?:—\s*)?(.*)$", tete) \
        or re.match(r"^\*\*" + code_re + r" — (.*)\*\*$", tete) \
        or re.match(r"^" + code_re + r"\s*—\s*(.*)$", tete)
    if m:
        code, reste = m.group(1), m.group(2).strip()
    else:
        code, reste = ident.upper(), tete
    c = corr.get(ident)
    info = {"id": ident, "type": genre, "code": code}
    corrige_html = ""
    if c:
        corrige_html = liens(rendu((c["titre"] + "\n\n" if c["titre"] else "") + c["md"]),
                             src.with_name("corrige.md"))
    else:
        avertissements.append(f"{slug} {code} : pas de corrigé")
    titre_long = s["niveau"] != ""          # labs, BF, jalons : titre court en tête
    attrs = f'id="{esc(ident)}" class="item item-{genre}" data-id="{esc(ident)}" data-type="{genre}"'

    if genre == "qcm":
        tronc, options, suite = qcm(([reste] if reste else []) + s["lignes"])
        rep = c["rep"] if c else None
        if not options:
            avertissements.append(f"{slug} {code} : QCM sans options lisibles")
        if c and not rep:
            avertissements.append(f"{slug} {code} : réponse du QCM illisible dans le corrigé")
        info["rep"] = rep
        info["n"] = len(options)
        if ident in redigees:
            liste = [("", x) for x in redigees[ident]]
        else:
            liste = A.aides_qcm(ident, [o for o, _ in options], rep or [], c["md"] if c else "")
        aides_html, bouton_aide = bloc_aides(slug, code, liste, src.with_name("corrige.md"))
        info["na"] = len(liste)
        multi = bool(rep and len(rep) > 1)
        opts = []
        for lettre, texte in options:
            opts.append(
                f'<label class="option" data-l="{lettre}"><input type="checkbox" value="{lettre}">'
                f'<span class="lettre">{lettre})</span> <span class="texte">{liens(MD.renderInline(texte), src)}</span></label>')
        consigne = "plusieurs réponses" if multi else "une réponse"
        boutons = (f'{aides_html}<div class="actions"><button type="button" class="verifier"'
                   f'{"" if rep else " hidden"}>Vérifier</button>{bouton_aide}'
                   f'<button type="button" class="voir">Voir le corrigé</button>'
                   f'<span class="verdict" aria-live="polite"></span></div>')
        corps = (f'<div class="enonce">{liens(rendu(tronc), src)}</div>'
                 f'<div class="options" data-rep="{",".join(rep or [])}" '
                 f'aria-label="{consigne}">{"".join(opts)}</div>'
                 f'{liens(rendu(suite), src) if suite.strip() else ""}{boutons}')
        tete_html = (f'<header><span class="code">{esc(code)}</span>'
                     f'<span class="genre">{LIBELLES[genre]} · {consigne}</span>'
                     f'<span class="etat"></span></header>')
    else:
        enonce_md = "\n".join(s["lignes"])
        if not titre_long and reste:
            enonce_md = reste + "\n" + enonce_md
        titre = (f'<h3 class="titre-item">{liens(MD.renderInline(reste), src)}</h3>'
                 if titre_long and reste else "")
        check = ""
        if genre in ("lab", "jalon", "incident") and re.search(r"check_[A-Z0-9_]+\.sh", enonce_md):
            check = ('<label class="check-ok"><input type="checkbox" class="coche-check">'
                     ' le script <code>check</code> passe</label>')
        if ident in redigees:
            liste = [("", x) for x in redigees[ident]]
        else:
            liste = A.aides_ecrit(genre, c["md"] if c else "")
        aides_html, bouton_aide = bloc_aides(slug, code, liste, src.with_name("corrige.md"))
        info["na"] = len(liste)
        corps = (f'{titre}<div class="enonce">{liens(rendu(enonce_md), src)}</div>'
                 f'<label class="zone"><span>Ta réponse</span>'
                 f'<textarea rows="5" placeholder="{esc(PLACEHOLDER[genre])}"></textarea></label>'
                 f'{aides_html}<div class="actions">{check}{bouton_aide}'
                 f'<button type="button" class="voir">Voir le corrigé</button>'
                 f'<span class="verdict" aria-live="polite"></span></div>')
        tete_html = (f'<header><span class="code">{esc(code)}</span>'
                     f'<span class="genre">{LIBELLES[genre]}</span><span class="etat"></span></header>')
    corrige_bloc = (f'<div class="corrige" hidden><p class="corrige-titre">Corrigé de {esc(code)}</p>'
                    f'{corrige_html or "<p>Pas de corrigé pour cet item.</p>"}</div>')
    return f'<article {attrs}>{tete_html}{corps}{corrige_bloc}</article>', info


def cases_autoeval(h: str, compteur: list[int]) -> str:
    morceaux = re.split(r"(<pre.*?</pre>)", h, flags=re.S)
    for i in range(0, len(morceaux), 2):
        def case(_m):
            compteur[0] += 1
            return f'<input type="checkbox" class="ae" data-k="ae-{compteur[0]}" aria-label="case {compteur[0]}">'
        morceaux[i] = re.sub("☐", case, morceaux[i])
    return "".join(morceaux)


def page(slug: str, prec: str | None, suiv: str | None, partie: tuple) -> tuple[str, dict]:
    d = workbook.item_dir(slug)
    src = d / "README.md"
    corr = corriges(d / "corrige.md")
    redigees = A.redigees(d / "aides.md")
    court, long_ = workbook.title_of(slug)
    label = workbook.short_label(slug)
    corps: list[str] = []
    toc: list[tuple[str, str]] = []
    items: list[dict] = []
    compteur = [0]
    ouvert = False
    n_sec = 0
    for s in segments(src.read_text(encoding="utf-8")):
        if s["kind"] == "titre":
            continue
        if s["kind"] == "section":
            if ouvert:
                corps.append("</div></details>" if ouvert == "details" else "</section>")
            n_sec += 1
            sid = f"s{n_sec}"
            titre = s["titre"]
            toc.append((sid, titre))
            if any(k in titre for k in REPLIEES):
                ouvrir = " open" if "Objectifs" in titre else ""
                corps.append(f'<details class="section" id="{sid}"{ouvrir}><summary><h2>{MD.renderInline(titre)}</h2>'
                             f'</summary><div class="section-corps">')
                ouvert = "details"
            else:
                corps.append(f'<section class="section" id="{sid}"><h2>{MD.renderInline(titre)}</h2>')
                ouvert = "section"
            if "QCM" in titre:
                corps.append('<div class="barre-qcm"><button type="button" class="verifier-tout">'
                             'Vérifier tout le QCM</button><span class="score-qcm"></span></div>')
            continue
        if s["kind"] == "texte":
            h = liens(rendu("\n".join(s["lignes"])), src)
            corps.append(cases_autoeval(h, compteur))
            continue
        carte, info = carte_item(slug, s, corr, src, redigees)
        corps.append(carte)
        items.append(info)
    if ouvert:
        corps.append("</div></details>" if ouvert == "details" else "</section>")
    connus = {i["id"] for i in items}
    for k in redigees:
        if k not in connus:
            avertissements.append(f"{slug} aides.md : « {k} » ne correspond à aucun item")

    manifeste = {"page": slug, "label": label, "titre": court, "items": items, "ae": compteur[0]}
    nav = []
    nav.append(f'<a href="{prec}.html">← {workbook.short_label(prec)}</a>' if prec else "<span></span>")
    nav.append('<a href="index.html">Sommaire</a>')
    nav.append(f'<a href="{suiv}.html">{workbook.short_label(suiv)} →</a>' if suiv else "<span></span>")
    rel = ("projets/" if slug.startswith("P") else "modules/") + slug
    toc_html = "".join(f'<li><a href="#{a}">{MD.renderInline(t)}</a></li>' for a, t in toc)
    doc = f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(label)} — {esc(court)} · fiche interactive</title>
<link rel="stylesheet" href="assets/fiche.css">
</head>
<body data-page="{esc(slug)}">
<header class="haut">
  <nav class="fil">{"".join(nav)}</nav>
  <p class="partie">{esc(partie[0])} — {esc(partie[1])}</p>
  <h1>{esc(long_)}</h1>
  <div class="outils">
    <span class="progression" aria-live="polite"></span>
    <button type="button" id="exporter">Exporter mes réponses (.md)</button>
    <button type="button" id="effacer">Effacer cette fiche</button>
    <a href="{BLOB}{rel}/README.md">Énoncé sur GitHub</a>
    <a href="{BLOB}{rel}/corrige.md">Corrigé sur GitHub</a>
  </div>
  <p class="rappel">Tes réponses sont enregistrées dans ce navigateur, au fil de la frappe.
  Règle des 20 minutes : cherche avant d'ouvrir un corrigé.</p>
</header>
<div class="mise-en-page">
<nav class="sommaire"><ol>{toc_html}</ol></nav>
<main>
{"".join(corps)}
</main>
</div>
<footer class="bas"><nav class="fil">{"".join(nav)}</nav>
<p>Workbook Linux &amp; DevOps — contenu CC BY-NC-SA 4.0 — <a href="{DEPOT}">dépôt GitHub</a></p></footer>
<script type="application/json" id="manifeste">{json.dumps(manifeste, ensure_ascii=False)}</script>
<script src="assets/fiche.js"></script>
</body>
</html>
"""
    return doc, manifeste


def index(manifestes: list[dict]) -> str:
    par_slug = {m["page"]: m for m in manifestes}
    blocs = []
    for nom, titre, desc, slugs in workbook.PARTS:
        cartes = []
        for slug in slugs:
            m = par_slug[slug]
            nq = sum(1 for i in m["items"] if i["type"] == "qcm")
            nr = len(m["items"]) - nq
            temps = workbook.estimated_time(slug)
            cartes.append(
                f'<a class="carte" href="{slug}.html" data-page="{slug}">'
                f'<span class="carte-label">{esc(m["label"])}</span>'
                f'<span class="carte-titre">{esc(m["titre"])}</span>'
                f'<span class="carte-meta">{nq} QCM · {nr} réponses écrites'
                f'{" · " + esc(temps) if temps else ""}</span>'
                f'<span class="jauge"><span></span></span><span class="carte-etat"></span></a>')
        blocs.append(f'<section class="partie-idx"><h2>{esc(nom)} — {esc(titre)}</h2>'
                     f'<p>{esc(desc)}</p><div class="cartes">{"".join(cartes)}</div></section>')
    resume = {m["page"]: {"q": [i["id"] for i in m["items"] if i["type"] == "qcm"],
                          "r": [i["id"] for i in m["items"] if i["type"] != "qcm"]}
              for m in manifestes}
    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Workbook Linux &amp; DevOps — fiches interactives</title>
<link rel="stylesheet" href="assets/fiche.css">
</head>
<body data-page="index">
<header class="haut">
  <h1>Workbook Linux &amp; DevOps — fiches interactives</h1>
  <p>Une fiche par module et par projet : coche les QCM et vérifie-les, écris tes réponses
  dans les cadres, puis ouvre le corrigé. Tout reste dans ce navigateur ; exporte une
  sauvegarde pour changer d'appareil, et tes réponses en Markdown pour ton dossier
  <code>reponses/</code>.</p>
  <div class="outils">
    <span class="progression" aria-live="polite"></span>
    <button type="button" id="sauver">Sauvegarder toutes mes réponses (.json)</button>
    <label class="bouton">Restaurer une sauvegarde<input type="file" id="restaurer" accept=".json,application/json" hidden></label>
    <a href="{DEPOT}">Le dépôt GitHub</a>
  </div>
</header>
<main class="index">
{"".join(blocs)}
</main>
<footer class="bas"><p>Workbook Linux &amp; DevOps — contenu CC BY-NC-SA 4.0, scripts MIT —
<a href="{DEPOT}">dépôt GitHub</a></p></footer>
<script type="application/json" id="resume">{json.dumps(resume, ensure_ascii=False)}</script>
<script src="assets/fiche.js"></script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--sortie", default=str(ROOT / "_site"))
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()
    sortie = Path(a.sortie)
    if sortie.exists():
        shutil.rmtree(sortie)
    (sortie / "assets" / "figures").mkdir(parents=True)
    for f in (ROOT / "tools" / "fiches").iterdir():
        shutil.copy(f, sortie / "assets" / f.name)
    for f in (ROOT / "assets" / "figures").glob("*.svg"):
        shutil.copy(f, sortie / "assets" / "figures" / f.name)
    (sortie / ".nojekyll").write_text("")

    liste = workbook.items()
    manifestes = []
    for i, (partie, slug) in enumerate(liste):
        prec = liste[i - 1][1] if i > 0 else None
        suiv = liste[i + 1][1] if i + 1 < len(liste) else None
        doc, man = page(slug, prec, suiv, partie)
        (sortie / f"{slug}.html").write_text(doc, encoding="utf-8")
        manifestes.append(man)
    (sortie / "index.html").write_text(index(manifestes), encoding="utf-8")

    nq = sum(1 for m in manifestes for i in m["items"] if i["type"] == "qcm")
    nauto = sum(1 for m in manifestes for i in m["items"] if i["type"] == "qcm" and i.get("rep"))
    nr = sum(1 for m in manifestes for i in m["items"] if i["type"] != "qcm")
    na = sum(i.get("na", 0) for m in manifestes for i in m["items"])
    sans = sum(1 for m in manifestes for i in m["items"] if not i.get("na"))
    print(f"fiches : {len(manifestes)} pages, {nq} QCM ({nauto} corrigés automatiquement), "
          f"{nr} réponses écrites, {na} aides ({sans} items sans aide) -> {sortie}")
    for w in avertissements:
        print("  [avert] " + w)
    return 1 if (a.strict and avertissements) else 0


if __name__ == "__main__":
    sys.exit(main())
