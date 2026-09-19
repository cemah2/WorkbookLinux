#!/usr/bin/env bash
# break_M11_05.sh — panne BF11.5 (miroir mdadm dégradé, alerte muette)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
MD=/dev/md0
CONF=/etc/mdadm/mdadm.conf
mkdir -p "$SAUV"

# --- prérequis ----------------------------------------------------------
command -v mdadm >/dev/null 2>&1 || {
  echo "mdadm n'est pas installé : sudo apt install -y mdadm" >&2; exit 1; }

if ! [ -b "$MD" ] || ! grep -q '^md0 : active raid1' /proc/mdstat 2>/dev/null
then
  cat >&2 <<EOF
$MD n'est pas un RAID1 assemblé.
Cette panne se pose sur le miroir construit au lab L11.6 (mdadm --create
/dev/md0 --level=1 ..., LVM par-dessus, monté sur /srv/factura/partage) :
fais-le d'abord, puis relance ce script.
EOF
  exit 1
fi

if grep -q 'recovery\|resync' /proc/mdstat; then
  echo "une synchronisation est en cours : attends [UU] avant de casser." >&2
  exit 1
fi

# --- trace de l'état avant ---------------------------------------------
[ -f "$SAUV/M11_05.mdstat" ]  || cp /proc/mdstat "$SAUV/M11_05.mdstat"
[ -f "$SAUV/M11_05.detail" ]  || mdadm --detail "$MD" > "$SAUV/M11_05.detail"
[ -f "$SAUV/M11_05.mdadm.conf" ] || \
  cp "$CONF" "$SAUV/M11_05.mdadm.conf" 2>/dev/null || true

# --- 1. l'alerte devient muette -----------------------------------------
if [ -d /run/systemd/system ]; then
  systemctl disable --now mdmonitor.service >/dev/null 2>&1 || true
fi
if [ -f "$CONF" ]; then
  sed -i 's/^MAILADDR/#MAILADDR/' "$CONF"
fi

# --- 2. un membre passe en faulty ----------------------------------------
# On choisit le membre en position 0 (RaidDevice 0), sauf s'il y a déjà
# un membre faulty : dans ce cas la panne est déjà posée (idempotence).
if ! grep -q '(F)' /proc/mdstat; then
  MEMBRE=$(mdadm --detail "$MD" | awk '$4=="0" && $5=="active"{print $NF}' \
    | head -1)
  [ -n "$MEMBRE" ] || MEMBRE=$(mdadm --detail "$MD" \
    | awk '/active sync/{print $NF}' | head -1)
  echo "$MEMBRE" > "$SAUV/M11_05.membre"
  mdadm "$MD" --fail "$MEMBRE" >/dev/null 2>&1
  sleep 1
fi

# --- 3. on antidate discrètement (pour l'exercice de datation) ----------
# Rien à faire : le noyau et le superblock horodatent eux-mêmes la panne.

cat <<'EOF'

Symptôme attendu : aucun. /srv/factura/partage répond normalement, les
écritures passent, personne ne s'est plaint. Un collègue te demande
simplement : « au fait, tu as vérifié le miroir de lab-db ? »
EOF
