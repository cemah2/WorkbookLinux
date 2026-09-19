#!/usr/bin/env bash
# lab-create.sh — clone les 7 VM du laboratoire depuis les templates
# (9000 Ubuntu 24.04, 9010 Rocky 9), fixe IP / RAM / CPU / disques,
# les démarre, puis (deuxième passe) pose le snapshot de référence.
# À lancer en root sur le nœud Proxmox VE 8, après make-templates.sh.
#
# Usage :
#   bash lab-create.sh            # clone + configure + démarre les 7 VM
#   bash lab-create.sh snapshot   # pose snap-clean sur les 7 VM
#                                 # (après bootstrap-lab.sh dans chaque VM)
#   bash lab-create.sh destroy    # supprime les 7 VM (demande confirmation)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-env.sh
. "$HERE/lab-env.sh"

need_root; need_qm
ACTION="${1:-create}"

# ---------------------------------------------------------------------
# Attend que l'agent QEMU réponde (donc que l'OS soit démarré), 120 s max.
# ---------------------------------------------------------------------
wait_agent() {
  local vmid="$1" _i
  for _i in $(seq 1 60); do
    if qm agent "$vmid" ping >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

# ---------------------------------------------------------------------
create_vm() {
  local vmid="$1" name="$2" ip="$3" tpl="$4" cores="$5" ram="$6" disk="$7"
  local src

  case "$tpl" in
    ubuntu) src="$TPL_UBUNTU_ID" ;;
    rocky)  src="$TPL_ROCKY_ID" ;;
    *) die "template inconnu : $tpl" ;;
  esac
  qm status "$src" >/dev/null 2>&1 \
    || die "template $src absent : lance make-templates.sh d'abord"

  if qm status "$vmid" >/dev/null 2>&1; then
    ok "$name ($vmid) existe déjà, on ne touche à rien"
    return 0
  fi

  info "clone $src -> $vmid ($name)"
  # --full : clone complet, indépendant du template (un linked clone
  # interdirait de supprimer le template et complique les snapshots).
  qm clone "$src" "$vmid" --name "$name" --full 1 --storage "$LAB_STORAGE"

  info "  ressources : $cores vCPU, $ram Mo, disque ${disk}G"
  qm set "$vmid" \
    --cores "$cores" \
    --memory "$ram" \
    --onboot 1 \
    --description "Workbook Linux/DevOps - $name - $ip" >/dev/null

  info "  réseau : ip=$ip/24 gw=$LAB_GW dns=$LAB_DNS"
  qm set "$vmid" \
    --ipconfig0 "ip=$ip/24,gw=$LAB_GW" \
    --nameserver "$LAB_DNS" \
    --searchdomain "$LAB_DOMAIN" \
    --ciuser "$LAB_USER" \
    --sshkeys "$LAB_SSHKEYS" >/dev/null

  # Le template fait 20G ; on agrandit seulement si la VM en demande plus
  # (lab-db 30G, lab-ops 40G). qm resize refuse de réduire : lab-git
  # (15G nominal) garde donc les 20G du template, c'est sans importance.
  if [ "$disk" -gt 20 ]; then
    info "  agrandissement du disque système à ${disk}G"
    qm resize "$vmid" scsi0 "${disk}G"
  fi

  # lab-virt : CPU réel exposé (vmx/svm) pour KVM imbriqué (module 20).
  if [ "$vmid" -eq "$LAB_VIRT_VMID" ]; then
    info "  cpu host (virtualisation imbriquée : nested=1 requis sur le nœud)"
    qm set "$vmid" --cpu host >/dev/null
    local nested
    nested=$(cat /sys/module/kvm_intel/parameters/nested \
             /sys/module/kvm_amd/parameters/nested 2>/dev/null | head -1)
    case "$nested" in
      Y|1) ;;
      *) ko "nested=${nested:-?} sur le nœud : pas de /dev/kvm dans $name (§0.3)" ;;
    esac
  fi

  # Disques bruts supplémentaires pour LVM (lab-db uniquement).
  if [ "$vmid" -eq "$LAB_DB_VMID" ]; then
    local n=1 size
    for size in "${LAB_DB_EXTRA_DISKS[@]}"; do
      info "  disque additionnel scsi$n : ${size}G (non formaté)"
      qm set "$vmid" --scsi"$n" "$LAB_STORAGE:$size" >/dev/null
      n=$((n+1))
    done
  fi

  info "  démarrage"
  qm start "$vmid"
  ok "$name ($vmid) créé et démarré"
}

# ---------------------------------------------------------------------
snapshot_all() {
  local line vmid name
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    qm status "$vmid" >/dev/null 2>&1 \
      || { ko "$name ($vmid) absent"; continue; }
    if qm listsnapshot "$vmid" | grep -qw "$LAB_SNAP"; then
      ok "$name : $LAB_SNAP déjà présent (qm delsnapshot pour refaire)"
      continue
    fi
    if ! wait_agent "$vmid"; then
      ko "$name : agent QEMU muet, la VM est-elle démarrée et bootstrapée ?"
      continue
    fi
    # VM en marche + agent actif : Proxmox gèle le FS pendant l'instantané.
    info "snapshot $LAB_SNAP sur $name ($vmid)"
    qm snapshot "$vmid" "$LAB_SNAP" --vmstate 0 \
      --description "état propre après bootstrap-lab.sh"
    ok "$name : $LAB_SNAP posé"
  done
}

# ---------------------------------------------------------------------
destroy_all() {
  local line vmid name
  echo "Cette action SUPPRIME les 7 VM du lab (pas les templates)."
  read -r -p "Taper OUI pour confirmer : " rep
  [ "$rep" = "OUI" ] || die "abandon"
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    qm status "$vmid" >/dev/null 2>&1 || continue
    info "arrêt et suppression de $name ($vmid)"
    qm stop "$vmid" >/dev/null 2>&1 || true
    qm destroy "$vmid" --purge --destroy-unreferenced-disks 1
  done
}

# ---------------------------------------------------------------------
case "$ACTION" in
  create)
    [ -s "$LAB_SSHKEYS" ] || die "clés publiques absentes : $LAB_SSHKEYS"
    ip link show "$LAB_BRIDGE" >/dev/null 2>&1 \
      || die "bridge $LAB_BRIDGE absent : voir chapitre 0.3"
    for line in "${LAB_VMS[@]}"; do
      # shellcheck disable=SC2086
      create_vm $line
    done
    echo
    echo "Les VM démarrent (compte 60 à 90 s pour cloud-init)."
    echo "Suite : ssh $LAB_USER@10.10.10.10, bootstrap-lab.sh sur chaque VM,"
    echo "puis : bash lab-create.sh snapshot"
    ;;
  snapshot) snapshot_all ;;
  destroy)  destroy_all ;;
  -h|--help) sed -n '2,11p' "$0" ;;
  *) die "action inconnue : $ACTION (create | snapshot | destroy)" ;;
esac
