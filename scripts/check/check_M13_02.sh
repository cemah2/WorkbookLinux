#!/usr/bin/env bash
# check_M13_02.sh — vérifie le lab L13.2 (policy routing, deux passerelles)
# À lancer sur lab-adm, avec sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L13.2 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab13/rapports/policy-routing.md"

# --- 1. la maquette ---------------------------------------------------
for ns in c-bur gw1 dual gw2 c-prod; do
  ip netns list 2>/dev/null | grep -qw "$ns" \
    && ok "netns $ns présent" || ko "netns $ns absent"
done
ip -n dual addr 2>/dev/null | grep -q '10\.10\.11\.2/24' \
  && ok "dual : eth1 = 10.10.11.2/24" || ko "dual sans 10.10.11.2/24"
ip -n dual addr 2>/dev/null | grep -q '10\.10\.12\.2/24' \
  && ok "dual : eth2 = 10.10.12.2/24" || ko "dual sans 10.10.12.2/24"
for gw in gw1 gw2; do
  [ "$(ip netns exec $gw sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ] \
    && ok "$gw relaie (ip_forward=1)" \
    || ko "$gw ne relaie pas (ip_forward dans le netns)"
done

# --- 2. la table nommée et la règle -------------------------------------
if grep -qsE '^[0-9]+[[:space:]]+[a-z]' /etc/iproute2/rt_tables.d/*.conf \
   /etc/iproute2/rt_tables 2>/dev/null; then
  ok "une table de routage nommée est déclarée"
else
  ko "aucune table nommée (/etc/iproute2/rt_tables.d/*.conf)"
fi
RULES=$(ip -n dual rule show 2>/dev/null)
if echo "$RULES" | grep -qE 'from 10\.10\.12\.2 lookup|fwmark .* lookup'; then
  ok "dual : règle ip rule (par source ou par marque) en place"
else
  ko "dual : aucune règle from 10.10.12.2 / fwmark (ip -n dual rule)"
fi
TBL=$(echo "$RULES" | grep -oE 'lookup [a-z0-9]+' | grep -vE 'local|main|default' \
      | head -1 | awk '{print $2}')
if [ -n "$TBL" ] && ip -n dual route show table "$TBL" 2>/dev/null \
   | grep -q 'default via 10\.10\.12\.1'; then
  ok "table $TBL : route par défaut via 10.10.12.1"
  ip -n dual route show table "$TBL" | grep -q '10\.10\.12\.0/24' \
    && ok "table $TBL : route connectée 10.10.12.0/24 présente" \
    || ko "table $TBL sans la route connectée 10.10.12.0/24 (cf. Q13.4)"
else
  ko "la table dédiée n'a pas de default via 10.10.12.1"
fi

# --- 3. la preuve : route get, ping, TCP --------------------------------
# réponse émise localement par dual : pas de iif (source locale = martienne)
if ip -n dual route get 192.168.2.10 from 10.10.12.2 2>/dev/null \
   | grep -q 'via 10\.10\.12\.1 dev eth2'; then
  ok "ip route get : la réponse à c-prod sort par eth2"
else
  ko "ip route get 192.168.2.10 from 10.10.12.2 ne sort pas via 10.10.12.1"
fi
if ip netns exec c-prod ping -c1 -W1 10.10.12.2 >/dev/null 2>&1; then
  ok "ping c-prod -> dual"
else
  ko "c-prod ne ping pas 10.10.12.2"
fi
ip netns exec dual timeout 4 nc -l 9009 >/dev/null 2>&1 &
sleep 0.5
if ip netns exec c-prod nc -z -w 2 10.10.12.2 9009 >/dev/null 2>&1; then
  ok "TCP c-prod -> dual:9009 s'établit"
else
  ko "TCP depuis c-prod échoue : la réponse repart par la mauvaise interface ?"
fi
wait 2>/dev/null

# --- 4. rapport ----------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -cv '^[[:space:]]*$' "$RAP")" -ge 10 ]; then
  ok "rapport policy-routing.md rédigé"
  grep -qiE 'asym|rp_filter' "$RAP" \
    && ok "route asymétrique / rp_filter expliqués" \
    || ko "le rapport n'explique ni la route asymétrique ni rp_filter"
else
  ko "rapport absent ou trop court : $RAP"
fi
note "la variante par marque (étape 5) et Netplan (étape 7) sont à relire"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
