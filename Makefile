# Makefile — Workbook Linux & DevOps
#   make check     cohérence du dépôt (identifiants, liens, schémas, scripts)
#   make lint      bash -n, shellcheck, py_compile
#   make nav       régénère la navigation et les tables du parcours
#   make figures   rend les schémas TikZ en SVG (assets/figures/)
#   make pdf       les trois volumes + le livret A5 du mémo (build/)
#   make memo | labs | solutions   un seul volume
#   make deps      dépendances Ubuntu 24.04 de la chaîne PDF
PYTHON ?= python3
BUILD   = build

.PHONY: help all check lint nav figures pdf memo labs solutions clean deps

help:
	@sed -n 's/^#   //p' Makefile

all: check lint pdf

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

figures:
	bash tools/render_figures.sh

pdf: check
	$(PYTHON) tools/pdf/build.py

memo:
	$(PYTHON) tools/pdf/build.py memo memo-a5

labs:
	$(PYTHON) tools/pdf/build.py labs

solutions:
	$(PYTHON) tools/pdf/build.py solutions

clean:
	rm -rf $(BUILD)
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +

deps:
	sudo apt-get install -y pandoc texlive-xetex texlive-latex-extra \
	  texlive-fonts-recommended texlive-pictures python3-pypdf poppler-utils \
	  shellcheck
