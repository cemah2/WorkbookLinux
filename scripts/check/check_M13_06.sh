#!/usr/bin/env bash
# check_M13_06.sh — vérifie le défi D13 (minicloud)
# À lancer sur lab-adm, avec sudo, après minicloud.sh up.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D13 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BIN="$HOMEDIR/lab13/bin/minicloud.sh"
RAP="$HOMEDIR/lab13/rapports/minicloud.md"
ZONE="$HOMEDIR/lab13/dns/minicloud.zone.inc"

[ -x "$BIN" ] && head -1 "$BIN" | grep -q bash && ok "minicloud.sh exécutable" \
  || ko "minicloud.sh absent ou non exécutable"
grep -q 'set -euo pipefail' "$BIN" 2>/dev/null \
  && ok "set -euo pipefail" || ko "set -euo pipefail manquant"
for c in up down status test; do
  grep -qE "^\s*$c\)|\b$c\b\)" "$BIN" 2>/dev/null \
    && ok "sous-commande $c" || ko "sous-commande $c absente"
done

for ns in rtr t1-web t1-db t2-web t2-db; do
  ip netns list 2>/dev/null | grep -qw "$ns" \
    && ok "netns $ns" || ko "netns $ns absent (minicloud.sh up ?)"
done
for b in br-t1 br-t2; do
  ip -d link show "$b" 2>/dev/null | grep -q bridge \
    && ok "bridge $b" || ko "bridge $b absent"
done
ip -n rtr addr 2>/dev/null | grep -q '10\.100\.1\.1/24' \
  && ok "rtr : 10.100.1.1" || ko "rtr sans 10.100.1.1/24"
ip -n rtr addr 2>/dev/null | grep -q '10\.100\.2\.1/24' \
  && ok "rtr : 10.100.2.1" || ko "rtr sans 10.100.2.1/24"
ip -n rtr addr 2>/dev/null | grep -q '10\.100\.0\.2/30' \
  && ok "rtr : transit 10.100.0.2/30" || ko "rtr sans 10.100.0.2/30"
[ "$(ip netns exec rtr sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ] \
  && ok "rtr relaie" || ko "ip_forward=0 dans rtr"
ip route show 2>/dev/null | grep -q '10\.100\.1\.0/24 via 10\.100\.0\.2' \
  && ok "route de retour vers 10.100.1.0/24 via rtr" \
  || ko "pas de route 10.100.1.0/24 via 10.100.0.2 dans le netns racine"

# nftables : map de publication, masquerade racine, isolation dans rtr
nft list ruleset 2>/dev/null | grep -qE 'map .*\{|dnat .* map @' \
  && ok "publication par map nftables" \
  || ko "aucune map nftables utilisée par une règle dnat"
nft list ruleset 2>/dev/null | grep -q '8082 : 10\.100\.2\.11 \. 8000' \
  && ok "8082 -> 10.100.2.11:8000 dans la map" \
  || ko "l'élément 8082 : 10.100.2.11 . 8000 manque"
ip netns exec rtr nft list ruleset 2>/dev/null | grep -q masquerade \
  && ok "NAT de sortie dans rtr" || ko "pas de masquerade dans rtr"
ip netns exec rtr nft list ruleset 2>/dev/null | grep -q 'established,related' \
  && ok "rtr : pare-feu stateful" || ko "rtr : pas de established,related"

# comportements
ip netns exec t1-web ping -c1 -W1 10.100.1.12 >/dev/null 2>&1 \
  && ok "t1-web -> t1-db" || ko "t1-web ne joint pas t1-db"
if ip netns exec t1-web ping -c1 -W1 10.100.2.12 >/dev/null 2>&1; then
  ko "t1-web joint t2-db : isolation absente (forward dans rtr)"
else
  ok "isolation t1 -> t2"
fi
ip netns exec t1-web curl -s -m 3 http://10.10.10.11/ >/dev/null 2>&1 \
  && ok "t1-web sort vers le lab (double NAT)" \
  || ko "t1-web ne joint pas http://10.10.10.11/ (NAT rtr + NAT racine ?)"
lat=$(ip netns exec t2-web ping -c3 -i 0.2 10.100.2.12 2>/dev/null \
      | awk -F/ '/rtt/ {print $5}')
if [ -n "$lat" ] && awk -v l="$lat" 'BEGIN{exit !(l>=30)}'; then
  ok "latence t2-web -> t2-db = $lat ms (netem)"
else
  ko "latence t2-web -> t2-db trop faible ou nulle ('$lat') : tc netem ?"
fi
if ip netns exec t1-web curl -s -m 3 http://10.100.1.11:8000/ \
   | grep -q t1-web; then
  ok "t1-web sert sa page"
else
  ko "pas de serveur HTTP dans t1-web sur 8000"
fi
note "vérifie depuis lab-web : curl http://10.10.10.10:8081/ et :8082/"

[ -s "$ZONE" ] && grep -q 't2-web' "$ZONE" \
  && ok "fragment de zone minicloud.zone.inc généré" \
  || ko "fragment $ZONE absent ou incomplet"
dig +short +time=2 t1-web.cloud.lab.local @10.10.10.53 2>/dev/null \
  | grep -q '10\.100\.1\.11' \
  && ok "t1-web.cloud.lab.local résolu par le DNS du lab" \
  || ko "t1-web.cloud.lab.local ne résout pas (\$INCLUDE + serial + reload ?)"

if [ -s "$RAP" ] && [ "$(grep -cv '^[[:space:]]*$' "$RAP")" -ge 15 ]; then
  ok "rapport minicloud.md rédigé"
  grep -qi 'trace id' "$RAP" && ok "trace nft monitor incluse" \
    || ko "pas de trace 'trace id ...' dans le rapport"
  grep -qiE 'qrouter|openstack' "$RAP" && grep -qiE 'nodeport|kubernetes' "$RAP" \
    && ok "parallèle OpenStack / Kubernetes fait" \
    || ko "le parallèle OpenStack / Kubernetes manque"
else
  ko "rapport absent ou trop court : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
