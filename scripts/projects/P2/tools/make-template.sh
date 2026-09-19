#!/usr/bin/env bash
# make-template.sh — crée le template cloud-init Ubuntu 24.04 (VMID 9000)
# À lancer sur l'hôte Proxmox (root). Idempotent. Identique au module 20.
set -euo pipefail
VMID=${VMID:-9000}
NAME=${NAME:-ubuntu-2404-tpl}
STORE=${STORE:-local-lvm}
BRIDGE=${BRIDGE:-vmbr1}
IMG=noble-server-cloudimg-amd64.img
URL=https://cloud-images.ubuntu.com/noble/current/$IMG

if qm status "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID existe déjà ($(qm config "$VMID" | grep -E '^name'))"
  exit 0
fi
cd /var/lib/vz/template
[ -f "$IMG" ] || wget -q "$URL"
qm create "$VMID" --name "$NAME" --memory 2048 --cores 2 \
  --net0 "virtio,bridge=$BRIDGE" --scsihw virtio-scsi-pci \
  --ostype l26 --agent enabled=1 --serial0 socket --vga serial0
qm importdisk "$VMID" "$IMG" "$STORE" >/dev/null
qm set "$VMID" --scsi0 "$STORE:vm-$VMID-disk-0,discard=on" \
  --ide2 "$STORE:cloudinit" --boot order=scsi0 --ipconfig0 ip=dhcp
qm template "$VMID"
# snippets : nécessaire pour les user-data personnalisés d'OpenTofu
pvesm set local --content backup,iso,vztmpl,snippets
echo "template $NAME ($VMID) prêt ; snippets activés sur 'local'"
