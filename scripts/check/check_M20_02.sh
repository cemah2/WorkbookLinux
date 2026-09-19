#!/usr/bin/env bash
# check_M20_02.sh — vérifie le lab L20.2 (bridge br0, vm-lan, réseau isolé)
# À lancer sur lab-virt, en tant que mathieu, sans sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L20.2 =="

V="virsh -c qemu:///system"
HOST_IP=10.10.10.16
VMLAN_IP=10.10.10.161

# --- bridge hôte ----------------------------------------------------------
if ip -br link show br0 >/dev/null 2>&1; then
  ok "bridge br0 présent"
  ip -4 -br addr show br0 | grep -q "$HOST_IP/24" \
    && ok "br0 porte $HOST_IP" || ko "br0 ne porte pas $HOST_IP/24"
  PORT=$(ip -o link show master br0 | awk -F': ' '{print $2}' | grep -v '^vnet' | head -1)
  [ -n "$PORT" ] && ok "interface physique en port de br0 : $PORT" \
    || ko "aucune interface physique dans br0 (bridges: br0: interfaces: [eth0])"
  ip -4 -br addr show "${PORT:-eth0}" 2>/dev/null | grep -q '10\.10\.10\.' \
    && ko "l'interface physique porte encore une adresse 10.10.10.x (doublon)" \
    || ok "l'interface physique n'a plus d'adresse"
else
  ko "bridge br0 absent (Netplan bridges: br0)"
fi
[ -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg ] \
  && ok "génération réseau cloud-init désactivée" \
  || ko "cloud-init peut réécrire le Netplan (99-disable-network-config.cfg)"
ping -c1 -W1 10.10.10.10 >/dev/null 2>&1 && ok "lab-adm joignable depuis lab-virt" \
  || ko "lab-adm injoignable : la passerelle/route de br0 ?"

# --- réseau lan côté libvirt ---------------------------------------------
if $V net-info lan >/dev/null 2>&1; then
  $V net-dumpxml lan | grep -q "<forward mode='bridge'/>" \
    && ok "réseau lan en mode bridge" || ko "réseau lan sans <forward mode='bridge'/>"
  $V net-info lan | grep -q 'Autostart: *yes' && ok "réseau lan en autostart" \
    || ko "réseau lan sans autostart"
else
  ko "réseau libvirt 'lan' non défini (net-define xml/net-lan.xml)"
fi

# --- vm-lan ---------------------------------------------------------------
if $V dominfo vm-lan >/dev/null 2>&1; then
  ok "vm-lan définie"
  [ "$($V domstate vm-lan)" = running ] && ok "vm-lan en marche" || ko "vm-lan éteinte"
  $V domiflist vm-lan | grep -qE 'bridge +br0|network +lan' \
    && ok "vm-lan attachée à br0" || ko "vm-lan n'est pas sur br0 (--network bridge=br0)"
  ping -c2 -W1 $VMLAN_IP >/dev/null 2>&1 && ok "vm-lan répond en $VMLAN_IP" \
    || ko "$VMLAN_IP ne répond pas (network-config statique dans le seed ?)"
  timeout 3 bash -c "exec 3<>/dev/tcp/$VMLAN_IP/22" 2>/dev/null \
    && ok "port 22 de vm-lan ouvert" || ko "port 22 de vm-lan fermé"
else
  ko "vm-lan non définie"
fi

# --- réseau isolé ---------------------------------------------------------
if $V net-info isole >/dev/null 2>&1; then
  ok "réseau isole défini"
  $V net-info isole | grep -q 'Active: *yes' && ok "réseau isole actif" \
    || ko "réseau isole inactif (virsh net-start isole)"
  $V net-dumpxml isole | grep -q '<forward' \
    && ko "le réseau isole a un <forward> : il n'est pas isolé" \
    || ok "réseau isole sans <forward> (isolé)"
  $V net-dumpxml isole | grep -q "address='10.20.0.1'" && ok "isole en 10.20.0.0/24" \
    || ko "isole n'est pas en 10.20.0.1/24"
  for vm in vm-01 vm-lan; do
    $V dumpxml --inactive $vm 2>/dev/null | grep -q "<source network='isole'/>" \
      && ok "$vm a une interface persistante sur isole" \
      || ko "$vm sans interface persistante sur isole (attach-interface --persistent)"
  done
  BR=$($V net-dumpxml isole | grep -o "bridge name='[^']*'" | cut -d"'" -f2)
  [ -n "$BR" ] && ip -br link show "$BR" >/dev/null 2>&1 \
    && ok "bridge $BR créé par libvirt" || ko "bridge du réseau isole absent"
else
  ko "réseau isole non défini (net-define xml/net-isole.xml)"
fi

# --- rapport --------------------------------------------------------------
R="$HOME/lab20/rapports/res-77.md"
[ -s "$R" ] && grep -qi 'macvtap' "$R" && ok "rapport res-77.md avec les quatre modes" \
  || ko "rapport $R absent ou incomplet (NAT, bridge, isolé, macvtap)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
