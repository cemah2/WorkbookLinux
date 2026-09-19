#!/usr/bin/env python3
"""Renumérotation des modules (ancien -> nouveau) dans les sources, scripts et noms de fichiers."""
import re, sys, os, glob, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAP = {9: 10, 10: 11, 11: 12, 12: 14, 13: 16, 14: 17, 15: 18, 16: 19,
       17: 21, 18: 22, 19: 23, 20: 24, 21: 25, 22: 26, 23: 27}


def m(n, pad=None):
    v = MAP.get(int(n), int(n))
    return f"{v:02d}" if (pad or (len(str(n)) == 2 and str(n).startswith("0"))) else str(v)


def renum(text):
    # A. identifiants Q/QO/E/L/BF avec point
    text = re.sub(r'\b(QO|Q|E|L|BF)(\d{1,2})\.(\d+)\b', lambda x: f"{x.group(1)}{m(x.group(2))}.{x.group(3)}", text)
    # B. défis D<n>
    text = re.sub(r'\bD(\d{1,2})\b(?!\.\d)', lambda x: f"D{m(x.group(1))}", text)
    # C. M<nn> (scripts, sauvegardes, dossiers reponses/M07)
    text = re.sub(r'(?<![A-Za-z0-9])M(\d{2})(?![A-Za-z0-9])', lambda x: f"M{m(x.group(1), True)}", text)
    # D. lab<nn>
    text = re.sub(r'\blab(\d{2})(?![A-Za-z0-9])', lambda x: f"lab{m(x.group(1), True)}", text)
    # E. titres de section "## 13.3", "### 13.3.1", "section 16.5", "§ 16.2"
    text = re.sub(r'^(#{1,6} )(\d{1,2})\.(\d+)', lambda x: f"{x.group(1)}{m(x.group(2))}.{x.group(3)}", text, flags=re.M)
    text = re.sub(r'(\bsection|§)( ?)(\d{1,2})\.(\d+)', lambda x: f"{x.group(1)}{x.group(2)}{m(x.group(3))}.{x.group(4)}", text)
    # mémo : "## 13 · "
    text = re.sub(r'^(## )(\d{2})( · )', lambda x: f"{x.group(1)}{m(x.group(2), True)}{x.group(3)}", text, flags=re.M)
    # F. prose : "module 16", "Module 16", "modules 1 à 19", "modules 21, 22 et 25"
    def prose(x):
        head, rest = x.group(1), x.group(2)
        rest = re.sub(r'\d{1,2}', lambda y: m(y.group(0)), rest)
        return head + rest
    text = re.sub(r'\b([Mm]odules?\s+)((?:\d{1,2})(?:\s*(?:,|et|à|/|–|-|ou)\s*\d{1,2})*)\b', prose, text)
    return text


def rename_paths():
    def newname(name):
        r = re.match(r'^(\d{2})(-.*\.md)$', name)
        if r: return f"{m(r.group(1), True)}{r.group(2)}"
        r = re.match(r'^(setup|check|break)_M(\d{2})(.*)$', name)
        if r: return f"{r.group(1)}_M{m(r.group(2), True)}{r.group(3)}"
        r = re.match(r'^m(\d{2})$', name)
        if r: return f"m{m(r.group(1), True)}"
        return name
    for d in ["src/labs", "src/solutions", "scripts/setup", "scripts/check", "scripts/break"]:
        p = ROOT / d
        pairs = [(f, newname(f.name)) for f in p.iterdir()]
        pairs = [(f, n) for f, n in pairs if n != f.name]
        # renommer via un nom temporaire pour éviter les collisions
        for f, n in pairs: f.rename(f.with_name("__" + n))
        for f, n in pairs: (f.with_name("__" + n)).rename(f.with_name(n))


def main():
    files = []
    for pat in ["src/*.md", "src/labs/*.md", "src/solutions/*.md", "scripts/**/*"]:
        files += [Path(p) for p in glob.glob(str(ROOT / pat), recursive=True)]
    changed = 0
    for f in files:
        if not f.is_file(): continue
        try:
            s = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        t = renum(s)
        if t != s:
            f.write_text(t, encoding="utf-8"); changed += 1
    rename_paths()
    print("fichiers modifiés :", changed)


if __name__ == "__main__":
    main()
