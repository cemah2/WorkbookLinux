#!/usr/bin/env bash
# check_M28_03.sh — vérifie le lab L28.3 (sudo et HBAC centralisés)
# À lancer avec sudo sur lab-web.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L28.3 =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
[ "$(hostname -s)" = lab-web ] || { ko "ce contrôle se lance sur lab-web"; fin; }
[ -f /etc/ipa/default.conf ] || { ko "lab-web n'est pas inscrit (L28.2)"; fin; }

# les règles du jour, pas celles d'hier
sss_cache -E 2>/dev/null || true

# --- 1. allow_all désactivée (lue avec l'identité de l'hôte) --------------
CC=$(mktemp); trap 'rm -f "$CC"' EXIT
export KRB5CCNAME="FILE:$CC"
if kinit -k -t /etc/krb5.keytab "host/lab-web.lab.local" 2>/dev/null; then
  F=$(ldapsearch -LLL -Q -Y GSSAPI -H ldap://lab-rhel.lab.local \
        -b cn=hbac,dc=lab,dc=local '(cn=allow_all)' ipaEnabledFlag 2>/dev/null |
      awk '/^ipaEnabledFlag:/{print $2}')
  case "$F" in
    FALSE) ok "la règle HBAC allow_all est désactivée" ;;
    TRUE)  ko "allow_all est encore active : ipa hbacrule-disable allow_all" \
"(après hbactest !)" ;;
    *)     note "état d'allow_all illisible (ldapsearch, libsasl2-modules-gssapi-mit)" ;;
  esac
  kdestroy -q 2>/dev/null || true
else
  note "kinit avec le keytab de l'hôte impossible : contrôle d'allow_all sauté"
fi

# --- 2. HBAC vu par PAM (phase account) -------------------------------------
acct() { sssctl user-checks "$1" -s "$2" -a acct 2>/dev/null | grep -q 'pam_acct_mgmt: Success'; }
acct alice sshd && ok "HBAC : alice (admins-lab) entre sur lab-web" \
                || ko "HBAC : alice refusée en sshd sur lab-web"
acct bruno sshd && ok "HBAC : bruno (devs) entre sur lab-web" \
                || ko "HBAC : bruno refusé en sshd sur lab-web"
acct chloe sshd && ok "HBAC : chloe (auditeurs) entre sur lab-web" \
                || ko "HBAC : chloe refusée en sshd sur lab-web"
acct bruno sudo && ok "HBAC : bruno peut passer par sudo" \
                || ko "HBAC : sudo refusé à bruno ; une règle HBAC doit inclure" \
"le service sudo (groupe de services Sudo)"
if acct chloe sudo; then
  ko "HBAC : chloe (auditeurs) a le service sudo ; elle ne devrait pas"
else
  ok "HBAC : le service sudo est fermé à chloe"
fi

# --- 3. règles sudo ---------------------------------------------------------
L=$(sudo -l -U bruno 2>/dev/null)
grep -q 'systemctl restart nginx' <<<"$L" \
  && ok "sudo : bruno peut redémarrer nginx" \
  || ko "sudo : pas de « systemctl restart nginx » pour bruno"
if grep -q 'journalctl' <<<"$L"; then
  grep -q 'journalctl --no-pager' <<<"$L" \
    && ok "sudo : journalctl autorisé avec --no-pager (pas de pager root)" \
    || ko "sudo : journalctl sans --no-pager ouvre less en root : « !sh » donne un shell"
else
  ko "sudo : pas de journalctl pour bruno"
fi
grep -Eq '\(ALL( : ALL)?\) ALL' <<<"$L" \
  && ko "sudo : bruno a (ALL) ALL ; la règle devs doit se limiter à nginx" \
  || ok "sudo : bruno n'a pas les pleins pouvoirs"
sudo -l -U alice 2>/dev/null | grep -Eq '\(ALL( : ALL)?\) ALL' \
  && ok "sudo : alice (admins-lab) a tous les droits sur lab-web" \
  || ko "sudo : alice n'a pas (ALL) ALL sur lab-web"
sudo -l -U chloe 2>&1 | grep -q 'not allowed\|n.est pas autorisé' \
  && ok "sudo : chloe n'a aucune règle" \
  || ko "sudo : chloe a des droits sudo sur lab-web"

# --- 4. rien en local -------------------------------------------------------
if grep -rEqs 'admins-lab|devs|auditeurs|alice|bruno|chloe|david' /etc/sudoers /etc/sudoers.d/; then
  ko "une règle locale cite un groupe ou un compte du domaine : tout doit" \
"venir de FreeIPA"
else
  ok "aucune règle sudo locale pour le domaine (/etc/sudoers.d/ propre)"
fi

fin
