#!/usr/bin/env bash
# break_M24_04.sh — panne BF24.4 : « la VM démarre mais cloud-init n'a rien
# fait ». Clone 9100 en 9120 (bf-ci) via l'API, pose ipconfig0, puis retire
# le lecteur cloud-init (ide2) avant de démarrer. Idempotent.
# Sauvegarde de la configuration dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
ENVF="$LAB_HOME/lab24/.env"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -r "$ENVF" ] || { echo "$ENVF absent : fais E24.8 d'abord" >&2; exit 1; }
set -a; . "$ENVF"; set +a
: "${PROXMOX_VE_ENDPOINT:?}" "${PROXMOX_VE_API_TOKEN:?}" "${PVE_NODE:=pve}"
API="${PROXMOX_VE_ENDPOINT%/}/api2/json"
AUTH="Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN"
VMID=9120
VM="/nodes/$PVE_NODE/qemu/$VMID"

api() {
  local m=$1 p=$2; shift 2; local args=()
  for kv in "$@"; do args+=(--data-urlencode "$kv"); done
  curl -sk -f --max-time 30 -X "$m" -H "$AUTH" "${args[@]}" "$API$p"
}
attendre() {
  local upid=$1 st
  [ -n "$upid" ] && [ "$upid" != "null" ] || return 0
  while :; do
    st=$(api GET "/nodes/$PVE_NODE/tasks/$upid/status")
    [ "$(jq -r .data.status <<<"$st")" = "stopped" ] && break; sleep 1
  done
  [ "$(jq -r .data.exitstatus <<<"$st")" = "OK" ]
}

api GET /version >/dev/null 2>&1 \
  || { echo "API Proxmox injoignable (token, réseau ?)" >&2; exit 1; }
api GET "/nodes/$PVE_NODE/qemu/9100/config" 2>/dev/null | jq -e '.data.template == 1' \
  >/dev/null || { echo "template 9100 absent : fais E24.9 d'abord" >&2; exit 1; }

CFG=$(api GET "$VM/config" 2>/dev/null || true)
if [ -z "$CFG" ]; then
  attendre "$(api POST "/nodes/$PVE_NODE/qemu/9100/clone" "newid=$VMID" \
             "name=bf-ci" "full=1" | jq -r .data)"
  CFG=$(api GET "$VM/config")
fi
[ -f "$SAUV/M24_04_9120.json" ] || printf '%s\n' "$CFG" > "$SAUV/M24_04_9120.json"

if jq -e '.data.ide2 // empty' <<<"$CFG" >/dev/null; then
  ST=$(api GET "$VM/status/current" | jq -r .data.status)
  [ "$ST" = "stopped" ] || attendre "$(api POST "$VM/status/stop" | jq -r .data)"
  # ipconfig0 correct... mais plus aucun lecteur pour transporter cidata
  api PUT "$VM/config" "ipconfig0=ip=10.10.10.120/24,gw=10.10.10.1" \
    "delete=ide2" >/dev/null
else
  echo "9120 est déjà sans lecteur cloud-init : rien à refaire"
fi
ST=$(api GET "$VM/status/current" | jq -r .data.status)
[ "$ST" = "running" ] || attendre "$(api POST "$VM/status/start" | jq -r .data)"

cat <<'EOF'

Symptôme attendu : la VM bf-ci (VMID 9120), clonée à la main depuis le
template avec un ipconfig0 correct (10.10.10.120/24), démarre : la console
(qm terminal 9120) montre « ubuntu login: », mais aucune adresse sur vmbr1,
aucun utilisateur mathieu, aucun mot de passe connu, ssh impossible.
Interdit de réinstaller, de passer en rescue ou de détruire la VM.
Objectif : diagnostiquer depuis le nœud sans entrer dans la VM, corriger,
redémarrer, prouver avec cloud-init status --long et cloud-init query ds.
EOF
