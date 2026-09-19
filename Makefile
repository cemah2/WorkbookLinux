# Makefile — workbook Linux & DevOps
# Cibles : pdf (les 3 volumes), memo, labs, solutions, check-ids, clean,
#          zip-scripts. Dépendances : pandoc, texlive-xetex,
#          texlive-latex-extra, texlive-fonts-recommended, fonts-dejavu.
PYTHON ?= python3
BUILD   = build

.PHONY: all pdf memo labs solutions check-ids clean zip-scripts deps

all: pdf

pdf: check-ids
	$(PYTHON) build.py

memo:
	$(PYTHON) build.py memo

labs:
	$(PYTHON) build.py labs

solutions:
	$(PYTHON) build.py solutions

# Chaque identifiant d'énoncé (Q, QO, E, L, BF, D) doit avoir son corrigé.
check-ids:
	$(PYTHON) scripts/lib/check_ids.py

clean:
	rm -rf $(BUILD)

# Le zip à copier sur les VM (chapitre 0.4) : les scripts seuls.
zip-scripts:
	mkdir -p $(BUILD)
	rm -f $(BUILD)/workbook-scripts.zip
	zip -qr $(BUILD)/workbook-scripts.zip scripts -x '*/__pycache__/*'
	@ls -l $(BUILD)/workbook-scripts.zip

# Ubuntu 24.04 : les paquets de la chaîne PDF.
deps:
	sudo apt-get install -y pandoc texlive-xetex texlive-latex-extra \
	  texlive-fonts-recommended fonts-dejavu python3 zip
