#!/usr/bin/env bash
# check_M18_02.sh — vérifie le lab L18.2 (fail2ban, jails et filtre maison)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L18.2 =="

LAB_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
SCAN="$LAB_HOME/lab18/logs/acces-scan.log"

command -v fail2ban-client >/dev/null 2>&1 || {
  ko "fail2ban n'est pas installé (apt install fail2ban)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. la configuration est dans jail.local, pas dans jail.conf -------
[ -f /etc/fail2ban/jail.local ] \
  && ok "/etc/fail2ban/jail.local existe" \
  || ko "pas de jail.local : ne modifie jamais jail.conf, il est écrasé \
aux mises à jour"

if [ -f /etc/fail2ban/jail.conf ] \
   && [ -f /etc/fail2ban/jail.conf.dpkg-dist ]; then
  note "jail.conf semble avoir été modifié (fichier .dpkg-dist présent)"
fi

CONF=$(cat /etc/fail2ban/jail.local /etc/fail2ban/jail.d/*.conf \
       2>/dev/null)
grep -qE '^\s*ignoreip.*10\.10\.10\.10' <<<"$CONF" \
  && ok "lab-adm (10.10.10.10) figure dans ignoreip" \
  || ko "10.10.10.10 absent de ignoreip : tu finiras par te bannir \
toi-même (voir BF18.4)"

for reglage in bantime findtime maxretry; do
  grep -qE "^\s*$reglage\s*=" <<<"$CONF" \
    && ok "$reglage défini explicitement" \
    || ko "$reglage non défini dans jail.local (ne compte pas sur les \
valeurs par défaut)"
done

# --- 2. le démon tourne et les deux jails sont actives -----------------
if fail2ban-client ping >/dev/null 2>&1; then
  ok "le démon fail2ban répond"
else
  ko "fail2ban ne répond pas (systemctl status fail2ban)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

JAILS=$(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/{print $2}')
for j in sshd nginx-scan; do
  grep -q "$j" <<<"$JAILS" \
    && ok "la jail $j est active" \
    || ko "la jail $j n'est pas active (enabled = true puis \
fail2ban-client reload)"
done

# --- 3. la jail sshd lit bien quelque chose ---------------------------
LP=$(fail2ban-client get sshd logpath 2>/dev/null)
BK=$(grep -A10 '^\[sshd\]' /etc/fail2ban/jail.local 2>/dev/null \
     | grep -E '^\s*backend' | head -1)
if grep -qi 'systemd' <<<"$BK" || grep -q '/var/log' <<<"$LP"; then
  ok "la jail sshd a une source de journal exploitable"
else
  ko "la jail sshd ne lit aucun journal : passe en backend = systemd \
si /var/log/auth.log n'existe pas"
fi

# --- 4. le filtre maison ----------------------------------------------
F=/etc/fail2ban/filter.d/nginx-scan.conf
if [ -f "$F" ]; then
  ok "le filtre $F existe"
  grep -q '<HOST>' "$F" \
    && ok "le filtre utilise <HOST> (sans quoi rien n'est bannissable)" \
    || ko "le filtre ne contient pas <HOST> : fail2ban ne saura pas quelle \
IP bannir"
  grep -qE '403\|404|404\|403' "$F" \
    && ok "le filtre discrimine sur le code de statut" \
    || note "le filtre ne regarde pas le code HTTP : risque de bannir des \
requêtes réussies"
else
  ko "filtre absent : crée $F"
fi

# --- 5. le filtre attrape réellement le journal fourni -----------------
if [ -f "$F" ] && [ -f "$SCAN" ]; then
  OUT=$(fail2ban-regex "$SCAN" "$F" 2>/dev/null)
  M=$(grep -oE '[0-9]+ matched' <<<"$OUT" | head -1 | cut -d' ' -f1)
  M=${M:-0}
  [ "$M" -ge 20 ] \
    && ok "fail2ban-regex trouve $M correspondances (>= 20 attendues)" \
    || ko "seulement $M correspondances sur $SCAN : élargis ta failregex \
et teste avec fail2ban-regex --print-all-missed"
  # faux positifs : les requêtes légitimes ne doivent pas correspondre
  if grep -q '10.10.10.10' <<<"$(fail2ban-regex "$SCAN" "$F" \
       --print-all-matched 2>/dev/null)"; then
    ko "ta failregex attrape aussi le trafic légitime de 10.10.10.10 \
(faux positifs)"
  else
    ok "aucun faux positif sur le trafic légitime du journal"
  fi
else
  note "test fail2ban-regex ignoré (filtre ou journal de scan absent)"
fi

# --- 6. la jail nginx-scan pointe sur le bon journal -------------------
if grep -q 'nginx-scan' <<<"$JAILS"; then
  LPN=$(fail2ban-client get nginx-scan logpath 2>/dev/null)
  grep -q 'access.log' <<<"$LPN" \
    && ok "nginx-scan suit le journal d'accès nginx" \
    || ko "nginx-scan ne suit pas /var/log/nginx/access.log (logpath)"
  MR=$(fail2ban-client get nginx-scan maxretry 2>/dev/null)
  [ "${MR:-0}" -ge 1 ] && [ "${MR:-99}" -le 10 ] \
    && ok "maxretry = $MR, valeur raisonnable" \
    || note "maxretry = $MR : vérifie que c'est bien ce que tu veux"
fi

# --- 7. le compte rendu sur les limites --------------------------------
LIM="$LAB_HOME/lab18/fail2ban-limites.md"
if [ -f "$LIM" ]; then
  n=$(grep -cE '^\s*[-*0-9]' "$LIM")
  [ "${n:-0}" -ge 3 ] \
    && ok "fail2ban-limites.md documente $n points" \
    || ko "fail2ban-limites.md attend trois limites décrites"
else
  ko "~/lab18/fail2ban-limites.md absent (étape 8 du lab)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
