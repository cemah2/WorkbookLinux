#!/usr/bin/env bash
# make-templates.sh — construit les templates cloud-init du laboratoire
#   9000 tpl-ubuntu-2404  (Ubuntu Server 24.04 LTS, image cloud officielle)
#   9010 tpl-rocky-9      (Rocky Linux 9 GenericCloud)
# À lancer en root sur le nœud Proxmox VE 8.
# Idempotent : un template existant est laissé tel quel (sauf --force).
#
# Usage : bash make-templates.sh [--force] [ubuntu|rocky|all]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-env.sh
. "$HERE/lab-env.sh"

need_root; need_qm

FORCE=0
WHAT=all
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    ubuntu|rocky|all) WHAT="$arg" ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "argument inconnu : $arg" ;;
  esac
done

mkdir -p "$LAB_DIR"
[ -s "$LAB_SSHKEYS" ] \
  || die "fichier de clés publiques absent : $LAB_SSHKEYS (voir chapitre 0.4)"

# ---------------------------------------------------------------------
# build_template VMID NOM URL
# ---------------------------------------------------------------------
build_template() {
  local vmid="$1" name="$2" url="$3"
  local img
  img="$LAB_DIR/$(basename "$url")"

  if qm status "$vmid" >/dev/null 2>&1; then
    if [ "$FORCE" -eq 1 ]; then
      info "suppression de l'ancien template $vmid"
      qm destroy "$vmid" --purge
    else
      ok "template $vmid ($name) déjà présent (--force pour le refaire)"
      return 0
    fi
  fi

  info "téléchargement de l'image ($name)"
  # -N : ne retélécharge que si l'image distante est plus récente
  wget -q -N -P "$LAB_DIR" "$url"

  # Le paquet qemu-guest-agent n'est pas dans les images cloud. Si
  # libguestfs-tools est installé sur le nœud, on l'injecte tout de suite ;
  # sinon bootstrap-lab.sh l'installera au premier démarrage.
  if command -v virt-customize >/dev/null 2>&1; then
    info "injection de qemu-guest-agent dans l'image (virt-customize)"
    virt-customize -q -a "$img" --install qemu-guest-agent \
      --run-command 'systemctl enable qemu-guest-agent' || true
  fi

  info "création de la VM $vmid ($name)"
  qm create "$vmid" \
    --name "$name" \
    --ostype l26 \
    --cpu host --cores 2 --sockets 1 \
    --memory 2048 \
    --scsihw virtio-scsi-pci \
    --net0 "virtio,bridge=$LAB_BRIDGE" \
    --agent enabled=1 \
    --serial0 socket --vga serial0

  info "import du disque dans $LAB_STORAGE"
  # PVE 8 : « qm disk import » ; « qm importdisk » reste accepté (alias).
  qm disk import "$vmid" "$img" "$LAB_STORAGE" --format raw >/dev/null

  # Le disque importé apparaît en unused0 ; son nom dépend du stockage
  # (local-lvm:vm-9000-disk-0, local:9000/vm-9000-disk-0.raw, ...).
  local disk
  disk="$(qm config "$vmid" | awk -F': ' '/^unused0:/ {print $2}')"
  [ -n "$disk" ] || die "disque importé introuvable dans la config de $vmid"

  info "attachement du disque ($disk) et du lecteur cloud-init"
  qm set "$vmid" \
    --scsi0 "${disk},discard=on,ssd=1" \
    --ide2 "$LAB_STORAGE:cloudinit" \
    --boot order=scsi0

  info "paramètres cloud-init par défaut"
  qm set "$vmid" \
    --ciuser "$LAB_USER" \
    --sshkeys "$LAB_SSHKEYS" \
    --ipconfig0 ip=dhcp \
    --nameserver "$LAB_DNS" \
    --searchdomain "$LAB_DOMAIN" \
    --ciupgrade 0

  # Les images cloud font ~2 à 10 Go : on met le disque à 20 Go, la taille
  # standard des VM du lab. cloud-init (growpart) agrandit / au boot.
  info "redimensionnement du disque système à 20G"
  qm resize "$vmid" scsi0 20G

  info "conversion en template"
  qm template "$vmid"
  ok "template $vmid ($name) prêt"
}

case "$WHAT" in
  ubuntu)
    build_template "$TPL_UBUNTU_ID" "$TPL_UBUNTU_NAME" "$TPL_UBUNTU_URL" ;;
  rocky)
    build_template "$TPL_ROCKY_ID" "$TPL_ROCKY_NAME" "$TPL_ROCKY_URL" ;;
  all)
    build_template "$TPL_UBUNTU_ID" "$TPL_UBUNTU_NAME" "$TPL_UBUNTU_URL"
    build_template "$TPL_ROCKY_ID"  "$TPL_ROCKY_NAME"  "$TPL_ROCKY_URL"
    ;;
esac

echo
qm list | awk 'NR==1 || $1 ~ /^90[01]0$/'
echo "Étape suivante : bash lab-create.sh"
