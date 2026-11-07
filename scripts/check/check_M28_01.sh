#!/usr/bin/env bash
# check_M28_01.sh — vérifie le lab L28.1 (serveur FreeIPA)
# À lancer avec sudo sur lab-rhel (Rocky 9).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L28.1 =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
command -v ipactl >/dev/null 2>&1 || {
  ko "ipactl absent : ce lab se fait sur lab-rhel (dnf install ipa-server)"; fin; }

# --- 1. nom et installation -------------------------------------------
[ "$(hostname)" = lab-rhel.lab.local ] \
  && ok "nom pleinement qualifié : lab-rhel.lab.local" \
  || ko "nom actuel : $(hostname) ; attendu lab-rhel.lab.local"

if [ -f /etc/ipa/default.conf ] && grep -q '^realm *= *LAB.LOCAL' /etc/ipa/default.conf; then
  ok "serveur installé, royaume LAB.LOCAL"
else
  ko "pas de royaume LAB.LOCAL dans /etc/ipa/default.conf (ipa-server-install)"
  fin
fi

# --- 2. tous les services tournent ------------------------------------
ETAT=$(ipactl status 2>&1)
if grep -q 'STOPPED' <<<"$ETAT"; then
  ko "services arrêtés : $(grep STOPPED <<<"$ETAT" | cut -d: -f1 | paste -sd, -)"
else
  ok "ipactl status : tous les services RUNNING"
fi

# --- 3. ports à l'écoute ------------------------------------------------
for p in 88 389 443 464 636; do
  ss -Htln "( sport = :$p )" | grep -q . \
    && ok "port $p/tcp à l'écoute" \
    || ko "port $p/tcp fermé"
done

# --- 4. pare-feu --------------------------------------------------------
if systemctl is-active -q firewalld; then
  trouve=0
  for z in $(firewall-cmd --get-active-zones | grep -v '^ '); do
    firewall-cmd --zone="$z" --query-service=freeipa-4 >/dev/null 2>&1 && trouve=1
  done
  [ "$trouve" -eq 1 ] \
    && ok "firewalld laisse passer freeipa-4 (zone active)" \
    || ko "freeipa-4 absent des zones actives : firewall-cmd --permanent" \
"--zone=public --add-service=freeipa-4 && firewall-cmd --reload"
  firewall-cmd --permanent --zone=public --query-service=freeipa-4 >/dev/null 2>&1 \
    && ok "règle permanente (survit à un reload)" \
    || ko "freeipa-4 n'est pas dans la configuration permanente de la zone public"
else
  ko "firewalld est arrêté : on n'installe pas un annuaire sans pare-feu"
fi

# --- 5. comptes et groupes (vus par SSSD, le serveur est son propre client)
declare -A GROUPES=([alice]="admins-lab" [bruno]="devs" [chloe]="auditeurs"
                    [david]="devs auditeurs")
for u in alice bruno chloe david; do
  if uid=$(id -u "$u" 2>/dev/null); then
    [ "$uid" -ge 100000 ] \
      && ok "$u existe (UID $uid, plage FreeIPA)" \
      || ko "$u a l'UID $uid : compte local ? il doit venir de l'annuaire"
    for g in ${GROUPES[$u]}; do
      id -nG "$u" | tr ' ' '\n' | grep -qx "$g" \
        && ok "$u est membre de $g" \
        || ko "$u n'est pas membre de $g (ipa group-add-member $g --users=$u)"
    done
  else
    ko "$u inconnu (étape 5 : import de ~/lab28/utilisateurs.csv)"
  fi
done

# --- 6. secrets -----------------------------------------------------------
LAB_HOME=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)
S="$LAB_HOME/lab28/secrets.md"
if [ -f "$S" ]; then
  [ "$(stat -c %a "$S")" = 600 ] \
    && ok "lab28/secrets.md en 0600" \
    || ko "lab28/secrets.md en $(stat -c %a "$S") : chmod 600"
else
  note "lab28/secrets.md absent : relance setup_M28.sh"
fi

fin
