#!/usr/bin/env bash
# check_M13_01.sh — vérifie le lab L13.1 (mini-Docker : netns, bridge, NAT)
# À lancer sur lab-adm, avec sudo (netns et nft exigent root).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L13.1 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BIN="$HOMEDIR/lab13/bin/minidocker.sh"
RAP="$HOMEDIR/lab13/rapports/minidocker.md"

# --- 1. le script et ses trois sous-commandes ---------------------------
if [ -x "$BIN" ] && grep -qE '^\s*(up|down|status)\)' "$BIN"; then
  ok "minidocker.sh existe, exécutable, avec up/down/status"
else
  ko "minidocker.sh absent, non exécutable ou sans up/down/status : $BIN"
fi

# --- 2. les objets réseau ----------------------------------------------
for ns in c1 c2 c3; do
  ip netns list 2>/dev/null | grep -qw "$ns" \
    && ok "netns $ns présent" \
    || ko "netns $ns absent (ip netns add / lance minidocker.sh up)"
done

if ip -d link show br-lab 2>/dev/null | grep -q 'bridge'; then
  ok "bridge br-lab présent"
  ip addr show dev br-lab | grep -q '172\.20\.0\.1/24' \
    && ok "br-lab porte 172.20.0.1/24" \
    || ko "br-lab n'a pas l'adresse 172.20.0.1/24"
  n=$(bridge link show 2>/dev/null | grep -c 'master br-lab')
  [ "$n" -ge 3 ] && ok "$n ports raccordés au bridge" \
    || ko "seulement $n port(s) sur br-lab (bridge link show)"
else
  ko "bridge br-lab absent"
fi

for i in 1 2 3; do
  ip -n c$i addr show dev eth0 2>/dev/null | grep -q "172\.20\.0\.1$i/24" \
    && ok "c$i : eth0 = 172.20.0.1$i/24" \
    || ko "c$i : eth0 sans 172.20.0.1$i/24"
done
ip -n c1 link show lo 2>/dev/null | grep -q 'UP' \
  && ok "lo monté dans c1" || ko "lo est DOWN dans c1 (ip -n c1 link set lo up)"
ip -n c1 route show default 2>/dev/null | grep -q '172\.20\.0\.1' \
  && ok "route par défaut de c1 via 172.20.0.1" \
  || ko "c1 n'a pas de route par défaut via 172.20.0.1"

# --- 3. forwarding et NAT ----------------------------------------------
[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ] \
  && ok "ip_forward = 1" || ko "net.ipv4.ip_forward vaut 0"

RS=$(nft list ruleset 2>/dev/null)
echo "$RS" | grep -q 'masquerade' \
  && ok "règle masquerade présente" \
  || ko "aucune règle masquerade dans nft list ruleset"
echo "$RS" | grep -q 'dnat to 172\.20\.0\.11:8000' \
  && ok "DNAT vers 172.20.0.11:8000 présent" \
  || ko "pas de dnat to 172.20.0.11:8000 (chaîne prerouting, table nat)"
echo "$RS" | grep -q 'ct state established,related accept' \
  && ok "règle stateful established,related présente" \
  || ko "il manque ct state established,related accept"
echo "$RS" | grep -q 'hook output' \
  && ok "chaîne nat output (accès local au port publié)" \
  || ko "pas de chaîne 'type nat hook output' : curl local vers 8080 échouera"

# --- 4. les résultats observables ----------------------------------------
if ip netns exec c1 curl -s -m 3 http://10.10.10.11/ >/dev/null 2>&1; then
  ok "c1 sort vers lab-web en NAT"
else
  ko "c1 ne joint pas http://10.10.10.11/ (ip_forward ? masquerade ? nginx ?)"
fi
if curl -s -m 3 http://10.10.10.10:8080/ 2>/dev/null | grep -q 'c1'; then
  ok "port publié joignable depuis lab-adm (10.10.10.10:8080)"
else
  ko "curl http://10.10.10.10:8080/ échoue localement (chaîne nat output ?)"
fi
if ip netns exec c2 curl -s -m 3 http://10.10.10.10:8080/ 2>/dev/null \
   | grep -q 'c1'; then
  ok "hairpin : c2 joint le port publié"
else
  ko "c2 ne joint pas 10.10.10.10:8080 (masquerade de retour ct status dnat ?)"
fi
note "vérifie aussi depuis lab-web : curl http://10.10.10.10:8080/"

# --- 5. rapport -----------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -cv '^[[:space:]]*$' "$RAP")" -ge 12 ]; then
  ok "rapport minidocker.md rédigé"
  grep -qi 'trace' "$RAP" && ok "la trace nft monitor est documentée" \
    || ko "le rapport ne mentionne pas la trace (nft monitor trace)"
else
  ko "rapport absent ou trop court : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
