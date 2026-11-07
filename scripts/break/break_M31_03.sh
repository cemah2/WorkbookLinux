#!/usr/bin/env bash
# break_M31_03.sh — panne BF31.3 (tâches en état D derrière un plafond d'E/S)
# À lancer sur lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
date -Is > "$SAUV/M31_03.etat"

cat > /etc/systemd/system/lab31-archiveur.service <<'EOF'
[Unit]
Description=Archivage des journaux

[Service]
# six flux d'écriture directe, recommencés sans fin ($$ : un $ littéral pour systemd)
ExecStart=/bin/sh -c 'for i in 1 2 3 4 5 6; do \
  ( while :; do dd if=/dev/zero of=/var/tmp/lab31-archive-$$i bs=1M count=20 \
      oflag=direct conv=notrunc status=none; done ) & done; wait'
# « pour ne pas gêner la production »
IOWriteBandwidthMax=/var/tmp 256K
ExecStopPost=/bin/sh -c 'rm -f /var/tmp/lab31-archive-*'
EOF
systemctl daemon-reload
systemctl restart lab31-archiveur.service

cat <<'EOF'

Symptôme attendu (après une à deux minutes) : load average au-dessus de 6
sur 2 vCPU, CPU inactif à plus de 90 %, aucun processus gourmand, machine
réactive.
EOF
