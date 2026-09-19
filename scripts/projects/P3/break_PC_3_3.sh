#!/usr/bin/env bash
# break_PC_3_3.sh — ticket PC.3.3 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_3_3; mkdir -p "$SAUV"
[ -f /etc/factura/api.env ] || { echo "lance setup_P3.sh (rôle web)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
cp -a /etc/hosts "$SAUV/$ID.hosts"

# Un « nettoyage » de /etc/hosts a retiré les entrées du lab : la
# résolution de lab-db (base et redis) ne fonctionne plus.
grep -vE '[[:space:]]lab-db([[:space:]]|$)' /etc/hosts > /etc/hosts.tmp
mv /etc/hosts.tmp /etc/hosts
# l'API pointe la base par son nom : /sante repasse en 503
[ -d /run/systemd/system ] && systemctl restart factura-api.service || true
sleep 1

cat <<'EOF'

Symptôme attendu : l'application affiche « base de données injoignable ».
/sante renvoie 503 avec « could not translate host name "lab-db" to
address ». Pourtant la base répond quand on la joint par son IP.
EOF
