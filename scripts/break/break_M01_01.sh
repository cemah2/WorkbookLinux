#!/usr/bin/env bash
# break_M01_01.sh — panne BF1.1
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

CIBLE="${SUDO_USER:-mathieu}"
HOME_CIBLE=$(getent passwd "$CIBLE" | cut -d: -f6)
BRC="$HOME_CIBLE/.bashrc"
SAUV=/root/.breakfix-backup
MARQUE='# BF1.1'

mkdir -p "$SAUV"
[ -f "$BRC" ] || { echo "pas de $BRC" >&2; exit 1; }

if ! [ -f "$SAUV/bashrc.M01_01" ]; then
  cp -- "$BRC" "$SAUV/bashrc.M01_01"
fi

if ! grep -qF "$MARQUE" "$BRC"; then
  cat >> "$BRC" <<EOF

$MARQUE outillage interne
export PATH=/opt/outils-maison/bin
EOF
fi
chown "$CIBLE": "$BRC"

cat <<'EOF'

Symptôme attendu : à la prochaine connexion SSH, toute commande répond
"bash: <commande>: command not found", y compris sudo, vim et nano.
Le prompt, lui, répond toujours.
EOF
