#!/usr/bin/env python3
"""Garantit une ligne vide avant et après chaque règle horizontale '---' (hors blocs de code)."""
import re, glob
n = 0
for f in glob.glob('src/*.md') + glob.glob('src/labs/*.md') + glob.glob('src/solutions/*.md') + glob.glob('src/memo-parts/*.md'):
    s = open(f, encoding='utf-8').read()
    lines = s.split('\n'); out = []; fence = False; ch = 0
    for i, l in enumerate(lines):
        if re.match(r'^\s*(```|~~~)', l): fence = not fence
        if not fence and re.match(r'^-{3,}\s*$', l):
            if out and out[-1].strip() != '': out.append(''); ch += 1
            out.append(l)
            if i + 1 < len(lines) and lines[i + 1].strip() != '': out.append(''); ch += 1
        else:
            out.append(l)
    if ch:
        open(f, 'w', encoding='utf-8').write('\n'.join(out)); n += ch; print(f, ch)
print('corrections :', n)
