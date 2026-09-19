#!/usr/bin/env bash
# check_M11_01.sh — vérifie le lab L11.1 (plan d'adressage, tests à chaud)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab11/rapports/plan-adressage.md"

# --- 1. le rapport existe et a été rempli ------------------------------
if [ -s "$RAP" ] && [ "$(grep -cv '^[[:space:]]*$' "$RAP")" -ge 15 ]; then
  ok "rapport plan-adressage.md rédigé"
else
  ko "rapport absent ou trop court : $RAP (15 lignes utiles minimum)"
fi

# --- 2. les quatre sous-réseaux, avec les bonnes frontières ------------
manque=""
for v in '10\.10\.10\.0/26' '10\.10\.10\.64/26' \
         '10\.10\.10\.128/26' '10\.10\.10\.192/26'; do
  grep -qE "$v" "$RAP" 2>/dev/null || manque="$manque ${v//\\/}"
done
[ -z "$manque" ] \
  && ok "les quatre préfixes /26 sont présents" \
  || ko "préfixes manquants :$manque — un /24 en 4 parts donne des /26"

# --- 3. adresses de diffusion : la valeur qui prouve le calcul ---------
manque=""
for v in '10\.10\.10\.63' '10\.10\.10\.127' '10\.10\.10\.191'; do
  grep -qE "$v" "$RAP" 2>/dev/null || manque="$manque ${v//\\/}"
done
[ -z "$manque" ] \
  && ok "les adresses de diffusion intermédiaires figurent au rapport" \
  || ko "diffusions manquantes :$manque (pas de 64 dans le dernier octet)"

grep -qE '255\.255\.255\.192' "$RAP" 2>/dev/null \
  && ok "le masque décimal est donné" \
  || ko "le masque décimal du /26 manque (255.255.255.192)"

# --- 4. la proposition de DMZ (62 hôtes = /26, hors 10.10.10.0/24) -----
DMZ=$(grep -oE '10\.10\.[0-9]{1,3}\.[0-9]{1,3}/26' "$RAP" 2>/dev/null |
      grep -v '^10\.10\.10\.' | head -1)
if [ -n "$DMZ" ]; then
  ok "proposition de DMZ hors 10.10.10.0/24 : $DMZ"
else
  ko "aucune DMZ en /26 hors de 10.10.10.0/24 (62 hôtes -> /26)"
fi

# --- 5. les trois ip route get ----------------------------------------
n=0
for m in '10\.10\.30\.5' '10\.10\.20\.99' '9\.9\.9\.9'; do
  grep -qE "$m" "$RAP" 2>/dev/null && n=$((n+1))
done
[ "$n" -eq 3 ] \
  && ok "les trois destinations testées sont documentées" \
  || ko "il manque des sorties de ip route get ($n/3 destinations citées)"

# --- 6. nettoyage effectif du système ----------------------------------
if ip -4 a 2>/dev/null | grep -q '10\.10\.20\.10/24'; then
  ko "l'adresse de test 10.10.20.10/24 est encore posée (ip a del)"
else
  ok "aucune adresse de test résiduelle"
fi

if ip -4 r 2>/dev/null | grep -q '10\.10\.30\.0/24'; then
  ko "la route de test vers 10.10.30.0/24 est encore là (ip r del)"
else
  ok "aucune route de test résiduelle"
fi

ip -4 r 2>/dev/null | grep -q '^default' \
  && ok "la route par défaut est intacte" \
  || note "aucune route par défaut : le nettoyage a été trop large ?"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
