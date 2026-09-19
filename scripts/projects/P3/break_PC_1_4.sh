#!/usr/bin/env bash
# break_PC_1_4.sh — ticket PC.1.4 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_1_4; mkdir -p "$SAUV"
ENVF=/etc/factura/api.env
[ -f "$ENVF" ] || { echo "lance d'abord setup_P3.sh (rôle web)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
[ -f "$SAUV/$ID.api.env" ] || cp -a "$ENVF" "$SAUV/$ID.api.env"

# « Déploiement 2.4.0 » : le script de la CI a réécrit api.env à partir
# du nouveau api.env.example du dépôt, où le port a changé.
sed -i -E 's/^PORT=.*/PORT=8082/; s/^APP_VERSION=.*/APP_VERSION=2.4.0/' "$ENVF"
mkdir -p /var/log/factura
printf '%s deploy factura-api 2.3.1 -> 2.4.0 : api.env regenere depuis \
api.env.example, service redemarre\n' "$(date '+%F %T')" \
  >> /var/log/factura/deploy.log
[ -d /run/systemd/system ] && systemctl restart factura-api.service || true
sleep 1

cat <<'EOF'

Symptôme attendu : depuis le déploiement de 15 h 10, https://factura.lab.local
renvoie « 502 Bad Gateway » sur toutes les pages. systemctl status
factura-api dit pourtant « active (running) ».
EOF
