#!/usr/bin/env bash
# render_figures.sh — régénère les schémas SVG (assets/figures/*.svg) à partir
# de leurs sources TikZ (assets/figures/src/*.tex).
#
#   bash tools/render_figures.sh              # tous les schémas
#   bash tools/render_figures.sh nom1 nom2    # seulement ceux-là
#
# À n'utiliser que pour MODIFIER un schéma existant : les nouveaux schémas
# s'écrivent en Mermaid, directement dans le Markdown (CONVENTIONS.md §5).
#
# Dépendances : xelatex (texlive-xetex, texlive-latex-extra, texlive-pictures)
# et pdftocairo (poppler-utils). Les polices sont dans assets/figures/src/fonts/.
# Le SVG reçoit un fond blanc : sans lui, le texte sombre des schémas est
# illisible avec le thème sombre de GitHub.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/figures/src"
FONTS="$SRC/fonts/"
OUT="$ROOT/assets/figures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for outil in xelatex pdftocairo; do
  command -v "$outil" >/dev/null || {
    echo "$outil absent : sudo apt install texlive-xetex texlive-latex-extra" \
         "texlive-pictures poppler-utils" >&2; exit 1; }
done

if [ "$#" -gt 0 ]; then
  names=("$@")
else
  mapfile -t names < <(cd "$SRC" && ls -1 [!_]*.tex | sed 's/\.tex$//')
fi

ok=0; ko=0
for name in "${names[@]}"; do
  [ -f "$SRC/$name.tex" ] || { echo "source absente : $SRC/$name.tex" >&2; ko=$((ko + 1)); continue; }
  cat > "$WORK/$name.tex" <<TEX
\documentclass[border=6pt]{standalone}
\usepackage{fontspec}
\setmainfont{SourceSans3}[Path=$FONTS,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-It,BoldItalicFont=*-BoldIt]
\setsansfont{SourceSans3}[Path=$FONTS,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-It,BoldItalicFont=*-BoldIt]
\setmonofont{JetBrainsMono}[Path=$FONTS,Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-Italic,Scale=0.86]
\usepackage{xcolor,tikz,amssymb}
\usetikzlibrary{calc,positioning,shapes.geometric,shapes.misc,arrows.meta,fit,backgrounds,decorations.pathreplacing,patterns,shadows}
\definecolor{accent}{HTML}{1E4E79}\definecolor{accent2}{HTML}{0E8C8F}\definecolor{accentsoft}{HTML}{E9F0F7}
\definecolor{ink}{HTML}{1B2733}\definecolor{muted}{HTML}{62707E}\definecolor{line}{HTML}{D8DEE5}\definecolor{stripe}{HTML}{F1F4F7}
\definecolor{green}{HTML}{2A7D4F}\definecolor{greensoft}{HTML}{E8F5EC}\definecolor{red}{HTML}{B4373A}\definecolor{redsoft}{HTML}{FBEBEB}
\definecolor{violet}{HTML}{6B4C9F}\definecolor{violetsoft}{HTML}{F0EBF8}\definecolor{orange}{HTML}{BE6A12}\definecolor{orangesoft}{HTML}{FDF1E2}
\definecolor{greysoft}{HTML}{F2F4F6}\definecolor{codebg}{HTML}{F7F8FA}\definecolor{codeink}{HTML}{23405C}
\input{$SRC/_styles.tex}
\begin{document}
\input{$SRC/$name.tex}
\end{document}
TEX
  if ( cd "$WORK" && xelatex -interaction=nonstopmode -halt-on-error "$name.tex" > "$name.log" 2>&1 ); then
    pdftocairo -svg "$WORK/$name.pdf" "$WORK/$name.svg"
    # fond blanc juste après la balise <svg ...>
    python3 - "$WORK/$name.svg" "$OUT/$name.svg" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<svg[^>]*>", s)
s = s[:m.end()] + '\n<rect width="100%" height="100%" fill="#ffffff"/>' + s[m.end():]
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
    largeur=$(sed -n 's/.*<svg[^>]* width="\([0-9.]*\)\(pt\)\{0,1\}".*/\1/p' "$OUT/$name.svg" | head -1)
    echo "OK $name (largeur ${largeur%.*} pt ; 480 au plus pour rester lisible)"
    ok=$((ok + 1))
  else
    echo "ÉCHEC $name :" >&2
    grep -E '^!|^l\.[0-9]' "$WORK/$name.log" | head -5 >&2
    ko=$((ko + 1))
  fi
done
echo "schémas : $ok rendus, $ko en échec -> $OUT"
[ "$ko" -eq 0 ]
