#!/usr/bin/env bash
# break_M03_02.sh — panne BF3.2 (partage cassé : SGID + ACL par défaut retirés)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

DIR=/srv/factura/exports
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -d "$DIR" ] || { echo "$DIR absent : lance d'abord setup_M03.sh" >&2; exit 1; }

# --- sauvegarde de l'état avant de casser -------------------------------
stat -c '%a %U:%G %n' "$DIR" > "$SAUV/M03_02.mode" 2>/dev/null || true
if command -v getfacl >/dev/null 2>&1; then
  getfacl -p "$DIR" > "$SAUV/M03_02.acl" 2>/dev/null || true
fi

# --- on retire le SGID (2770 -> 0770) : plus d'héritage de groupe -------
chmod 0770 "$DIR"

# --- et on efface toute ACL par défaut : plus de w de groupe hérité -----
if command -v setfacl >/dev/null 2>&1; then
  setfacl -b "$DIR" 2>/dev/null || true          # supprime les ACL étendues
  setfacl -k "$DIR" 2>/dev/null || true          # supprime les ACL par défaut
fi

# le répertoire reste inscriptible (le groupe peut créer), c'est bien
# l'héritage qui est cassé, pas l'accès en écriture au répertoire.
chgrp facturation "$DIR"

cat <<'EOF'

Symptôme attendu : les fichiers déposés dans /srv/factura/exports par un membre
de l'équipe facturation appartiennent au mauvais groupe et ne sont plus
modifiables par les collègues. Le répertoire existe toujours et chacun peut
encore y créer des fichiers. "Avant, ça marchait."
EOF
