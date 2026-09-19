#!/usr/bin/env bash
# break_PC_4_4.sh — ticket PC.4.4 (lab-ops)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_4_4; mkdir -p "$SAUV"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker indisponible : ce ticket n'est pas jouable ici." >&2; exit 1
fi
[ -f /etc/factura/worker.env ] || { echo "lance setup_P3.sh (rôle ops)" >&2
  exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
cp -a /etc/factura/worker.env "$SAUV/$ID.worker.env"

# La sonde met 1,5 s à répondre ; on met un timeout de 1 s, un intervalle
# de 5 s et une seule tentative : le conteneur bascule unhealthy, et
# l'autoheal le redémarre en boucle.
cat > /etc/factura/worker.env <<'EOF'
HC_INTERVAL=5s
HC_TIMEOUT=1s
HC_RETRIES=1
HC_START=1s
EOF
systemctl restart factura-worker.service 2>/dev/null || true
systemctl start factura-autoheal.timer 2>/dev/null || true

cat <<'EOF'

Symptôme attendu : le conteneur « factura-worker » redémarre sans cesse.
« docker ps » le montre tantôt « health: starting », tantôt
« unhealthy », et son uptime ne dépasse jamais une minute. Le traitement
des lots ne se termine jamais.
EOF
