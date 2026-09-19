#!/usr/bin/env bash
# break_PC_4_2.sh — ticket PC.4.2 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_4_2; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"

# Sauvegarde l'état NTP pour la remise en état par le check si besoin.
timedatectl show -p NTP --value > "$SAUV/$ID.ntp" 2>/dev/null || true

# On désactive la synchro et on avance l'horloge de +37 minutes :
# suffisant pour que la validation TLS (tolérance ~quelques minutes) casse
# côté client sur les certificats à fenêtre serrée, et pour fausser les logs.
timedatectl set-ntp false 2>/dev/null || systemctl stop \
  systemd-timesyncd chrony chronyd 2>/dev/null || true
systemctl disable --now systemd-timesyncd 2>/dev/null || true
date -s "$(date -d '+37 min' '+%Y-%m-%d %H:%M:%S')" >/dev/null

cat <<'EOF'

Symptôme attendu : les clients qui appellent l'API en HTTPS échouent par
intermittence avec « certificate is not yet valid » ou « has expired », et
les horodatages des journaux sont en avance de plus d'une demi-heure sur
l'heure réelle. Aucun certificat n'a pourtant été changé.
EOF
