#!/usr/bin/env bash
# break_PC_2_2.sh — ticket PC.2.2 (lab-ops)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_2_2; mkdir -p "$SAUV"
mountpoint -q /mnt/archives \
  || { echo "/mnt/archives n'est pas monté : lance setup_P3.sh (rôle ops)" >&2
       exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
cp -a /etc/fstab "$SAUV/$ID.fstab" 2>/dev/null || true

# Le serveur de fichiers « part » : ses paquets NFS ne passent plus.
# (Simulation d'une coupure réseau vers le NAS avec nftables.)
if ! nft list table inet nas_coupure >/dev/null 2>&1; then
  nft add table inet nas_coupure
  nft add chain inet nas_coupure sortie \
    '{ type filter hook output priority 0; policy accept; }'
  nft add rule inet nas_coupure sortie tcp dport 2049 drop
  nft add rule inet nas_coupure sortie tcp dport 111 drop
fi

# Un export en cours reste bloqué dessus (processus en état D)
setsid nohup bash -c 'exec -a export-archives \
  cp /srv/factura/data/facture-0001.txt /mnt/archives/export-en-cours.tmp' \
  >/dev/null 2>&1 < /dev/null &

cat <<'EOF'

Symptôme attendu : « df -h » et « ls /mnt/archives » ne rendent jamais la
main, le job d'export des archives est figé, la charge moyenne monte alors
que le CPU est inactif.
EOF
