#!/usr/bin/env bash
# Compile un schéma seul : bash tex/figtest.sh nom  -> build/figtest/nom.pdf (+ png)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; out="$ROOT/build/figtest"; mkdir -p "$out"
cat > "$out/$name.tex" <<TEX
\documentclass[border=4pt]{standalone}
\usepackage{fontspec}
\setmainfont{SourceSans3}[Path=$ROOT/fonts/,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-It,BoldItalicFont=*-BoldIt]
\setsansfont{SourceSans3}[Path=$ROOT/fonts/,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-It,BoldItalicFont=*-BoldIt]
\setmonofont{JetBrainsMono}[Path=$ROOT/fonts/,Extension=.ttf,UprightFont=*-Regular,BoldFont=*-Bold,Scale=0.86]
\usepackage{xcolor,tikz,amssymb}
\usetikzlibrary{calc,positioning,shapes.geometric,shapes.misc,arrows.meta,fit,backgrounds,decorations.pathreplacing,patterns,shadows}
\definecolor{accent}{HTML}{1E4E79}\definecolor{accent2}{HTML}{0E8C8F}\definecolor{accentsoft}{HTML}{E9F0F7}
\definecolor{ink}{HTML}{1B2733}\definecolor{muted}{HTML}{62707E}\definecolor{line}{HTML}{D8DEE5}\definecolor{stripe}{HTML}{F1F4F7}
\definecolor{green}{HTML}{2A7D4F}\definecolor{greensoft}{HTML}{E8F5EC}\definecolor{red}{HTML}{B4373A}\definecolor{redsoft}{HTML}{FBEBEB}
\definecolor{violet}{HTML}{6B4C9F}\definecolor{violetsoft}{HTML}{F0EBF8}\definecolor{orange}{HTML}{BE6A12}\definecolor{orangesoft}{HTML}{FDF1E2}
\definecolor{greysoft}{HTML}{F2F4F6}\definecolor{codebg}{HTML}{F7F8FA}\definecolor{codeink}{HTML}{23405C}
\input{$ROOT/tex/wbfig.tex}
\begin{document}
\input{$ROOT/tex/figures/$name.tex}
\end{document}
TEX
( cd "$out" && xelatex -interaction=nonstopmode -halt-on-error "$name.tex" >"$name.log" 2>&1 ) \
  || { grep -E "^!|^l\.[0-9]" "$out/$name.log" | head -5; exit 1; }
pdftoppm -png -r 110 -singlefile "$out/$name.pdf" "$out/$name" >/dev/null 2>&1 || true
w=$(pdfinfo "$out/$name.pdf" | awk '/Page size/{print $3}')
echo "OK $name (largeur ${w%.*} pt ; max conseillé 480)"
