#!/usr/bin/env bash
# break_M09_03.sh — panne BF9.3 (un paquet retenu bloque la mise à jour)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
PAQ="$LAB_HOME/lab09/paquets/outil-lab_1.0.0_all.deb"
mkdir -p "$SAUV"

[ -f "$PAQ" ] || {
  echo "$PAQ absent : lance d'abord setup_M09.sh" >&2; exit 1; }

# --- on mémorise l'état des retenues avant de toucher à quoi que ce soit
if [ ! -f "$SAUV/M09_03.holds" ]; then
  apt-mark showhold > "$SAUV/M09_03.holds" 2>/dev/null || true
fi

# --- 1. la version ancienne est en place --------------------------------
DEBIAN_FRONTEND=noninteractive \
  dpkg -i --force-confdef --force-confold "$PAQ" >/dev/null 2>&1 || true

# --- 2. deux verrous posés à deux endroits différents -------------------
# a) le marqueur dpkg, visible avec apt-mark showhold
apt-mark hold outil-lab >/dev/null

# b) un fichier d'épinglage oublié par un prédécesseur, qui interdit
#    toute version supérieure à 1.0.0. Les deux produisent le même
#    symptôme, mais un seul se voit avec apt-mark.
cat > /etc/apt/preferences.d/80-outil-lab-gel.pref <<'EOF'
# Gel temporaire suite a l'incident INC-1187 — a retirer apres validation
Package: outil-lab
Pin: version 1.0.0
Pin-Priority: 1001
EOF
chmod 0644 /etc/apt/preferences.d/80-outil-lab-gel.pref

apt-get update >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : le dépôt publie outil-lab 1.2.0, « apt list
--upgradable » ne le propose pas, et « sudo apt upgrade » se termine
sans rien faire pour ce paquet. « sudo apt install -y
outil-lab=1.2.0 » s'arrête sur un E: au lieu d'installer.
EOF
