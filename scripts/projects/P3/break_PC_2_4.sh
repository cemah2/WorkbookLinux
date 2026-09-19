#!/usr/bin/env bash
# break_PC_2_4.sh — ticket PC.2.4 (lab-ops) : demande de changement.
# Ne casse rien : dépose les exports à purger.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_2_4; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
E=/srv/factura/exports
mkdir -p "$E/archives-legales"
for j in 2 9 20 31 45 60 95 140 200; do
  f="$E/export-$(date -d "$j days ago" +%Y%m%d).csv"
  printf 'id;client;montant\n1;test;%d\n' "$j" > "$f"; touch -d "$j days ago" "$f"
done
for j in 40 120; do
  f="$E/export-$(date -d "$j days ago" +%Y%m%d)-legal.csv"
  printf 'id;client;montant\n1;legal;%d\n' "$j" > "$f"; touch -d "$j days ago" "$f"
done
f="$E/archives-legales/bilan-2025.csv"
printf 'bilan\n' > "$f"; touch -d '300 days ago' "$f"
f="$E/README.txt"; printf 'Exports CSV de Factura.\n' > "$f"; touch -d '400 days ago' "$f"
chown -R "${SUDO_USER:-mathieu}:${SUDO_USER:-mathieu}" "$E"
cat <<'EOF'

Demande déposée : /srv/factura/exports contient des exports CSV qui
s'accumulent. Mettre en place la purge automatique décrite dans le ticket.
EOF
