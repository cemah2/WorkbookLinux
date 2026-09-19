#!/usr/bin/env bash
# check_M13_03.sh — vérifie le lab L13.3 (VXLAN, WireGuard, mesures)
# À lancer sur lab-web (VXLAN) et sur lab-adm (WireGuard + rapport).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L13.3 =="

HOSTN=$(hostname -s)
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab13/rapports/overlay.md"

case "$HOSTN" in
  lab-web|lab-db)
    [ "$HOSTN" = lab-web ] && PEER=192.168.42.12 || PEER=192.168.42.11
    D=$(ip -d link show vxlan0 2>/dev/null)
    if [ -n "$D" ]; then
      ok "vxlan0 existe"
      echo "$D" | grep -q 'vxlan id 42' && ok "VNI 42" || ko "VNI différent de 42"
      echo "$D" | grep -q 'dstport 4789' && ok "port 4789" || ko "port UDP ≠ 4789"
      echo "$D" | grep -q 'mtu 1450' && ok "MTU 1450" \
        || ko "MTU de vxlan0 ≠ 1450 (ip -d link show vxlan0)"
      ip addr show dev vxlan0 | grep -q '192\.168\.42\.' \
        && ok "adresse 192.168.42.x posée" || ko "pas d'adresse 192.168.42.x"
      ping -c1 -W2 "$PEER" >/dev/null 2>&1 \
        && ok "le pair $PEER répond à travers le VXLAN" \
        || ko "$PEER ne répond pas via vxlan0 (pair monté ? remote ?)"
      ping -M do -s 1422 -c1 -W2 "$PEER" >/dev/null 2>&1 \
        && ok "un paquet de 1450 o passe sans fragmentation" \
        || ko "ping -M do -s 1422 échoue : MTU incohérent quelque part"
    else
      ko "vxlan0 absent (ip link add vxlan0 type vxlan ...)"
    fi
    grep -qs 'vxlan' /etc/netplan/*.yaml \
      && ok "un bloc tunnels: vxlan existe dans Netplan" \
      || ko "VXLAN non persistant (Netplan tunnels: mode vxlan)"
    ip link show vxlan1 >/dev/null 2>&1 \
      && ko "vxlan1 (multicast) est encore là : à supprimer" \
      || ok "vxlan1 nettoyé"
    tc qdisc show dev ens18 2>/dev/null | grep -q netem \
      && ko "un netem traîne encore sur ens18 (tc qdisc del dev ens18 root)" \
      || ok "pas de netem résiduel sur ens18"
    ;;
  lab-adm|lab-ops)
    [ "$HOSTN" = lab-adm ] && PEER=10.99.0.2 || PEER=10.99.0.1
    if ip link show wg0 >/dev/null 2>&1; then
      ok "wg0 existe"
      W=$(sudo wg show wg0 2>/dev/null)
      echo "$W" | grep -q 'latest handshake' \
        && ok "poignée de main WireGuard effectuée" \
        || ko "aucun handshake (clés ? Endpoint ? port 51820 ?)"
      ping -c1 -W2 "$PEER" >/dev/null 2>&1 \
        && ok "le pair $PEER répond via wg0" || ko "$PEER injoignable via wg0"
      systemctl is-enabled -q wg-quick@wg0 2>/dev/null \
        && ok "wg-quick@wg0 activé au démarrage" \
        || ko "wg-quick@wg0 n'est pas enable"
      [ "$(stat -c %a /etc/wireguard/wg0.conf 2>/dev/null)" = 600 ] \
        && ok "wg0.conf en 0600" || ko "wg0.conf doit être en 0600 (clé privée)"
    else
      ko "wg0 absent (wg-quick up wg0)"
    fi
    ;;
  *) note "hôte $HOSTN : rien à vérifier ici" ;;
esac

# --- rapport (lab-adm ou lab-web) ------------------------------------------
if [ -f "$RAP" ]; then
  n=$(grep -ciE 'bits?/s|Gbit|Mbit' "$RAP")
  [ "$n" -ge 4 ] && ok "$n lignes de mesures de débit dans overlay.md" \
    || ko "moins de 4 mesures de débit dans $RAP"
  grep -qi 'retr' "$RAP" && ok "la colonne Retr est reportée" \
    || ko "le rapport ne mentionne pas Retr"
  grep -qiE 'flannel|calico|cilium' "$RAP" \
    && ok "le lien avec les CNI est fait" \
    || ko "conclusion sans lien avec flannel/Calico/Cilium"
else
  note "rapport $RAP absent sur cet hôte"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
