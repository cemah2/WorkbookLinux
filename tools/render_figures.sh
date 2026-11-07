#!/usr/bin/env bash
# render_figures.sh — compile les schémas TikZ (tools/pdf/tex/figures/*.tex)
# en SVG pour GitHub (assets/figures/*.svg).
#
#   bash tools/render_figures.sh              # tous les schémas
#   bash tools/render_figures.sh nom1 nom2    # seulement ceux-là
#
# Dépendances : xelatex (texlive-xetex, texlive-latex-extra, texlive-pictures)
# et pdftocairo (poppler-utils). Les polices viennent de tools/pdf/fonts/.
# Le SVG reçoit un fond blanc : sans lui, le texte sombre des schémas est
# illisible avec le thème sombre de GitHub.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIG="$ROOT/tools/pdf/tex/figures"
OUT="$ROOT/assets/figures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

if [ "$#" -gt 0 ]; then
  names=("$@")
else
  mapfile -t names < <(cd "$FIG" && ls -1 *.tex | sed 's/\.tex$//')
fi

ok=0; ko=0
for name in "${names[@]}"; do
  cat > "$WORK/$name.tex" <<TEX
\documentclass[border=6pt]{standalone}
\usepackage{fontspec}
\setmainfont{SourceSans3}[Path=$ROOT/tools/pdf/fonts/,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-It,BoldItalicFont=*-BoldIt]
\setsansfont{SourceSans3}[Path=$ROOT/tools/pdf/fonts/,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-It,BoldItalicFont=*-BoldIt]
\setmonofont{JetBrainsMono}[Path=$ROOT/tools/pdf/fonts/,Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-Italic,Scale=0.86]
\usepackage{xcolor,tikz,amssymb}
\usetikzlibrary{calc,positioning,shapes.geometric,shapes.misc,arrows.meta,fit,backgrounds,decorations.pathreplacing,patterns,shadows}
\definecolor{accent}{HTML}{1E4E79}\definecolor{accent2}{HTML}{0E8C8F}\definecolor{accentsoft}{HTML}{E9F0F7}
\definecolor{ink}{HTML}{1B2733}\definecolor{muted}{HTML}{62707E}\definecolor{line}{HTML}{D8DEE5}\definecolor{stripe}{HTML}{F1F4F7}
\definecolor{green}{HTML}{2A7D4F}\definecolor{greensoft}{HTML}{E8F5EC}\definecolor{red}{HTML}{B4373A}\definecolor{redsoft}{HTML}{FBEBEB}
\definecolor{violet}{HTML}{6B4C9F}\definecolor{violetsoft}{HTML}{F0EBF8}\definecolor{orange}{HTML}{BE6A12}\definecolor{orangesoft}{HTML}{FDF1E2}
\definecolor{greysoft}{HTML}{F2F4F6}\definecolor{codebg}{HTML}{F7F8FA}\definecolor{codeink}{HTML}{23405C}
\input{$ROOT/tools/pdf/tex/wbfig.tex}
\begin{document}
\input{$FIG/$name.tex}
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
    ok=$((ok + 1))
  else
    echo "ÉCHEC $name :" >&2
    grep -E '^!|^l\.[0-9]' "$WORK/$name.log" | head -5 >&2
    ko=$((ko + 1))
  fi
done
echo "schémas : $ok rendus, $ko en échec -> $OUT"
[ "$ko" -eq 0 ]
