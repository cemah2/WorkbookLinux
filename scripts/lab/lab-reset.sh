#!/usr/bin/env bash
# lab-reset.sh — remet une ou plusieurs VM du lab à l'état snap-clean
# (ou à un autre snapshot) et les redémarre.
# À lancer en root sur le nœud Proxmox VE 8.
#
# Usage :
#   bash lab-reset.sh                 # rollback des 7 VM sur snap-clean
#   bash lab-reset.sh lab-db          # une seule VM (nom ou VMID)
#   bash lab-reset.sh lab-db lab-web  # plusieurs
#   bash lab-reset.sh --snap avant-lab11 lab-db   # autre snapshot
#   bash lab-reset.sh --list lab-db   # liste les snapshots d'une VM
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-env.sh
. "$HERE/lab-env.sh"

need_root; need_qm

SNAP="$LAB_SNAP"
LIST=0
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --snap) SNAP="${2:?nom de snapshot attendu}"; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

# nom -> vmid (accepte déjà un vmid)
resolve() {
  local want="$1" line vmid name
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    if [ "$want" = "$vmid" ] || [ "$want" = "$name" ]; then
      echo "$vmid"; return 0
    fi
  done
  return 1
}

name_of() {
  local want="$1" line vmid name
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    [ "$want" = "$vmid" ] && { echo "$name"; return 0; }
  done
  echo "$want"
}

VMIDS=()
if [ "${#TARGETS[@]}" -eq 0 ]; then
  for line in "${LAB_VMS[@]}"; do
    read -r vmid _ <<< "$line"; VMIDS+=("$vmid")
  done
else
  for t in "${TARGETS[@]}"; do
    v="$(resolve "$t")" || die "VM inconnue : $t"
    VMIDS+=("$v")
  done
fi

if [ "$LIST" -eq 1 ]; then
  for vmid in "${VMIDS[@]}"; do
    echo "== $(name_of "$vmid") ($vmid)"
    qm listsnapshot "$vmid"
  done
  exit 0
fi

FAILS=0
for vmid in "${VMIDS[@]}"; do
  name="$(name_of "$vmid")"
  if ! qm status "$vmid" >/dev/null 2>&1; then
    ko "$name ($vmid) n'existe pas"; FAILS=$((FAILS+1)); continue
  fi
  if ! qm listsnapshot "$vmid" | grep -qw "$SNAP"; then
    ko "$name : snapshot $SNAP introuvable (--list pour voir)"
    FAILS=$((FAILS+1)); continue
  fi
  info "rollback de $name ($vmid) sur $SNAP"
  # qm rollback exige une VM arrêtée quand le snapshot n'inclut pas la RAM.
  if qm status "$vmid" | grep -q running; then
    qm stop "$vmid" --timeout 30 >/dev/null 2>&1 || qm stop "$vmid"
  fi
  qm rollback "$vmid" "$SNAP"
  qm start "$vmid"
  ok "$name : restauré et redémarré"
done

[ "$FAILS" -eq 0 ] || die "$FAILS VM non restaurée(s)"
echo "Attends ~30 s que les VM répondent, puis : bash lab-status.sh"
