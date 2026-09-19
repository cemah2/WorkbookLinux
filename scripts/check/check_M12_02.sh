#!/usr/bin/env bash
# check_M12_02.sh — vérifie le lab L12.2 (~/.ssh/config de référence)
# À lancer sur lab-adm, SANS sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L12.2 =="

CONF="$HOME/.ssh/config"
# valeur effective d'une directive pour un alias : ssh -G est l'arbitre
eff() { ssh -G "$1" 2>/dev/null | awk -v k="$2" '$1==k {print $2; exit}'; }

command -v ssh >/dev/null 2>&1 || { \
  ko "ssh introuvable"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. le fichier et ses droits ------------------------------------------
if [ -f "$CONF" ]; then
  ok "~/.ssh/config présent"
  M=$(stat -c %a "$CONF")
  [ "$M" = 600 ] || [ "$M" = 644 ] \
    && ok "permissions du fichier de configuration : $M" \
    || ko "~/.ssh/config en $M : ssh refusera de le lire (600 attendu)"
else
  ko "~/.ssh/config absent"
fi
grep -qE '^[[:space:]]*Include[[:space:]]' "$CONF" 2>/dev/null \
  && ok "une directive Include est présente (étape 5)" \
  || ko "aucune directive Include : sors les machines dans ~/.ssh/config.d/"

# --- 2. le bastion --------------------------------------------------------
[ "$(eff bastion hostname)" = 10.10.10.10 ] \
  && ok "alias bastion -> 10.10.10.10" \
  || ko "ssh -G bastion : hostname vaut '$(eff bastion hostname)'"
[ "$(eff bastion user)" = mathieu ] \
  && ok "bastion : user mathieu" \
  || ko "ssh -G bastion : user vaut '$(eff bastion user)'"

# --- 3. les quatre serveurs -----------------------------------------------
verif_hote() {
  local alias=$1 ip=$2
  [ "$(eff "$alias" hostname)" = "$ip" ] \
    && ok "$alias -> $ip" \
    || ko "ssh -G $alias : hostname vaut '$(eff "$alias" hostname)' (≠ $ip)"
  [ "$(eff "$alias" user)" = mathieu ] \
    && ok "$alias : user mathieu" \
    || ko "$alias : user vaut '$(eff "$alias" user)'"
  PJ=$(ssh -G "$alias" 2>/dev/null | awk '$1=="proxyjump"{print $2; exit}')
  case "$PJ" in
    ""|none) ko "$alias : aucun ProxyJump (le rebond par le bastion manque)" ;;
    *)       ok "$alias : proxyjump $PJ" ;;
  esac
  [ "$(eff "$alias" identitiesonly)" = yes ] \
    && ok "$alias : identitiesonly yes" \
    || ko "$alias : identitiesonly vaut '$(eff "$alias" identitiesonly)'"
  case "$(ssh -G "$alias" 2>/dev/null | awk '$1=="identityfile"{print $2}' \
          | tr '\n' ' ')" in
    *id_ed25519*) ok "$alias : la clé ed25519 est désignée explicitement" ;;
    *) ko "$alias : IdentityFile ne désigne pas ~/.ssh/id_ed25519" ;;
  esac
}
verif_hote lab-web  10.10.10.11
verif_hote lab-db   10.10.10.12
verif_hote lab-rhel 10.10.10.13
verif_hote lab-ops  10.10.10.14

# --- 4. réglages globaux --------------------------------------------------
[ "$(eff lab-db controlmaster)" = auto ] \
  && ok "controlmaster auto" \
  || ko "controlmaster vaut '$(eff lab-db controlmaster)' (auto attendu)"
CP=$(eff lab-db controlpath)
case "$CP" in
  ""|none) ko "controlpath non défini : pas de multiplexage possible" ;;
  *)       ok "controlpath $CP" ;;
esac
PERSIST=$(eff lab-db controlpersist)
case "$PERSIST" in
  ""|no|0) ko "controlpersist inactif : le maître ne survit pas aux sessions" ;;
  *)       ok "controlpersist $PERSIST" ;;
esac
SAI=$(eff lab-db serveraliveinterval)
[ -n "$SAI" ] && [ "$SAI" -gt 0 ] 2>/dev/null \
  && ok "serveraliveinterval $SAI" \
  || ko "serveraliveinterval non positionné (sessions coupées par le NAT)"

# --- 5. le répertoire des sockets de contrôle -----------------------------
CMDIR=$(dirname "${CP:-$HOME/.ssh/cm/x}")
if [ -d "$CMDIR" ]; then
  ok "répertoire des sockets présent : $CMDIR"
  [ "$(stat -c %a "$CMDIR")" = 700 ] \
    && ok "$CMDIR en 700" \
    || ko "$CMDIR en $(stat -c %a "$CMDIR") : 700 attendu"
else
  ko "$CMDIR absent : OpenSSH ne le crée pas, le multiplexage sera inactif"
fi

# --- 6. le multiplexage fonctionne réellement -----------------------------
if ssh -o BatchMode=yes -o ConnectTimeout=5 lab-web true 2>/dev/null; then
  ok "ssh lab-web fonctionne en une frappe (rebond compris)"
  if ssh -O check lab-web >/dev/null 2>&1; then
    ok "une session maître est active (ssh -O check)"
  else
    ko "aucune session maître : vérifie ControlMaster/ControlPath"
  fi
else
  ko "ssh lab-web échoue : reprends L12.1 avant ce lab"
fi

# --- 7. rapport -----------------------------------------------------------
R="$HOME/lab12/rapports/config-ordre.md"
if [ -s "$R" ]; then
  ok "rapport présent : ~/lab12/rapports/config-ordre.md"
  grep -qiE 'premi(è|e)re valeur|first obtained|premier' "$R" \
    && ok "le rapport énonce la règle de précédence" \
    || ko "le rapport doit énoncer la règle : la première valeur gagne"
else
  ko "rapport manquant : ~/lab12/rapports/config-ordre.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
