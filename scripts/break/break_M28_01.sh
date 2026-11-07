#!/usr/bin/env bash
# break_M28_01.sh — panne BF28.1 (horloge en avance, synchronisation coupée)
# À lancer sur lab-web inscrit dans lab.local, avec sudo. Idempotent :
# relancé, il ne décale pas l'horloge une seconde fois.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ -f /etc/ipa/default.conf ] || {
  echo "machine non inscrite dans lab.local : termine L28.2 d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
MARQUE="$SAUV/M28_01.fait"

# nom de l'unité chrony selon la famille
UNITE=chrony
systemctl list-unit-files chronyd.service >/dev/null 2>&1 && UNITE=chronyd

if [ ! -f "$MARQUE" ]; then
  { timedatectl status; systemctl is-enabled "$UNITE" || true; } \
    > "$SAUV/M28_01.etat-avant.txt" 2>&1
  # « maintenance » d'un collègue : synchronisation coupée…
  systemctl disable --now "$UNITE" >/dev/null 2>&1 || true
  timedatectl set-ntp false >/dev/null 2>&1 || true
  # … et une horloge qui a pris douze minutes d'avance
  date -s '+12 minutes' >/dev/null
  date -Is > "$MARQUE"
fi

# SSSD retente sa connexion avec la nouvelle heure
sss_cache -E 2>/dev/null || true
systemctl restart sssd

cat <<'EOF'

Symptôme attendu : une partie des comptes du domaine ne peut plus se
connecter à lab-web (« Permission denied » au mot de passe), alors qu'ils
entrent sur lab-db. D'autres comptes entrent encore sur lab-web, mais leur
session n'a pas de ticket Kerberos (klist : « No credentials cache found »).
Les comptes locaux fonctionnent, « id alice » répond normalement.
EOF
