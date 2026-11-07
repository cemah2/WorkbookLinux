#!/usr/bin/env bash
# setup_M27.sh — prépare le terrain du module 27 (Python pour l'ops)
# À lancer SANS sudo, en tant que mathieu, sur lab-adm. Idempotent.
#
# Crée ~/lab27 : un venv, les jeux de données (access.log du module 05,
# fixture JSON de l'API Proxmox, archives datées, factures CSV), les fichiers
# de configuration des labs, et quelques scripts volontairement mal écrits
# pour les exercices guidés. Il n'écrit AUCUN des scripts demandés dans les
# labs : c'est le travail du module.
set -euo pipefail

if [ "$(id -u)" -eq 0 ] && [ "${M27_ALLOW_ROOT:-0}" != 1 ]; then
  echo "à lancer sans sudo, en tant que mathieu" >&2; exit 1
fi

BASE="$HOME/lab27"
WB="${WORKBOOK_DIR:-$HOME/workbook}"

echo "== Préparation du module 27 dans $BASE =="

mkdir -p "$BASE"/{bin,data,conf,fixtures,tests,rapports,var,casse}
mkdir -p "$BASE/data/sauvegardes"

# ---------------------------------------------------------------------
# 1. Outils système requis
# ---------------------------------------------------------------------
for outil in python3 pip3; do
  command -v "$outil" >/dev/null 2>&1 || {
    echo "$outil absent : sudo apt install -y python3-venv python3-pip pipx" \
      >&2; exit 1; }
done
python3 -c 'import venv, ensurepip' 2>/dev/null || {
  echo "python3-venv absent : sudo apt install -y python3-venv" >&2; exit 1; }
echo "  -> python : $(python3 --version)"

# ---------------------------------------------------------------------
# 2. Le venv du module et ses dépendances
# ---------------------------------------------------------------------
if [ ! -x "$BASE/venv/bin/python" ]; then
  echo "  -> création du venv $BASE/venv"
  python3 -m venv "$BASE/venv"
fi
# requirements.in : ce qu'on VEUT (bornes larges). requirements.txt : ce
# qu'on a INSTALLÉ (pip freeze, versions exactes). Les deux se committent.
cat > "$BASE/requirements.in" <<'EOF'
requests>=2.32,<3
PyYAML>=6.0,<7
prometheus-client>=0.21,<1
pytest>=8,<10
ruff>=0.5
mypy>=1.10
EOF
if "$BASE/venv/bin/python" -c 'import requests, yaml, pytest' 2>/dev/null; then
  echo "  -> dépendances déjà présentes dans le venv"
else
  echo "  -> installation des dépendances (réseau nécessaire)"
  "$BASE/venv/bin/pip" install --quiet --upgrade pip
  if "$BASE/venv/bin/pip" install --quiet -r "$BASE/requirements.in"; then
    "$BASE/venv/bin/pip" freeze > "$BASE/requirements.txt"
    echo "  -> requirements.txt figé ($(wc -l < "$BASE/requirements.txt") lignes)"
  else
    echo "  !! pip install a échoué : vérifie l'accès réseau puis relance" >&2
  fi
fi

# ---------------------------------------------------------------------
# 3. access.log : celui du module 05, régénéré si besoin
# ---------------------------------------------------------------------
if [ ! -f "$HOME/lab05/access.log" ]; then
  if [ -f "$WB/scripts/setup/setup_M05.sh" ]; then
    echo "  -> access.log absent : exécution de setup_M05.sh"
    bash "$WB/scripts/setup/setup_M05.sh" >/dev/null
  else
    echo "  !! $HOME/lab05/access.log absent et setup_M05.sh introuvable" >&2
    exit 1
  fi
fi
cp -f "$HOME/lab05/access.log" "$BASE/data/access.log"
cp -f "$HOME/lab05/access.log.1.gz" "$BASE/data/access.log.1.gz"
# un « gros » journal (~45 Mo) pour mesurer la lecture en flux
if [ ! -s "$BASE/data/gros.log" ]; then
  echo "  -> gros.log (30 x access.log)"
  for _ in $(seq 30); do cat "$BASE/data/access.log"; done > "$BASE/data/gros.log"
fi
echo "  -> access.log : $(wc -l < "$BASE/data/access.log") lignes"

# le pipeline awk de référence (module 05) pour la comparaison de L27.1
cat > "$BASE/bin/logstats.awk" <<'EOF'
#!/usr/bin/env bash
# logstats.awk — l'équivalent « module 05 » de logstats.py, pour comparer.
# usage : logstats.awk access.log
set -euo pipefail
f=${1:?fichier}
echo "== Top IP =="
awk '{print $1}' "$f" | sort | uniq -c | sort -rn | head -10
echo "== Codes HTTP =="
awk '{print $9}' "$f" | sort | uniq -c | sort -rn
echo "== p95 latence =="
awk '{print $NF}' "$f" | sort -n \
  | awk '{a[NR]=$1} END{k=int(NR*0.95); if (k<1) k=1; print a[k]}'
EOF
chmod 755 "$BASE/bin/logstats.awk"

# ---------------------------------------------------------------------
# 4. Fixture de l'API Proxmox (pour inventaire.py --fixture)
# ---------------------------------------------------------------------
cat > "$BASE/fixtures/proxmox-qemu.json" <<'EOF'
{
  "_commentaire": "Réponses figées de l'API Proxmox : GET /cluster/resources?type=vm puis GET /nodes/{node}/qemu/{vmid}/config.",
  "resources": [
    {"vmid": 9001, "name": "lab-adm", "node": "pve", "type": "qemu", "status": "running", "template": 0, "maxcpu": 2, "maxmem": 2147483648, "maxdisk": 21474836480, "tags": "adm;ubuntu", "uptime": 412233},
    {"vmid": 9002, "name": "lab-web", "node": "pve", "type": "qemu", "status": "running", "template": 0, "maxcpu": 2, "maxmem": 2147483648, "maxdisk": 21474836480, "tags": "web;ubuntu;prod", "uptime": 412201},
    {"vmid": 9003, "name": "lab-db", "node": "pve", "type": "qemu", "status": "running", "template": 0, "maxcpu": 2, "maxmem": 2147483648, "maxdisk": 32212254720, "tags": "db;ubuntu;prod", "uptime": 412190},
    {"vmid": 9004, "name": "lab-rhel", "node": "pve", "type": "qemu", "status": "running", "template": 0, "maxcpu": 2, "maxmem": 2147483648, "maxdisk": 21474836480, "tags": "rhel;rocky", "uptime": 412150},
    {"vmid": 9005, "name": "lab-ops", "node": "pve", "type": "qemu", "status": "running", "template": 0, "maxcpu": 2, "maxmem": 4294967296, "maxdisk": 42949672960, "tags": "ops;ubuntu;docker", "uptime": 412100},
    {"vmid": 9100, "name": "tpl-ubuntu-2404", "node": "pve", "type": "qemu", "status": "stopped", "template": 1, "maxcpu": 2, "maxmem": 2147483648, "maxdisk": 21474836480, "tags": "template;ubuntu", "uptime": 0},
    {"vmid": 9111, "name": "lab-web-old", "node": "pve", "type": "qemu", "status": "stopped", "template": 0, "maxcpu": 1, "maxmem": 1073741824, "maxdisk": 10737418240, "tags": "web;ubuntu", "uptime": 0},
    {"vmid": 9120, "name": "lab-sandbox", "node": "pve", "type": "qemu", "status": "running", "template": 0, "maxcpu": 1, "maxmem": 1073741824, "maxdisk": 10737418240, "uptime": 3600},
    {"vmid": 200, "name": "ct-dns", "node": "pve", "type": "lxc", "status": "running", "template": 0, "maxcpu": 1, "maxmem": 536870912, "maxdisk": 4294967296, "tags": "dns", "uptime": 900000}
  ],
  "configs": {
    "9001": {"name": "lab-adm", "cores": 2, "memory": 2048, "ipconfig0": "ip=10.10.10.10/24,gw=10.10.10.1", "net0": "virtio=BC:24:11:3A:10:10,bridge=vmbr1", "tags": "adm;ubuntu", "agent": "1"},
    "9002": {"name": "lab-web", "cores": 2, "memory": 2048, "ipconfig0": "ip=10.10.10.11/24,gw=10.10.10.1", "net0": "virtio=BC:24:11:3A:10:11,bridge=vmbr1", "tags": "web;ubuntu;prod", "agent": "1"},
    "9003": {"name": "lab-db", "cores": 2, "memory": 2048, "ipconfig0": "ip=10.10.10.12/24,gw=10.10.10.1", "net0": "virtio=BC:24:11:3A:10:12,bridge=vmbr1", "tags": "db;ubuntu;prod", "agent": "1"},
    "9004": {"name": "lab-rhel", "cores": 2, "memory": 2048, "ipconfig0": "ip=10.10.10.13/24,gw=10.10.10.1", "net0": "virtio=BC:24:11:3A:10:13,bridge=vmbr1", "tags": "rhel;rocky", "agent": "1"},
    "9005": {"name": "lab-ops", "cores": 2, "memory": 4096, "ipconfig0": "ip=10.10.10.14/24,gw=10.10.10.1", "net0": "virtio=BC:24:11:3A:10:14,bridge=vmbr1", "tags": "ops;ubuntu;docker", "agent": "1"},
    "9100": {"name": "tpl-ubuntu-2404", "cores": 2, "memory": 2048, "ipconfig0": "ip=dhcp", "template": 1, "tags": "template;ubuntu"},
    "9111": {"name": "lab-web-old", "cores": 1, "memory": 1024, "ipconfig0": "ip=10.10.10.21/24,gw=10.10.10.1", "tags": "web;ubuntu"},
    "9120": {"name": "lab-sandbox", "cores": 1, "memory": 1024, "ipconfig0": "ip=dhcp", "net0": "virtio=BC:24:11:3A:10:99,bridge=vmbr1"}
  }
}
EOF
echo "  -> fixtures/proxmox-qemu.json (9 ressources)"

# ---------------------------------------------------------------------
# 5. Archives datées pour la rétention GFS (L27.4)
# ---------------------------------------------------------------------
cat > "$BASE/bin/regen-sauvegardes.sh" <<EOF
#!/usr/bin/env bash
# regen-sauvegardes.sh — recrée les 120 archives datées (reset de L27.4)
set -euo pipefail
D="$BASE/data/sauvegardes"
mkdir -p "\$D"
rm -f "\$D"/*
for i in \$(seq 0 119); do
  d=\$(date -d "-\$i days" +%F)
  printf 'archive %s\\n' "\$d" > "\$D/factura-\$d.tar.gz"
done
printf 'ne pas toucher\\n' > "\$D/export final.tar.gz"
printf 'autre prefixe\\n' > "\$D/gitea-\$(date +%F).tar.gz"
echo "sauvegardes régénérées dans \$D"
EOF
chmod 755 "$BASE/bin/regen-sauvegardes.sh"
bash "$BASE/bin/regen-sauvegardes.sh" >/dev/null
echo "  -> data/sauvegardes : 120 archives datées + 2 intrus"

# ---------------------------------------------------------------------
# 6. Factures (source de l'exporter L27.5) et fichiers de configuration
# ---------------------------------------------------------------------
python3 - "$BASE/data/factures.csv" <<'EOF'
import csv, random, sys
random.seed(2026)
clients = ["ACME", "Globex", "Initech", "Umbrella", "Wonka", "Stark"]
statuts = ["brouillon", "emise", "emise", "payee", "payee", "payee", "annulee"]
with open(sys.argv[1], "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter=";")
    w.writerow(["id", "client", "montant", "statut", "date"])
    for i in range(1, 401):
        w.writerow([i, random.choice(clients), f"{random.uniform(40, 2500):.2f}",
                    random.choice(statuts), f"2026-{random.randint(1, 8):02d}-{random.randint(1, 28):02d}"])
EOF
echo "  -> data/factures.csv (400 factures)"

cat > "$BASE/conf/exporter.toml" <<EOF
# configuration de factura_exporter.py (L27.5)
[http]
port = 9105

[source]
csv = "$BASE/data/factures.csv"
# dsn = "host=10.10.10.12 dbname=factura user=factura password=..."
EOF

cat > "$BASE/conf/sante.yaml" <<'EOF'
# configuration de sante.py (L27.3) — adapte les cibles à ton lab
timeout: 3
verifications:
  - nom: ssh lab-web
    type: tcp
    hote: 10.10.10.11
    port: 22
  - nom: site boutique
    type: http
    url: http://10.10.10.11/
    attendu: 200
  - nom: gitea
    type: http
    url: http://10.10.10.14:3000/api/v1/version
    contient: version
  - nom: prometheus
    type: http
    url: http://10.10.10.14:9090/-/healthy
  - nom: certificat lab-web
    type: tls
    hote: 10.10.10.11
    port: 443
    jours_min: 14
  - nom: racine
    type: disque
    chemin: /
    pct_max: 90
  - nom: unite ssh
    type: commande
    argv: ["systemctl", "is-active", "ssh"]
EOF

# un fichier en latin-1 pour l'exercice sur les encodages
printf 'id;client;ville\n1;Soci\xe9t\xe9 G\xe9n\xe9rale;Orl\xe9ans\n2;M\xfcller;Z\xfcrich\n' \
  > "$BASE/data/clients-latin1.csv"
# un fichier « inventaire » CSV avec BOM UTF-8, cadeau d'Excel
printf '\xef\xbb\xbfhote;ip;env\nlab-web;10.10.10.11;prod\nlab-db;10.10.10.12;prod\n' \
  > "$BASE/data/inventaire-excel.csv"

# ---------------------------------------------------------------------
# 7. Scripts volontairement mal écrits (exercices guidés)
# ---------------------------------------------------------------------
cat > "$BASE/casse/mutable.py" <<'EOF'
"""E27 — pourquoi la deuxième liste contient-elle la première ?"""


def ajouter_hote(nom, liste=[]):
    liste.append(nom)
    return liste


prod = ajouter_hote("lab-web")
recette = ajouter_hote("lab-db")
print("prod    :", prod)
print("recette :", recette)
EOF

cat > "$BASE/casse/purge.py" <<'EOF'
"""E27 — purge des fichiers temporaires d'un répertoire passé en argument."""
import os
import sys

rep = sys.argv[1]
os.system("rm -f " + rep + "/*.tmp")
print("purge faite")
EOF

cat > "$BASE/casse/lecture.py" <<'EOF'
"""E27 — lit un CSV de clients et affiche les villes."""
import sys

for ligne in open(sys.argv[1]).read().split("\n"):
    if ligne:
        print(ligne.split(";")[2])
EOF

cat > "$BASE/casse/stock.py" <<'EOF'
"""E27 — un service qui tourne sans rien dire : où sont les messages ?"""
import time

def traiter(lot):
    print("traitement du lot", lot)
    if lot % 3 == 0:
        print("ERREUR lot", lot, "corrompu")
    time.sleep(0.2)

for lot in range(1, 7):
    traiter(lot)
EOF

mkdir -p "$BASE/casse/tmp"
touch "$BASE/casse/tmp/a.tmp" "$BASE/casse/tmp/important.txt"

# ---------------------------------------------------------------------
# 8. Squelette de projet pour la qualité (L27.4 et D27)
# ---------------------------------------------------------------------
cat > "$BASE/pyproject.example.toml" <<'EOF'
# Exemple minimal : copie-le dans ton projet et adapte name/scripts.
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "monoutil"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["requests>=2.32,<3", "PyYAML>=6,<7"]

[project.optional-dependencies]
dev = ["pytest>=8", "ruff>=0.5", "mypy>=1.10"]

[project.scripts]
monoutil = "monoutil.cli:main"

[tool.setuptools.packages.find]
where = ["src"]

[tool.ruff]
line-length = 79
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "SIM"]

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

cat > "$BASE/.pre-commit-config.yaml" <<'EOF'
# pre-commit install ; puis chaque commit lance ruff (lint + format)
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
EOF

cat <<EOF

== Terminé ==
  venv          : $BASE/venv   (source $BASE/venv/bin/activate)
  données       : $BASE/data/{access.log,gros.log,factures.csv,sauvegardes/}
  fixture       : $BASE/fixtures/proxmox-qemu.json
  configuration : $BASE/conf/{sante.yaml,exporter.toml}
  à casser      : $BASE/casse/*.py
Vérifie : $BASE/venv/bin/python -c 'import requests, yaml; print("ok")'
EOF
