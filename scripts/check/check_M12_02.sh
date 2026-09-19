#!/usr/bin/env bash
# check_M12_02.sh — vérifie le lab L12.2 (configuration persistante)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L12.2 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab12/rapports/reseau-3-formalismes.md"
IFACE=$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')
[ -n "$IFACE" ] || IFACE=ens18

# --- 1. état du noyau : c'est le résultat qui compte -------------------
if ip -4 a show dev "$IFACE" 2>/dev/null | grep -q '10\.10\.10\.'; then
  ok "adresse principale présente sur $IFACE"
else
  ko "aucune adresse 10.10.10.x sur $IFACE"
fi

if ip -4 a show dev "$IFACE" 2>/dev/null | grep -q '10\.10\.20\.'; then
  ok "adresse secondaire 10.10.20.x présente"
else
  ko "adresse secondaire 10.10.20.<dernier octet>/24 absente (ip -br a)"
fi

if ip -4 r 2>/dev/null | grep -q '^default via 10\.10\.10\.1'; then
  ok "route par défaut via 10.10.10.1"
else
  ko "route par défaut absente ou mauvaise passerelle (ip r)"
fi

NDEF=$(ip -4 r 2>/dev/null | grep -c '^default')
if [ "$NDEF" -le 1 ]; then
  ok "une seule route par défaut ($NDEF)"
else
  ko "$NDEF routes par défaut : deux gestionnaires se disputent l'interface"
fi

# --- 2. domaine de recherche ------------------------------------------
if command -v resolvectl >/dev/null 2>&1 &&
   resolvectl status 2>/dev/null | grep -qi 'lab\.local'; then
  ok "domaine de recherche lab.local déclaré"
elif grep -qE '^(search|domain).*lab\.local' /etc/resolv.conf 2>/dev/null
then
  ok "domaine de recherche lab.local déclaré (resolv.conf)"
else
  ko "search lab.local absent (resolvectl status / nameservers.search)"
fi

# --- 3. persistance : Netplan (Ubuntu) ou NetworkManager (Rocky) ------
if [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
  FIC=$(grep -lE '10\.10\.20\.' /etc/netplan/*.yaml 2>/dev/null | head -1)
  if [ -n "$FIC" ]; then
    ok "configuration persistante trouvée dans $FIC"
    M=$(stat -c '%a' "$FIC")
    [ "$M" = 600 ] \
      && ok "droits du fichier Netplan : 0600" \
      || ko "droits $M sur $FIC — netplan attend 0600 (chmod 600)"
    grep -qE '^[[:space:]]*renderer:[[:space:]]*networkd' "$FIC" \
      && ok "renderer networkd déclaré" \
      || note "renderer non déclaré dans $FIC (valeur par défaut utilisée)"
    grep -qE 'to:[[:space:]]*default' "$FIC" \
      && ok "route par défaut écrite en syntaxe routes: (pas gateway4)" \
      || ko "utilise routes: [{to: default, via: ...}] — gateway4 est retiré"
    if command -v netplan >/dev/null 2>&1; then
      netplan generate >/dev/null 2>&1 \
        && ok "netplan generate valide la syntaxe" \
        || ko "netplan generate échoue : la configuration ne s'appliquera pas"
    fi
  else
    ko "aucun fichier /etc/netplan/*.yaml ne contient l'adresse secondaire"
  fi
elif [ -d /etc/NetworkManager/system-connections ]; then
  if grep -rqE '10\.10\.20\.' /etc/NetworkManager/system-connections/ \
       2>/dev/null; then
    ok "configuration persistante trouvée dans un keyfile NetworkManager"
  else
    ko "aucun keyfile ne contient l'adresse secondaire (nmcli con mod)"
  fi
else
  ko "ni /etc/netplan ni keyfiles NetworkManager : rien de persistant"
fi

# --- 4. le rapport aux trois formalismes ------------------------------
if [ -s "$RAP" ]; then
  ok "rapport reseau-3-formalismes.md présent"
  n=0
  grep -qi 'netplan'   "$RAP" && n=$((n+1))
  grep -qi 'nmcli'     "$RAP" && n=$((n+1))
  grep -qi 'interfaces' "$RAP" && n=$((n+1))
  [ "$n" -eq 3 ] \
    && ok "les trois formalismes sont documentés" \
    || ko "seulement $n/3 formalismes dans le rapport"
else
  ko "rapport absent : $RAP (Netplan, nmcli, /etc/network/interfaces)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
