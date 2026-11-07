#!/usr/bin/env bash
# check_M12_03.sh — vérifie le lab L12.3 (résolution de noms)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L12.3 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab12/rapports/zone-lab-local.md"

command -v dig >/dev/null 2>&1 || {
  ko "dig absent : installe dnsutils (ou bind-utils) avant ce lab"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. NSS et DNS doivent converger -----------------------------------
NSS=$(getent hosts www.lab.local 2>/dev/null | awk '{print $1; exit}')
# serveur interrogé explicitement : sans @, le stub 127.0.0.53 servirait
# aussi /etc/hosts et masquerait la divergence
DNS=$(dig +short +time=2 +tries=1 @10.10.10.10 www.lab.local 2>/dev/null |
      grep -E '^[0-9.]+$' | tail -1)

if [ -z "$DNS" ]; then
  ko "le DNS ne répond pas pour www.lab.local (dnsmasq sur lab-adm ?)"
elif [ -z "$NSS" ]; then
  ko "getent hosts www.lab.local ne répond rien : chaîne NSS cassée"
elif [ "$NSS" = "$DNS" ]; then
  ok "getent et dig convergent sur $DNS"
else
  ko "divergence getent=$NSS dig=$DNS — cherche dans /etc/hosts"
fi

# --- 2. /etc/hosts nettoyé ---------------------------------------------
if grep -qE '^[^#]*[[:space:]]www\.lab\.local' /etc/hosts 2>/dev/null; then
  ko "/etc/hosts contient encore une entrée pour www.lab.local"
else
  ok "/etc/hosts ne court-circuite plus www.lab.local"
fi

# --- 3. domaine de recherche : les noms courts doivent résoudre --------
if getent hosts lab-db >/dev/null 2>&1; then
  ok "le nom court lab-db résout (search lab.local actif)"
else
  ko "lab-db ne résout pas sans suffixe : configure search lab.local"
fi

# --- 4. le résolveur pointe bien vers le DNS du lab --------------------
if command -v resolvectl >/dev/null 2>&1; then
  if resolvectl status 2>/dev/null | grep -q '10\.10\.10\.10'; then
    ok "10.10.10.10 déclaré comme serveur DNS"
  else
    ko "le DNS du lab (10.10.10.10) n'apparaît pas dans resolvectl status"
  fi
  if [ -L /etc/resolv.conf ]; then
    ok "/etc/resolv.conf est bien un lien géré par systemd-resolved"
  else
    note "/etc/resolv.conf est un fichier réel : configuration figée"
  fi
fi

# --- 5. le rapport de zone : six types d'enregistrements ---------------
if [ -s "$RAP" ]; then
  ok "rapport zone-lab-local.md présent"
  manque=""
  for t in CNAME MX TXT SRV PTR; do
    grep -qi "$t" "$RAP" || manque="$manque $t"
  done
  grep -qE '10\.10\.10\.1[0-4]' "$RAP" || manque="$manque A"
  [ -z "$manque" ] \
    && ok "les six types d'enregistrements sont documentés" \
    || ko "types manquants dans le rapport :$manque"
else
  ko "rapport absent : $RAP (A, CNAME, MX, TXT, SRV, PTR)"
fi

# --- 6. la zone répond réellement pour chaque type ---------------------
n=0
[ -n "$(dig +short CNAME www.lab.local 2>/dev/null)" ] && n=$((n+1))
[ -n "$(dig +short MX lab.local 2>/dev/null)" ]        && n=$((n+1))
[ -n "$(dig +short TXT lab.local 2>/dev/null)" ]       && n=$((n+1))
[ -n "$(dig +short SRV _http._tcp.lab.local 2>/dev/null)" ] && n=$((n+1))
if [ "$n" -ge 3 ]; then
  ok "la zone lab.local sert $n/4 types spéciaux interrogés"
else
  note "seulement $n/4 types spéciaux répondent (dnsmasq sur lab-adm)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
