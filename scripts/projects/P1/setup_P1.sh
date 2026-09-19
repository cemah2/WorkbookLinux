#!/usr/bin/env bash
# setup_P1.sh — dépose les sources du projet A (Factura) selon le hostname.
# À lancer avec sudo, sur CHAQUE VM du projet (lab-adm, lab-web, lab-db,
# lab-ops), depuis le dépôt du workbook :
#     sudo bash ~/workbook/scripts/projects/P1/setup_P1.sh
# Idempotent. Ne crée ni compte, ni unité, ni configuration : c'est le
# travail des jalons. Il installe seulement les paquets de base communs
# (curl, jq, python3, openssl) et copie les sources dans
# /usr/local/src/factura/.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/app"
DST=/usr/local/src/factura
HOST="$(hostname -s)"
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"

[ -d "$SRC" ] || {
  echo "sources introuvables : $SRC (le dépôt workbook est-il complet ?)" >&2
  exit 1; }

echo "== Préparation du projet A (Factura) sur $HOST =="

# ---------------------------------------------------------------------
# 1. Paquets de base communs (les paquets métier sont l'affaire des jalons)
# ---------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq curl jq python3 openssl rsync >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q curl jq python3 openssl rsync >/dev/null
fi

# ---------------------------------------------------------------------
# 2. Dépôt des sources selon le rôle de la VM
# ---------------------------------------------------------------------
install -d -m 0755 "$DST"
copy() {                     # copy <sous-dossier ou fichier>
  local item="$1"
  if [ -d "$SRC/$item" ]; then
    install -d -m 0755 "$DST/$item"
    cp -a "$SRC/$item/." "$DST/$item/"
  else
    cp -a "$SRC/$item" "$DST/$item"
  fi
  echo "   $DST/$item"
}

copy README.md
copy tools
case "$HOST" in
  lab-web)
    copy api; copy worker; copy www; copy requirements.txt ;;
  lab-db)
    copy sql ;;
  lab-ops)
    : ;;                      # tools suffit : webhook et smoke test
  lab-adm|*)
    copy api; copy worker; copy www; copy sql; copy requirements.txt ;;
esac
chmod 0755 "$DST"/tools/*.sh "$DST"/tools/*.py
find "$DST" -type f -name '*.py' -not -path '*/tools/*' \
  -exec chmod 0644 {} +
chown -R root:root "$DST"

# ---------------------------------------------------------------------
# 3. Espace de travail de l'apprenant (journal de bord, copies de conf)
# ---------------------------------------------------------------------
if [ -n "$LAB_HOME" ]; then
  install -d -o "$LAB_USER" -g "$LAB_USER" "$LAB_HOME/P1" \
    "$LAB_HOME/P1/conf" "$LAB_HOME/P1/incidents"
  if [ ! -f "$LAB_HOME/P1/journal.md" ]; then
    cat > "$LAB_HOME/P1/journal.md" <<EOF
# Projet A — Factura : journal de bord ($HOST)

| Date | Jalon | Ce que j'ai fait | Ce qui a coincé |
|---|---|---|---|
EOF
    chown "$LAB_USER":"$LAB_USER" "$LAB_HOME/P1/journal.md"
  fi
fi

# ---------------------------------------------------------------------
# 4. Marqueur et récapitulatif
# ---------------------------------------------------------------------
install -d -m 0755 /var/lib/factura-setup
date -Is > /var/lib/factura-setup/P1-$HOST
sha256sum "$DST"/api/*.py "$DST"/worker/*.py 2>/dev/null \
  > /var/lib/factura-setup/P1-sources.sha256 || true

cat <<EOF

Sources déposées dans $DST. Rien d'autre n'a été fait : pas de compte,
pas de service, pas de configuration. Commence par le jalon PA.1.
Journal de bord : $LAB_HOME/P1/journal.md
Vérifications   : bash $HERE/check_PA_01.sh (puis 02, 03 ...)
EOF
