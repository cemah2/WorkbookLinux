#!/usr/bin/env bash
# lab-status.sh — état des 7 VM du laboratoire vu depuis le nœud Proxmox :
# statut qm, agent QEMU, réponse ping, port SSH, présence de snap-clean.
# À lancer en root sur le nœud Proxmox VE 8. Code retour 0 si tout est vert.
#
# Usage : bash lab-status.sh [--quiet]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-env.sh
. "$HERE/lab-env.sh"

need_root; need_qm
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1

PROBLEMS=0
printf '%-9s %-5s %-12s %-8s %-6s %-5s %-4s %s\n' \
  VM VMID IP STATUT AGENT PING SSH SNAPSHOT
printf '%s\n' "----------------------------------------------------------------"

for line in "${LAB_VMS[@]}"; do
  read -r vmid name ip _ <<< "$line"

  if ! qm status "$vmid" >/dev/null 2>&1; then
    printf '%-9s %-5s %-12s %-8s\n' "$name" "$vmid" "$ip" ABSENT
    PROBLEMS=$((PROBLEMS+1)); continue
  fi

  status="$(qm status "$vmid" | awk '{print $2}')"
  agent=no; ping=no; ssh=no; snap=no
  if [ "$status" = "running" ]; then
    qm agent "$vmid" ping >/dev/null 2>&1 && agent=yes
    ping -c1 -W1 "$ip" >/dev/null 2>&1 && ping=yes
    timeout 2 bash -c "exec 3<>/dev/tcp/$ip/22" 2>/dev/null && ssh=yes
  fi
  qm listsnapshot "$vmid" | grep -qw "$LAB_SNAP" && snap=yes

  printf '%-9s %-5s %-12s %-8s %-6s %-5s %-4s %s\n' \
    "$name" "$vmid" "$ip" "$status" "$agent" "$ping" "$ssh" "$snap"

  [ "$status" = "running" ] && [ "$ssh" = "yes" ] || PROBLEMS=$((PROBLEMS+1))
done

echo
# Le bridge et la règle NAT : les deux causes n°1 de « pas d'internet ».
if ip link show "$LAB_BRIDGE" >/dev/null 2>&1; then
  ok "bridge $LAB_BRIDGE présent ($(ip -4 -br addr show "$LAB_BRIDGE" \
      | awk '{print $3}'))"
else
  ko "bridge $LAB_BRIDGE absent"; PROBLEMS=$((PROBLEMS+1))
fi
if iptables -t nat -C POSTROUTING -s "$LAB_NET" -o "$LAB_WAN_BRIDGE" \
     -j MASQUERADE 2>/dev/null; then
  ok "NAT $LAB_NET -> $LAB_WAN_BRIDGE actif"
else
  ko "règle MASQUERADE absente (voir /etc/network/interfaces, chapitre 0.3)"
  PROBLEMS=$((PROBLEMS+1))
fi
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
  ok "ip_forward = 1"
else
  ko "ip_forward = 0 : les VM ne sortiront pas"; PROBLEMS=$((PROBLEMS+1))
fi
# Virtualisation imbriquée pour lab-virt (module 20) : nested + cpu host.
nested=$(cat /sys/module/kvm_intel/parameters/nested \
         /sys/module/kvm_amd/parameters/nested 2>/dev/null | head -1)
case "$nested" in
  Y|1) ok "KVM nested=$nested (lab-virt pourra charger kvm)" ;;
  *)   ko "KVM nested=${nested:-?} : lab-virt n'aura pas /dev/kvm (chapitre 0.3)"
       PROBLEMS=$((PROBLEMS+1)) ;;
esac
if qm status "$LAB_VIRT_VMID" >/dev/null 2>&1; then
  if qm config "$LAB_VIRT_VMID" | grep -q '^cpu: host'; then
    ok "lab-virt en cpu: host"
  else
    ko "lab-virt sans cpu: host (qm set $LAB_VIRT_VMID --cpu host)"
    PROBLEMS=$((PROBLEMS+1))
  fi
fi

if [ "$QUIET" -eq 0 ]; then
  echo
  echo "Templates :"
  qm list | awk -v u="$TPL_UBUNTU_ID" -v r="$TPL_ROCKY_ID" \
    'NR==1 || $1==u || $1==r'
fi

echo
if [ "$PROBLEMS" -eq 0 ]; then
  echo "Lab opérationnel."
else
  echo "$PROBLEMS point(s) à corriger."
fi
[ "$PROBLEMS" -eq 0 ]
