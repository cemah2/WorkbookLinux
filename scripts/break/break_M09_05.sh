#!/usr/bin/env bash
# break_M09_05.sh — panne BF9.5 (horloge dérivée : TLS et apt cassés)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

if [ -f /etc/chrony/chrony.conf ]; then
  CONF=/etc/chrony/chrony.conf; UNIT=chrony.service
elif [ -f /etc/chrony.conf ]; then
  CONF=/etc/chrony.conf; UNIT=chronyd.service
else
  echo "chrony n'est pas installé (voir §9.1 / L9.5)" >&2; exit 1
fi

# --- sauvegarde ------------------------------------------------------------
[ -f "$SAUV/M09_05.chrony.conf" ] || cp -a "$CONF" "$SAUV/M09_05.chrony.conf"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$SAUV/M09_05.date-avant"

# --- 1. plus de service de temps -----------------------------------------
systemctl disable --now "$UNIT" >/dev/null 2>&1 || true
systemctl disable --now systemd-timesyncd >/dev/null 2>&1 || true
timedatectl set-ntp false >/dev/null 2>&1 || true

# --- 2. plus de saut autorisé ---------------------------------------------
sed -i 's/^makestep /#makestep /' "$CONF"

# --- 3. l'heure « pour tester un script », écrite aussi dans le RTC -------
# 44 jours EN ARRIÈRE : c'est ce qui produit « not valid yet » (apt, TLS).
date -s "$(date -d '-44 days' '+%Y-%m-%d %H:%M:%S')" >/dev/null
hwclock --systohc >/dev/null 2>&1 || true

cat <<'EOF2'

Symptôme attendu : « sudo apt update » échoue avec « Release file ... is not
valid yet », « curl https://... » refuse les certificats récents (« not yet
valid »), et les journaux portent des dates dans le passé. Le réseau, lui,
fonctionne.
EOF2
