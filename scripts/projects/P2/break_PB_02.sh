#!/usr/bin/env bash
# break_PB_02.sh — INC-B2 : tofu plan veut recréer la base de prod
# À lancer avec sudo sur lab-adm. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/INC-B2/ (état prod, mémoire 9022).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
REPO="${REPO:-$LAB_HOME/factura-v2}"
BK=/root/.breakfix-backup/INC-B2
PVE=10.10.10.1
STG_DB_VMID=9022
mkdir -p "$BK"
u() { sudo -u "$LAB_USER" -H "$@"; }
pve() { u ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$PVE" "$@"; }

# 1. « libérer de la RAM à chaud » sur la base de staging, depuis Proxmox
if [ ! -f "$BK/memory-$STG_DB_VMID.txt" ]; then
  pve "qm config $STG_DB_VMID" | awk '/^memory:/{print $2}' \
    > "$BK/memory-$STG_DB_VMID.txt"
fi
pve "qm set $STG_DB_VMID --memory 1536" >/dev/null

# 2. « nettoyer un truc qui traînait » dans l'état OpenTofu de la prod
cd "$REPO/infra"
CUR=$(u tofu workspace show)
u tofu workspace select prod >/dev/null
STATE="terraform.tfstate.d/prod/terraform.tfstate"
[ -f "$BK/prod.tfstate" ] || cp -a "$STATE" "$BK/prod.tfstate"
ADDR=$(u tofu state list 2>/dev/null \
       | grep 'proxmox_virtual_environment_vm' | grep -i '"db"' | head -1 || true)
if [ -n "$ADDR" ]; then
  u tofu state rm "$ADDR" >/dev/null
fi
u tofu workspace select "$CUR" >/dev/null

cat <<'EOF'
Symptôme : un collègue en congé a « libéré de la RAM à chaud » hier soir et
« nettoyé un truc dans OpenTofu qui traînait ».
  make infra-plan ENV=staging   -> propose de modifier factura-staging-db
  make infra-plan ENV=prod      -> propose de CRÉER factura-prod-db
La VM factura-prod-db tourne, avec les données de prod dedans.
EOF
