#!/usr/bin/env bash
# check_M13_05.sh — vérifie le lab L13.5 (bonding active-backup)
# À lancer sur lab-db.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L13.5 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab13/rapports/bonding.md"
B=/proc/net/bonding/bond0

if [ -r "$B" ]; then
  ok "bond0 existe"
  grep -q 'active-backup' "$B" && ok "mode active-backup" \
    || ko "le mode n'est pas active-backup ($(grep 'Bonding Mode' "$B"))"
  n=$(grep -c '^Slave Interface' "$B")
  [ "$n" -eq 2 ] && ok "deux esclaves" || ko "$n esclave(s) au lieu de 2"
  grep -q 'Primary Slave: ens19' "$B" && ok "ens19 est l'esclave primaire" \
    || ko "pas de primary ens19 (paramètre primary)"
  grep -q 'MII Polling Interval (ms): 100' "$B" && ok "miimon 100 ms" \
    || ko "miimon n'est pas à 100 ms"
  grep -q 'Currently Active Slave: ens' "$B" && ok "un esclave est actif" \
    || ko "aucun esclave actif : les NIC sont-elles up ?"
  f=$(awk '/Link Failure Count/ {s+=$4} END {print s+0}' "$B")
  [ "$f" -ge 1 ] && ok "au moins une bascule a eu lieu (Link Failure Count=$f)" \
    || note "Link Failure Count = 0 : la bascule n'a pas encore été jouée"
else
  ko "bond0 absent (/proc/net/bonding/bond0)"
fi
ip addr show dev bond0 2>/dev/null | grep -q '172\.31\.0\.12/24' \
  && ok "bond0 = 172.31.0.12/24" || ko "bond0 sans 172.31.0.12/24"
ping -c1 -W2 172.31.0.11 >/dev/null 2>&1 \
  && ok "lab-web (172.31.0.11) répond à travers le bond" \
  || ko "172.31.0.11 ne répond pas (ens19 de lab-web configurée ?)"

grep -qs 'bonds:' /etc/netplan/*.yaml \
  && ok "configuration persistante (Netplan bonds:)" \
  || ko "pas de bloc bonds: dans Netplan"
grep -qs 'mii-monitor-interval' /etc/netplan/*.yaml \
  && ok "mii-monitor-interval déclaré" || ko "mii-monitor-interval manquant"

if [ -s "$RAP" ] && [ "$(grep -cv '^[[:space:]]*$' "$RAP")" -ge 10 ]; then
  ok "rapport bonding.md rédigé"
  grep -q 'Link Failure Count' "$RAP" \
    && ok "extrait de /proc/net/bonding/bond0 dans le rapport" \
    || ko "le rapport ne contient pas d'extrait de /proc/net/bonding/bond0"
  grep -qiE 'perdu|lost|loss' "$RAP" \
    && ok "les pertes pendant la bascule sont chiffrées" \
    || ko "le rapport ne chiffre pas les paquets perdus"
  grep -qiE '802\.3ad|lacp' "$RAP" \
    && ok "la variante LACP est décrite" || ko "pas de variante 802.3ad/LACP"
else
  ko "rapport absent ou trop court : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
