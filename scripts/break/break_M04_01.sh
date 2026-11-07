#!/usr/bin/env bash
# break_M04_01.sh — panne BF4.1 (sudo inutilisable : /etc/sudoers world-writable)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

# --- sauvegarde de l'état avant de casser -------------------------------
# (une seule fois : relancé, le script n'écrase pas les modes sains)
if [ ! -s "$SAUV/M04_01.modes" ]; then
  stat -c '%a %U %G %n' /etc/sudoers /etc/sudoers.d/* \
    > "$SAUV/M04_01.modes" 2>/dev/null || true
  cp -a /etc/sudoers "$SAUV/M04_01.sudoers" 2>/dev/null || true
fi

# --- la panne : le CONTENU reste parfaitement valide, c'est le MODE qui  -
# --- rend le fichier inutilisable. sudo refuse de lire une politique     -
# --- que n'importe quel utilisateur pourrait réécrire.                   -
chmod 0777 /etc/sudoers
chown root:root /etc/sudoers

# on s'assure que la syntaxe est irréprochable : le diagnostic ne doit pas
# se laisser distraire par une erreur de contenu
visudo -c >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : toute commande sudo échoue immédiatement avec
  sudo: /etc/sudoers is world writable
  sudo: error initializing audit plugin sudoers_audit
Aucune commande n'est exécutée. Le compte root n'ayant pas de mot de passe,
"su -" répond "su: Authentication failure".
EOF
