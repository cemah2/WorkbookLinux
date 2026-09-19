#!/usr/bin/env bash
# break_M24_01.sh — panne BF24.1 : « le plan veut reconfigurer une VM qui
# n'est pas à nous ». Le VMID 9105 (lab2-ops) est détruit puis réutilisé par
# une VM « sandbox-julien » clonée du template, via l'API Proxmox (token de
# ~/lab24/.env). Sans API joignable, MODE=state simule la même situation en
# réécrivant les attributs de lab2-ops dans l'état (plan à lire avec
# -refresh=false). Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab24"
ENVF="$BASE/.env"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -r "$ENVF" ] || { echo "$ENVF absent : fais E24.8 d'abord" >&2; exit 1; }
set -a; . "$ENVF"; set +a
: "${PROXMOX_VE_ENDPOINT:?}" "${PROXMOX_VE_API_TOKEN:?}" "${PVE_NODE:=pve}"
API="${PROXMOX_VE_ENDPOINT%/}/api2/json"
AUTH="Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN"
VMID=9105
MODE="${MODE:-api}"

# racine OpenTofu de l'apprenant : 04-modules si initialisée, sinon 02-lab2
DIR="$BASE/02-lab2"
[ -f "$BASE/04-modules/.terraform/terraform.tfstate" ] && DIR="$BASE/04-modules"

api() {   # api <méthode> <chemin> [param=valeur ...]
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
tofu_as_user() {   # exécute tofu dans DIR avec l'environnement de l'apprenant
  sudo -u "$LAB_USER" -H bash -c \
    "set -a; . '$ENVF'; set +a; cd '$DIR' && $*"
}

if [ "$MODE" = api ] && ! api GET /version >/dev/null 2>&1; then
  echo "API Proxmox injoignable : bascule en MODE=state (simulation)" >&2
  MODE=state
fi

if [ "$MODE" = api ]; then
  CFG=$(api GET "/nodes/$PVE_NODE/qemu/$VMID/config" 2>/dev/null || true)
  if [ -n "$CFG" ] && [ "$(jq -r .data.name <<<"$CFG")" = "sandbox-julien" ]; then
    echo "9105 est déjà sandbox-julien : rien à refaire"
  else
    if [ -n "$CFG" ]; then
      [ -f "$SAUV/M24_01_9105.json" ] || printf '%s\n' "$CFG" > "$SAUV/M24_01_9105.json"
      ST=$(api GET "/nodes/$PVE_NODE/qemu/$VMID/status/current" | jq -r .data.status)
      [ "$ST" = "stopped" ] || attendre "$(api POST "/nodes/$PVE_NODE/qemu/$VMID/status/stop" | jq -r .data)"
      attendre "$(api DELETE "/nodes/$PVE_NODE/qemu/$VMID" "purge=1" \
                 "destroy-unreferenced-disks=1" | jq -r .data)"
    fi
    attendre "$(api POST "/nodes/$PVE_NODE/qemu/9100/clone" "newid=$VMID" \
               "name=sandbox-julien" "full=1" | jq -r .data)"
    api PUT "/nodes/$PVE_NODE/qemu/$VMID/config" "memory=1536" "tags=julien" \
      "ipconfig0=ip=10.10.10.125/24,gw=10.10.10.1" >/dev/null
    attendre "$(api POST "/nodes/$PVE_NODE/qemu/$VMID/status/start" | jq -r .data)" || true
  fi
else
  # simulation : l'état croit que lab2-ops a d'autres attributs (comme après
  # un refresh sur la VM de Julien) ; à lire avec : tofu plan -refresh=false
  ST=$(tofu_as_user tofu state pull)
  [ -f "$SAUV/M24_01_state.json" ] || printf '%s\n' "$ST" > "$SAUV/M24_01_state.json"
  if grep -q '"sandbox-julien"' <<<"$ST"; then
    echo "état déjà modifié : rien à refaire"
  else
    NEW=$(jq '.serial += 1
      | (.resources[] | select(.type == "proxmox_virtual_environment_vm")
         | .instances[] | select(.attributes.name == "lab2-ops") | .attributes)
        |= (.name = "sandbox-julien"
            | .tags = ["julien"]
            | .memory[0].dedicated = 1536
            | .initialization[0].ip_config[0].ipv4[0].address = "10.10.10.125/24")' \
      <<<"$ST")
    TMP=$(mktemp); printf '%s\n' "$NEW" > "$TMP"; chown "$LAB_USER" "$TMP"
    tofu_as_user tofu state push "$TMP"
    rm -f "$TMP"
  fi
fi

cat <<EOF

Symptôme attendu : dans $DIR,
  tofu plan$( [ "$MODE" = state ] && printf ' -refresh=false' )
annonce une mise à jour de lab2-ops (nom, mémoire, adresse, tags). Or dans
Proxmox, le VMID 9105 s'appelle sandbox-julien et appartient à Julien, qui
jure avoir « pris un VMID libre ». Interdit d'appliquer et de détruire sa VM.
Objectif : plan final « 1 to add » et rien d'autre, sandbox-julien intacte.
EOF
