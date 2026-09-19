#!/usr/bin/env bash
# break_M03_03.sh — panne BF3.3 (resolv.conf immuable : root lui-même bloqué)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

CIBLE=/etc/resolv.conf
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

# --- sauvegarde du contenu et de l'état avant de casser -----------------
if [ -e "$CIBLE" ] && [ ! -e "$SAUV/M03_03.resolv.conf" ]; then
  # cp échoue si déjà immuable d'un run précédent : on protège
  chattr -i "$CIBLE" 2>/dev/null || true
  cp -a "$CIBLE" "$SAUV/M03_03.resolv.conf" 2>/dev/null || true
fi
lsattr "$CIBLE" > "$SAUV/M03_03.lsattr" 2>/dev/null || true

# si resolv.conf est un lien (systemd-resolved), on travaille sur une
# vraie copie pour que chattr ait prise (chattr ne suit pas les liens).
if [ -L "$CIBLE" ]; then
  real=$(readlink -f "$CIBLE")
  cp -a "$real" "$SAUV/M03_03.resolv.target" 2>/dev/null || true
  rm -f "$CIBLE"
  printf 'nameserver 10.10.10.1\n' > "$CIBLE"
fi

# --- la panne : on rend le fichier immuable -----------------------------
chattr +i "$CIBLE"

cat <<'EOF'

Symptôme attendu : le pipeline de déploiement échoue à l'étape qui met à jour
/etc/resolv.conf avec "Operation not permitted", ALORS QUE le job tourne en
root. Toute tentative manuelle "echo ... > /etc/resolv.conf" en root échoue
aussi. Le fichier semble figé.
EOF
