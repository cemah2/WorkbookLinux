#!/usr/bin/env bash
# break_M10_04.sh — panne BF10.4 (épinglage trop large : apt veut
#                   rétrograder la moitié du système)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

. /etc/os-release
SUITE="${VERSION_CODENAME:-noble}"

# --- sauvegarde --------------------------------------------------------
if [ ! -f "$SAUV/M10_04.liste" ]; then
  ls -1 /etc/apt/preferences.d/ > "$SAUV/M10_04.liste" 2>/dev/null || true
fi

# --- la casse ----------------------------------------------------------
# Intention d'origine : « rester sur les versions de la release, ne pas
# prendre les nouveautés ». Écrit sans comprendre ce que veut dire
# Pin-Priority > 1000 ni ce que couvre « Package: * ».
cat > /etc/apt/preferences.d/00-socle-fige.pref <<EOF
# Socle fige — ticket CHG-4402
# « on reste sur la release, on ne prend pas les nouveautes »
Package: *
Pin: release a=$SUITE
Pin-Priority: 1001
EOF
chmod 0644 /etc/apt/preferences.d/00-socle-fige.pref

cat <<'EOF'

Symptôme attendu : « sudo apt upgrade » annonce plusieurs centaines de
paquets sous un intitulé qui n'est pas « will be upgraded », et propose
de remplacer des versions installées par des versions plus anciennes,
dont apt, dpkg et libc6. Aucune mise à jour de sécurité n'est plus
proposée.
EOF
