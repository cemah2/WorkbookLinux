#!/usr/bin/env bash
# break_M11_06.sh — panne BF11.6 (montage NFS hard bloqué, processus en D)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/. À lancer sur lab-db.
#
# Le serveur NFS n'est pas touché : le script rend le serveur injoignable
# POUR NFS depuis ce client (il répond toujours au ping), puis lance un
# processus qui écrit dans le partage et se retrouve bloqué.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
MNT=/mnt/partage-ops
TABLE=lab11bf
mkdir -p "$SAUV"

# --- prérequis ----------------------------------------------------------
# un automount non déclenché se présente en autofs : on le réveille
ls "$MNT" >/dev/null 2>&1 || true
FS=$(findmnt -no FSTYPE "$MNT" 2>/dev/null | tail -1 || true)
case "$FS" in
  nfs|nfs4) : ;;
  *)
    cat >&2 <<EOF
$MNT n'est pas un montage NFS actif.
Cette panne se pose sur le partage monté au lab L11.7 depuis lab-ops
(10.10.10.14:/srv/nfs/partage, en hard) : monte-le d'abord, puis relance
ce script.
EOF
    exit 1 ;;
esac
SRC=$(findmnt -no SOURCE "$MNT" | tail -1)
SERVEUR="${SRC%%:*}"
case "$SERVEUR" in
  *[0-9].[0-9]*) : ;;
  *) SERVEUR=$(getent ahostsv4 "$SERVEUR" | awk 'NR==1{print $1}') ;;
esac
[ -n "$SERVEUR" ] || { echo "serveur NFS introuvable pour $MNT" >&2; exit 1; }

findmnt -no OPTIONS "$MNT" | tail -1 | grep -q 'soft' && {
  echo "$MNT est monté en soft : remonte-le en hard, sinon la panne" >&2
  echo "n'a pas de sens (voir L11.7)." >&2
  exit 1; }

# --- trace de l'état avant ---------------------------------------------
[ -f "$SAUV/M11_06.findmnt" ] || findmnt "$MNT" > "$SAUV/M11_06.findmnt"
echo "$SERVEUR" > "$SAUV/M11_06.serveur"
if command -v nft >/dev/null 2>&1; then
  [ -f "$SAUV/M11_06.nft" ] || nft list ruleset > "$SAUV/M11_06.nft" 2>/dev/null
fi

# --- 1. le serveur devient injoignable pour NFS (et seulement pour NFS) --
if command -v nft >/dev/null 2>&1; then
  if ! nft list table inet "$TABLE" >/dev/null 2>&1; then
    nft add table inet "$TABLE"
    nft add chain inet "$TABLE" sortie \
      '{ type filter hook output priority 0; policy accept; }'
    nft add rule inet "$TABLE" sortie ip daddr "$SERVEUR" tcp dport 2049 drop
  fi
  echo nft > "$SAUV/M11_06.moteur"
elif command -v iptables >/dev/null 2>&1; then
  iptables -C OUTPUT -d "$SERVEUR" -p tcp --dport 2049 -j DROP 2>/dev/null \
    || iptables -I OUTPUT -d "$SERVEUR" -p tcp --dport 2049 -j DROP
  echo iptables > "$SAUV/M11_06.moteur"
else
  echo "ni nft ni iptables : impossible de poser la panne" >&2; exit 1
fi

# --- 2. un processus qui écrit dans le partage… et qui se fige -----------
if ! pgrep -f 'factura-rapport' >/dev/null 2>&1; then
  setsid bash -c "exec -a factura-rapport sh -c \
    'echo rapport > \"$MNT/rapport-\$(date +%s).txt\"; df -h \"$MNT\"'" \
    </dev/null >/dev/null 2>&1 &
  sleep 2
fi

cat <<'EOF'

Symptôme attendu : sur lab-db, « ls /mnt/partage-ops » ne rend pas la main,
« df -h » non plus, et « uptime » montre une charge qui grimpe alors que le
CPU ne fait rien. Ctrl-C est sans effet. lab-ops, lui, répond au ping.
EOF
