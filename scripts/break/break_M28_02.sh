#!/usr/bin/env bash
# break_M28_02.sh — panne BF28.2 (droits de sssd.conf, sss retiré de NSS)
# À lancer sur lab-db inscrit dans lab.local, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ -f /etc/sssd/sssd.conf ] || {
  echo "/etc/sssd/sssd.conf absent : termine L28.2 d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M28_02.nsswitch.conf" ] || cp -a /etc/nsswitch.conf "$SAUV/M28_02.nsswitch.conf"
[ -f "$SAUV/M28_02.sssd.conf" ]     || cp -a /etc/sssd/sssd.conf "$SAUV/M28_02.sssd.conf"

# 1. le fichier a été « recopié depuis le modèle » : droits par défaut
chmod 644 /etc/sssd/sssd.conf

# 2. et 3. « nettoyage » de nsswitch.conf : sss retiré des comptes et de sudo
sed -i -E '/^(passwd|group|shadow|sudoers):/ s/[[:space:]]+sss\b//g' /etc/nsswitch.conf

systemctl restart sssd >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : « id alice » répond « no such user » sur lab-db ;
« systemctl status sssd » est en échec ; le timer de sauvegarde de L28.4
échoue (journalctl -u sauvegarde-nginx). Sur lab-web, tout va bien.
EOF
