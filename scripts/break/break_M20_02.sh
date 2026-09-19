#!/usr/bin/env bash
# break_M20_02.sh — panne BF20.2 : « après la maintenance réseau, vm-lan ne
# démarre plus ». Réécrit le Netplan de lab-virt sans le bridge br0 (l'adresse
# revient sur l'interface physique : lab-virt reste joignable), puis arrête
# vm-lan. Idempotent. Sauvegarde /etc/netplan dans /root/.breakfix-backup/.
# À lancer avec sudo sur lab-virt (L20.2 fait). Garde qm terminal 9007 ouvert.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
V="virsh -c qemu:///system"
SAUV=/root/.breakfix-backup/M20_02
mkdir -p "$SAUV"

$V dominfo vm-lan >/dev/null 2>&1 || { echo "vm-lan n'existe pas : fais L20.2 d'abord" >&2; exit 1; }

if ip link show br0 >/dev/null 2>&1; then
  PORT=$(ip -o link show master br0 | awk -F': ' '{print $2}' | grep -v '^vnet' | head -1)
  [ -n "$PORT" ] || { echo "br0 sans port physique : Netplan inattendu, abandon" >&2; exit 1; }
  ADDR=$(ip -4 -o addr show br0 | awk '{print $4}' | head -1)
  [ -n "$ADDR" ] || ADDR=10.10.10.16/24
  MAC=$(cat "/sys/class/net/$PORT/address")
  [ -e "$SAUV/netplan-saved" ] || { cp -a /etc/netplan/. "$SAUV/"; touch "$SAUV/netplan-saved"; }

  # « simplification » : plus de bridge, l'adresse revient sur l'interface
  rm -f /etc/netplan/*.yaml
  cat > /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  ethernets:
    $PORT:
      match:
        macaddress: $MAC
      set-name: $PORT
      addresses: [$ADDR]
      routes:
        - to: default
          via: 10.10.10.1
      nameservers:
        addresses: [10.10.10.1]
        search: [lab.local]
EOF
  chmod 600 /etc/netplan/50-cloud-init.yaml
  $V destroy vm-lan >/dev/null 2>&1 || true
  netplan apply 2>/dev/null || true
  ip link del br0 2>/dev/null || true
  netplan apply 2>/dev/null || true
else
  echo "br0 est déjà absent : rien à refaire"
  $V destroy vm-lan >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : un collègue a « simplifié » le Netplan de lab-virt pour
régler un problème de DNS. lab-virt répond toujours en 10.10.10.16, mais
« virsh start vm-lan » échoue avec une erreur qui parle de MTU et de
périphérique introuvable. vm-01 démarre normalement. Interdit de rattacher
vm-lan au réseau default ou de modifier son XML.
EOF
