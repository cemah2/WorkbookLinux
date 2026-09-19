#!/usr/bin/env bash
# break_M19_02.sh — panne BF19.2 : « le groupe db a disparu »
# Remplace ~/lab19/inventory/hosts.yml par la version « rangée » du collègue.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
INV="$LAB_HOME/lab19/inventory/hosts.yml"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$INV" ] || { echo "$INV absent : lance setup_M19.sh" >&2; exit 1; }

# on ne sauvegarde que si le fichier actuel est sain (relance idempotente)
if python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$INV" \
     >/dev/null 2>&1; then
  cp -a "$INV" "$SAUV/M19_02_hosts.yml"
fi

# La version « rangée » : commentaires ajoutés, groupes réordonnés...
# et deux erreurs (une tabulation, un nom d'hôte).
printf '%s\n' \
'---' \
'# Inventaire du lab - rangé par groupes (Julien)' \
'all:' \
'  hosts:' \
'    lab-web:' \
'      ansible_host: 10.10.10.11' \
'    lab-db:' \
'      ansible_host: 10.10.10.12' \
'    lab-rhel:' \
'      ansible_host: 10.10.10.13' \
'    lab-ops:' \
'      ansible_host: 10.10.10.14' \
'  children:' \
'    # --- roles ---' \
'    web:' \
'      hosts:' \
'        lab-web:' \
'        lab-rhel:' \
'    db:' \
'      hosts:' \
'        lab_db:' \
'    ops:' \
'      hosts:' \
'        lab-ops:' \
'    # --- distributions ---' \
'    ubuntu:' \
'      hosts:' \
'        lab-web:' \
"$(printf '\t')lab-db:" \
'        lab-ops:' \
'    rhel:' \
'      hosts:' \
'        lab-rhel:' \
> "$INV"
chown "$LAB_USER":"$LAB_USER" "$INV"

cat <<'EOF'

Symptôme attendu : depuis que l'inventaire a été « rangé »,
  cd ~/lab19 && ansible db -m ansible.builtin.ping
répond « Could not match supplied host pattern, ignoring: db » puis
« No hosts matched, nothing to do », et ansible all -m ansible.builtin.ping
ne connaît plus que localhost, avec plusieurs [WARNING] avant.
Objectif : lire tous les avertissements, corriger le fichier sans le
réécrire, et retrouver db, web, ubuntu et rhel dans
ansible-inventory --graph avec les bons hôtes.
EOF
