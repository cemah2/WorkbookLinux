# Makefile — Workbook Linux & DevOps
#   make check     cohérence du dépôt (identifiants, liens, schémas, scripts)
#   make lint      bash -n, shellcheck, py_compile
#   make nav       régénère la navigation et les tables du parcours
#   make mermaid   valide les diagrammes Mermaid (Node.js requis)
#   make fiches    génère les fiches interactives dans _site/ (ouvre _site/index.html)
#   make figures   régénère les SVG des schémas TikZ existants (rarement utile)
#   make deps      outils des contrôles (shellcheck, python3)
PYTHON ?= python3

.PHONY: help all check lint nav mermaid fiches figures clean deps

help:
	@sed -n 's/^#   //p' Makefile

all: nav check lint

check:
	$(PYTHON) tools/check_repo.py

lint:
	find scripts tools -name '*.sh' -print0 | xargs -0 -n1 bash -n
	@if command -v shellcheck >/dev/null; then \
	  find scripts tools -name '*.sh' -print0 | xargs -0 shellcheck -S error; \
	else echo "shellcheck absent : apt install shellcheck"; fi
	find scripts tools -name '*.py' -print0 | xargs -0 $(PYTHON) -m py_compile

nav:
	$(PYTHON) tools/gen_nav.py

mermaid:
	@[ -d node_modules/mermaid ] || npm install --no-save --no-audit --no-fund --silent mermaid@11 jsdom
	node tools/check_mermaid.mjs $$(git ls-files '*.md')

fiches:
	@$(PYTHON) -c 'import markdown_it' 2>/dev/null || $(PYTHON) -m pip install --user markdown-it-py
	$(PYTHON) tools/gen_fiches.py --strict --sortie _site

figures:
	bash tools/render_figures.sh

clean:
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
	rm -rf node_modules _site

deps:
	sudo apt-get install -y shellcheck python3 python3-markdown-it
