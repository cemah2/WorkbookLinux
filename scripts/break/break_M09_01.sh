#!/usr/bin/env bash
# break_M09_01.sh — panne BF9.1 (base dpkg en état incohérent)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
PAQ="$LAB_HOME/lab09/paquets/outil-lab_1.3.0_all.deb"
mkdir -p "$SAUV"

[ -f "$PAQ" ] || {
  echo "$PAQ absent : lance d'abord setup_M09.sh" >&2; exit 1; }

# --- 1. outil-lab 1.3.0 : son postinst exige un fichier de licence -----
# On s'assure qu'il n'existe pas, puis on installe : dpkg dépose les
# fichiers (unpack) mais échoue à la configuration.
rm -f /etc/outil-lab/licence.key
DEBIAN_FRONTEND=noninteractive \
  dpkg -i --force-confdef --force-confold "$PAQ" >/dev/null 2>&1 || true

# --- 2. journal dpkg non rejoué ---------------------------------------
# Une entrée numérique dans /var/lib/dpkg/updates fait croire à apt
# qu'une transaction dpkg a été interrompue : il refuse de travailler.
mkdir -p /var/lib/dpkg/updates
if [ ! -f "$SAUV/M09_01.marqueur" ]; then
  : > "$SAUV/M09_01.marqueur"
fi
# Le fichier est laissé vide à dessein : apt ne regarde que le nom
# (une suite de chiffres), et un contenu invalide rendrait dpkg-query
# lui-même inutilisable — ce n'est pas la panne recherchée.
: > /var/lib/dpkg/updates/0042

# --- 3. verrou orphelin ------------------------------------------------
# Un /var/lib/dpkg/lock-frontend laissé par un apt tué au mauvais moment
# n'est PAS le problème ici (le verrou est libéré à la mort du process),
# mais on ajoute le symptôme classique : un cache d'archives partiel.
mkdir -p /var/cache/apt/archives/partial
: > /var/cache/apt/archives/partial/outil-lab_1.3.0_all.deb.FAILED

cat <<'EOF'

Symptôme attendu : « sudo apt install <n'importe quoi> » refuse de
démarrer avec un message d'erreur unique, sans rien installer.
« dpkg -l outil-lab » n'affiche pas ii dans la première colonne.
EOF
