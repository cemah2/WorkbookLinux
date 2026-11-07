#!/usr/bin/env bash
# check_M28_02.sh — vérifie le lab L28.2 (client inscrit dans lab.local)
# À lancer avec sudo sur lab-web, lab-db et lab-adm.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L28.2 sur $(hostname) =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
FQDN="$(hostname -s).lab.local"

# --- 1. inscription -------------------------------------------------------
if [ -f /etc/ipa/default.conf ]; then
  ok "machine inscrite (/etc/ipa/default.conf)"
else
  ko "machine non inscrite : ipa-client-install (étape 1 ou 4)"; fin
fi
[ "$(hostname)" = "$FQDN" ] \
  && ok "nom pleinement qualifié : $FQDN" \
  || ko "nom actuel : $(hostname) ; attendu $FQDN"
klist -k /etc/krb5.keytab 2>/dev/null | grep -q "host/$FQDN@LAB.LOCAL" \
  && ok "keytab de l'hôte : host/$FQDN@LAB.LOCAL" \
  || ko "/etc/krb5.keytab ne contient pas host/$FQDN@LAB.LOCAL"

# --- 2. SSSD --------------------------------------------------------------
C=/etc/sssd/sssd.conf
if [ -f "$C" ]; then
  [ "$(stat -c '%U:%G %a' "$C")" = "root:root 600" ] \
    && ok "sssd.conf : root:root 0600" \
    || ko "sssd.conf : $(stat -c '%U:%G %a' "$C") ; sssd exige root:root 0600"
else
  ko "/etc/sssd/sssd.conf absent"
fi
systemctl is-active -q sssd \
  && ok "sssd actif" \
  || ko "sssd n'est pas actif : journalctl -u sssd -b"
if command -v sssctl >/dev/null 2>&1; then
  sssctl domain-status lab.local 2>/dev/null | grep -q 'Online status: Online' \
    && ok "SSSD en ligne avec le domaine lab.local" \
    || ko "SSSD hors ligne : sssctl domain-status lab.local (heure ? réseau ?)"
else
  ko "sssctl absent : apt install sssd-tools"
fi

# --- 3. NSS et PAM ----------------------------------------------------------
for base in passwd group sudoers; do
  grep -Eq "^$base:.*\bsss\b" /etc/nsswitch.conf \
    && ok "nsswitch.conf : $base interroge sss" \
    || ko "nsswitch.conf : sss absent de la ligne $base"
done
if uid=$(id -u alice 2>/dev/null); then
  [ "$uid" -ge 100000 ] \
    && ok "id alice : UID $uid attribué par FreeIPA" \
    || ko "alice a l'UID $uid : un compte local masque celui de l'annuaire"
else
  ko "id alice échoue"
fi
mu=$(id -u mathieu 2>/dev/null || echo 0)
[ "$mu" -gt 0 ] && [ "$mu" -lt 60000 ] \
  && ok "mathieu reste un compte local (UID $mu)" \
  || ko "le compte local mathieu a disparu ou change d'UID"
grep -q pam_mkhomedir /etc/pam.d/common-session 2>/dev/null \
  && ok "pam_mkhomedir actif (répertoire créé à la première connexion)" \
  || ko "pam_mkhomedir absent : pam-auth-update --enable mkhomedir"
[ -d /home/alice ] \
  && ok "/home/alice existe (alice s'est déjà connectée ici)" \
  || note "/home/alice absent : connecte alice une fois depuis lab-adm"

# --- 4. sshd et heure -------------------------------------------------------
T=$(sshd -T 2>/dev/null)
grep -qi '^gssapiauthentication yes' <<<"$T" \
  && ok "sshd accepte GSSAPI" \
  || ko "sshd : GSSAPIAuthentication n'est pas à yes"
grep -qi '^authorizedkeyscommand .*sss_ssh_authorizedkeys' <<<"$T" \
  && ok "sshd lit les clés de l'annuaire (sss_ssh_authorizedkeys)" \
  || ko "sshd : AuthorizedKeysCommand sss_ssh_authorizedkeys absent"
[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] \
  && ok "horloge synchronisée" \
  || ko "horloge non synchronisée : Kerberos refusera au-delà de 5 min d'écart"

# --- 5. inscription reproductible (lab-db, lab-adm) ------------------------
LAB_HOME=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)
case "$(hostname -s)" in
  lab-db|lab-adm)
    if [ -f "$LAB_HOME/lab28/inscription.sh" ]; then
      ok "lab28/inscription.sh présent"
      grep -Eq -- '--password[= ]+["'"'"']?[A-Za-z0-9]{6,}' "$LAB_HOME/lab28/inscription.sh" \
        && ko "inscription.sh contient un mot de passe en clair" \
        || ok "inscription.sh ne contient pas de mot de passe en clair"
    else
      ko "lab28/inscription.sh absent (étape 4)"
    fi ;;
esac

fin
