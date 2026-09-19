#!/usr/bin/env bash
# check_M13_04.sh — vérifie le lab L13.4 (Unbound, BIND9, secondaire, clients)
# À lancer sur n'importe quelle VM du lab ; tests complémentaires sur lab-ops
# et lab-adm.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L13.4 =="

HOSTN=$(hostname -s)
RES=10.10.10.53; NS1=10.10.10.14; NS2=10.10.10.10
command -v dig >/dev/null || { echo "dig manquant (bind9-dnsutils)" >&2; exit 1; }

# --- 1. l'autoritaire ----------------------------------------------------
A=$(dig @$NS1 +time=2 +tries=1 lab-web.lab.local A 2>/dev/null)
echo "$A" | grep -q 'flags: qr aa' \
  && ok "ns1 ($NS1) répond avec autorité (aa)" \
  || ko "ns1 ne répond pas avec le flag aa (named actif ? listen-on ?)"
echo "$A" | grep -q '10\.10\.10\.11' \
  && ok "lab-web.lab.local -> 10.10.10.11" || ko "lab-web.lab.local faux/absent"
dig @$NS1 +short +time=2 -x 10.10.10.12 2>/dev/null | grep -q 'lab-db\.lab\.local\.' \
  && ok "zone inverse : 10.10.10.12 -> lab-db.lab.local." \
  || ko "PTR de 10.10.10.12 absent (zone 10.10.10.in-addr.arpa)"
dig @$NS1 +short +time=2 www.lab.local CNAME 2>/dev/null | grep -q 'lab-web' \
  && ok "www est un CNAME de lab-web" || ko "CNAME www manquant"
dig @$NS1 +short +time=2 lab.local MX 2>/dev/null | grep -q . \
  && ok "MX présent" || ko "MX manquant à l'apex"
dig @$NS1 +short +time=2 _http._tcp.lab.local SRV 2>/dev/null | grep -q '80' \
  && ok "SRV _http._tcp présent" || ko "SRV _http._tcp.lab.local manquant"
dig @$NS1 +short +time=2 lab-web.lab.local AAAA 2>/dev/null | grep -q 'fd00' \
  && ok "AAAA ULA présent" || ko "AAAA fd00:10:10:10::11 manquant"
dig @$NS1 +time=2 +tries=1 www.ubuntu.com 2>/dev/null | grep -q 'REFUSED' \
  && ok "ns1 refuse la récursion (recursion no)" \
  || ko "ns1 ne répond pas REFUSED sur un nom externe : recursion no ?"

# --- 2. le secondaire ---------------------------------------------------------
S1=$(dig @$NS1 +short +time=2 lab.local SOA 2>/dev/null | awk '{print $3}')
S2=$(dig @$NS2 +short +time=2 lab.local SOA 2>/dev/null | awk '{print $3}')
if [ -n "$S2" ]; then
  ok "ns2 ($NS2) sert la zone (serial $S2)"
  [ "$S1" = "$S2" ] && ok "serials identiques sur ns1 et ns2" \
    || ko "serials différents : ns1=$S1 ns2=$S2 (transfert ? notify ?)"
else
  ko "ns2 ($NS2) ne répond pas pour lab.local (secondaire non configuré ?)"
fi
dig @$NS2 +short +time=2 -x 10.10.10.11 2>/dev/null | grep -q 'lab-web' \
  && ok "ns2 sert aussi la zone inverse" || ko "zone inverse absente sur ns2"

# --- 3. le résolveur ---------------------------------------------------------
R=$(dig @$RES +time=3 +tries=1 www.ubuntu.com A 2>/dev/null)
echo "$R" | grep -q 'NOERROR' \
  && ok "résolveur $RES résout un nom public" \
  || ko "$RES ne résout pas www.ubuntu.com (unbound actif ? interface ?)"
echo "$R" | grep -q 'flags: qr rd ra ad' \
  && ok "validation DNSSEC active (flag ad)" \
  || ko "pas de flag ad : la validation DNSSEC n'est pas effective"
dig @$RES +short +time=2 lab-db.lab.local 2>/dev/null | grep -q '10\.10\.10\.12' \
  && ok "résolveur : lab-db.lab.local via la stub-zone" \
  || ko "$RES ne résout pas lab-db.lab.local (stub-zone ? domain-insecure ?)"
dig @$RES +short +time=2 -x 10.10.10.12 2>/dev/null | grep -q 'lab-db' \
  && ok "résolveur : inverse 10.10.10.12" \
  || ko "$RES ne résout pas l'inverse (local-zone 10.in-addr.arpa nodefault ?)"
dig @$RES +time=3 +tries=1 dnssec-failed.org A 2>/dev/null | grep -q 'SERVFAIL' \
  && ok "une zone mal signée est refusée (SERVFAIL)" \
  || ko "dnssec-failed.org devrait donner SERVFAIL"

# --- 4. la machine locale ---------------------------------------------------
if command -v resolvectl >/dev/null 2>&1; then
  resolvectl status 2>/dev/null | grep -q "$RES" \
    && ok "cette VM utilise $RES (resolvectl status)" \
    || ko "cette VM n'utilise pas $RES (Netplan nameservers)"
  resolvectl status 2>/dev/null | grep -qi 'lab.local' \
    && ok "lab.local est domaine de recherche" \
    || ko "lab.local absent des domaines (search: [lab.local])"
else
  grep -q "$RES" /etc/resolv.conf 2>/dev/null \
    && ok "resolv.conf pointe sur $RES" || ko "resolv.conf ne pointe pas sur $RES"
fi
n=$(grep -c 'lab\.local' /etc/hosts 2>/dev/null)
if [ "$n" -le 1 ]; then
  ok "/etc/hosts ne contient plus les entrées lab.local ($n ligne)"
else
  ko "/etc/hosts contient encore $n lignes lab.local : le DNS doit faire foi"
fi
G=$(getent hosts lab-db 2>/dev/null | awk '{print $1}')
[ "$G" = 10.10.10.12 ] && ok "getent hosts lab-db -> 10.10.10.12" \
  || ko "getent hosts lab-db donne '$G' (search domain ? cache ?)"

# --- 5. spécifique lab-ops -------------------------------------------------
if [ "$HOSTN" = lab-ops ]; then
  systemctl is-active -q unbound && ok "unbound actif" || ko "unbound inactif"
  systemctl is-active -q named && ok "named actif" || ko "named inactif"
  ip addr show dev ens18 | grep -q '10\.10\.10\.53/24' \
    && ok "10.10.10.53 posée sur ens18" || ko "10.10.10.53 absente"
  grep -qs '10\.10\.10\.53' /etc/netplan/*.yaml \
    && ok "10.10.10.53 persistante dans Netplan" \
    || ko "10.10.10.53 n'est pas dans Netplan (elle disparaîtra au reboot)"
  sudo -n named-checkconf -z >/dev/null 2>&1 \
    && ok "named-checkconf -z sans erreur" || ko "named-checkconf -z échoue"
  sudo -n unbound-checkconf >/dev/null 2>&1 \
    && ok "unbound-checkconf sans erreur" || ko "unbound-checkconf échoue"
fi
if [ "$HOSTN" = lab-adm ]; then
  systemctl is-active -q named && ok "named (secondaire) actif" \
    || ko "named inactif sur lab-adm"
  ls /var/cache/bind/ 2>/dev/null | grep -q 'lab.local' \
    && ok "copie de zone dans /var/cache/bind/" \
    || note "pas de fichier de zone transféré dans /var/cache/bind/"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
