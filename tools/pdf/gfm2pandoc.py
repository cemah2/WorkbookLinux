"""Markdown GitHub du dépôt -> Markdown pandoc attendu par la chaîne PDF.

Inverse exact des conventions de format (voir CONVENTIONS.md) :

- blocs de navigation <!-- nav:début --> ... <!-- nav:fin --> : supprimés ;
- alertes GitHub dont la 1re ligne est un libellé connu -> blocs ::: classe ;
- <!-- repondre: N --> -> ::: repondre (zone de réponse du PDF d'énoncés) ;
- image centrée assets/figures/NOM.svg + légende « *Figure — ...* » -> @fig(NOM): ... ;
- ancres <a id="..."></a> et liens d'identifiants [Q7.1](corrige.md#q7-1) -> Q7.1.
"""
import re
import sys

LABELS = {
    ("NOTE", "Objectifs"): "objectif",
    ("TIP", "Astuce"): "astuce",
    ("CAUTION", "Attention"): "attention",
    ("IMPORTANT", "Variante Rocky / RHEL"): "rhel",
    (None, "Contexte"): "contexte",
    ("NOTE", "Pourquoi"): "pourquoi",
    ("WARNING", "Piège"): "piege",
    ("TIP", "Critère de succès"): "check",
    ("NOTE", "Note"): "note",
}

FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
NAV = re.compile(r"<!-- nav:début -->.*?<!-- nav:fin -->\n?", re.S)
FIG = re.compile(r'^<p align="center"><img src="(?:\.\./)*assets/figures/([\w-]+)\.svg"[^>]*></p>$')
CAP = re.compile(r"^\*Figure — (.*)\*$")
REP = re.compile(r"^<!-- repondre: (\d+) -->$")
ANCHOR = re.compile(r'<a id="[^"]*"></a>')
IDLINK = re.compile(r"\[([^\]]+)\]\((?:corrige|README)\.md#[^)]*\)")


def convert(text):
    text = NAV.sub("", text)
    lines = text.split("\n")
    out = []
    i = 0
    inf = False
    n = len(lines)
    while i < n:
        l = lines[i]
        if FENCE.match(l) and not l.startswith(">"):
            inf = not inf
            out.append(l)
            i += 1
            continue
        if inf:
            out.append(l)
            i += 1
            continue
        # alerte / encadré
        m = re.match(r"^> \[!(\w+)\]\s*$", l)
        typ, lab_line = None, None
        if m and i + 1 < n:
            typ, lab_line = m.group(1), lines[i + 1]
            start = i + 2
        elif l.startswith("> **"):
            lab_line = l
            start = i + 1
        if lab_line is not None:
            ml = re.match(r"^> \*\*(.+)\*\*\s*$", lab_line)
            cls = LABELS.get((typ, ml.group(1))) if ml else None
            if cls:
                j = start
                if j < n and lines[j].strip() == ">":
                    j += 1
                body = []
                while j < n and lines[j].startswith(">"):
                    b = lines[j]
                    body.append(b[2:] if b.startswith("> ") else b[1:])
                    j += 1
                out.append(f"::: {cls}")
                out.extend(body)
                out.append(":::")
                i = j
                continue
        m = REP.match(l)
        if m:
            out.extend(["::: repondre", f"lignes: {m.group(1)}", ":::"])
            i += 1
            continue
        m = FIG.match(l)
        if m:
            j = i + 1
            while j < n and not lines[j].strip():
                j += 1
            mc = CAP.match(lines[j]) if j < n else None
            if mc:
                out.append(f"@fig({m.group(1)}): {mc.group(1)}")
                i = j + 1
                continue
        l = ANCHOR.sub("", l)
        l = IDLINK.sub(r"\1", l)
        out.append(l)
        i += 1
    return "\n".join(out)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        sys.stdout.write(convert(open(p, encoding="utf-8").read()))
