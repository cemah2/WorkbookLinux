#!/usr/bin/env bash
# lab-nat.sh — règles iptables du réseau de lab (nœud Proxmox VE 8).
#   * NAT de sortie : 10.10.10.0/24 -> internet via vmbr0 (MASQUERADE)
#   * redirection  : <IP du nœud>:2222 -> lab-adm (10.10.10.10):22
#   * redirection  : <IP du nœud>:3000 -> lab-git (10.10.10.15):3000 (Gitea)
# Appelé par /etc/network/interfaces (post-up / post-down de vmbr1),
# volontairement autonome : aucun fichier sourcé, tout est ici.
#
# Usage : lab-nat.sh up | down | status
set -euo pipefail

LAB_NET="${LAB_NET:-10.10.10.0/24}"
LAB_ADM="${LAB_ADM:-10.10.10.10}"
WAN_IF="${LAB_WAN_BRIDGE:-vmbr0}"
LAN_NET="${LAN_NET:-192.168.1.0/24}"   # ton LAN : pas de NAT vers lui
BASTION_PORT="${BASTION_PORT:-2222}"
LAB_GIT="${LAB_GIT:-10.10.10.15}"
GITEA_PORT="${GITEA_PORT:-3000}"       # 0 pour ne pas publier Gitea

# rule ACTION TABLE CHAINE ARGS...  — idempotent grâce à -C
rule() {
  local action="$1" table="$2" chain="$3"; shift 3
  case "$action" in
    add) iptables -t "$table" -C "$chain" "$@" 2>/dev/null \
           || iptables -t "$table" -A "$chain" "$@" ;;
    del) if iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
           iptables -t "$table" -D "$chain" "$@"
         fi ;;
  esac
  return 0
}

apply() {
  local a="$1"
  # 1. les VM sortent sur internet avec l'IP du nœud
  rule "$a" nat POSTROUTING -s "$LAB_NET" ! -d "$LAN_NET" -o "$WAN_IF" \
       -j MASQUERADE
  # 2. le port 2222 du nœud mène au SSH de lab-adm (bastion du lab)
  rule "$a" nat PREROUTING -i "$WAN_IF" -p tcp --dport "$BASTION_PORT" \
       -j DNAT --to-destination "$LAB_ADM:22"
  # 3. FORWARD : utile seulement si la politique par défaut est DROP
  rule "$a" filter FORWARD -s "$LAB_NET" -j ACCEPT
  rule "$a" filter FORWARD -d "$LAB_NET" -m conntrack \
       --ctstate RELATED,ESTABLISHED -j ACCEPT
  rule "$a" filter FORWARD -d "$LAB_ADM" -p tcp --dport 22 -j ACCEPT
  # 4. le port 3000 du nœud mène à l'interface web de Gitea (chapitre 0.8)
  if [ "$GITEA_PORT" != 0 ]; then
    rule "$a" nat PREROUTING -i "$WAN_IF" -p tcp --dport "$GITEA_PORT" \
         -j DNAT --to-destination "$LAB_GIT:3000"
    rule "$a" filter FORWARD -d "$LAB_GIT" -p tcp --dport 3000 -j ACCEPT
  fi
}

case "${1:-}" in
  up)
    sysctl -q -w net.ipv4.ip_forward=1
    apply add ;;
  down)
    apply del ;;
  status)
    echo "ip_forward = $(cat /proc/sys/net/ipv4/ip_forward)"
    iptables -t nat -S | grep -E "$LAB_NET|$LAB_ADM|$LAB_GIT" \
      || echo "aucune règle NAT"
    ;;
  *) echo "usage : $0 up|down|status" >&2; exit 1 ;;
esac
