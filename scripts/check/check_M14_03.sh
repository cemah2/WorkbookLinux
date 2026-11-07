#!/usr/bin/env bash
# check_M14_03.sh — vérifie le lab L14.3 (durcissement de sshd)
# À lancer SUR lab-web, avec sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L14.3 =="

[ "$(id -u)" -eq 0 ] || { \
  ko "à lancer avec sudo : sshd -T a besoin des droits root"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

SSHD=$(command -v sshd || echo /usr/sbin/sshd)
[ -x "$SSHD" ] || { ko "sshd introuvable"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 0. la configuration est-elle valide ? --------------------------------
if "$SSHD" -t 2>/tmp/m14.sshd-t; then
  ok "sshd -t : configuration valide"
else
  ko "sshd -t échoue : $(head -1 /tmp/m14.sshd-t)"
fi

EFF=$("$SSHD" -T 2>/dev/null)
[ -n "$EFF" ] || { ko "sshd -T ne renvoie rien : configuration illisible"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
val() { printf '%s\n' "$EFF" | awk -v k="$1" 'tolower($1)==k {sub($1" ","");
        print; exit}'; }

attendu() {   # attendu <directive> <valeur> <indice>
  local lu; lu=$(val "$1")
  if [ "$lu" = "$2" ]; then ok "$1 $lu"; else
    ko "$1 vaut '$lu' au lieu de '$2' ($3)"; fi
}

# --- 1. authentification ---------------------------------------------------
attendu permitrootlogin no "fragment 60-durcissement.conf"
attendu passwordauthentication no "attention au fragment 50-cloud-init.conf"
attendu kbdinteractiveauthentication no \
  "sans lui, PAM redemande un mot de passe par un autre chemin"
attendu pubkeyauthentication yes "c'est la seule méthode qui doit rester"
attendu permitemptypasswords no "valeur par défaut, à confirmer explicitement"

# --- 2. comptes autorisés --------------------------------------------------
GRP=$(val allowgroups)
case "$GRP" in
  *ssh-users*) ok "allowgroups $GRP" ;;
  "")  ko "allowgroups absent : l'accès n'est réservé à aucun groupe" ;;
  *)   ko "allowgroups vaut '$GRP' : ssh-users attendu" ;;
esac
if getent group ssh-users >/dev/null; then
  ok "le groupe ssh-users existe"
  MEMBRES=$(getent group ssh-users | cut -d: -f4)
  ID_M=$(id -nG mathieu 2>/dev/null | tr ' ' '\n' | grep -cx ssh-users)
  [ "$ID_M" -ge 1 ] \
    && ok "mathieu est membre de ssh-users" \
    || ko "mathieu n'est pas dans ssh-users (membres : ${MEMBRES:-aucun})"
else
  ko "le groupe ssh-users n'existe pas : plus personne ne peut se connecter"
fi

# --- 3. délais et tentatives -----------------------------------------------
attendu maxauthtries 3 "trois tentatives maximum"
attendu logingracetime 20 "20 secondes de délai de grâce"
CAI=$(val clientaliveinterval)
[ -n "$CAI" ] && [ "$CAI" -gt 0 ] 2>/dev/null && [ "$CAI" -le 600 ] \
  && ok "clientaliveinterval $CAI" \
  || ko "clientaliveinterval vaut '$CAI' : déconnexion sur inactivité"

# --- 4. surface d'attaque ---------------------------------------------------
attendu x11forwarding no "aucun besoin de X11 sur un serveur"
attendu allowagentforwarding no "le serveur ne doit pas détenir tes clés"

# --- 5. traçabilité ---------------------------------------------------------
LL=$(val loglevel)
[ "$LL" = VERBOSE ] \
  && ok "loglevel VERBOSE (l'empreinte de la clé utilisée est journalisée)" \
  || ko "loglevel vaut '$LL' : VERBOSE attendu pour tracer les clés"

if journalctl -u ssh -n 200 --no-pager 2>/dev/null \
   | grep -q 'Accepted publickey.*SHA256:'; then
  ok "le journal contient une connexion avec l'empreinte de la clé"
else
  note "aucune ligne 'Accepted publickey ... SHA256:' récente : reconnecte-toi"
fi

# --- 6. algorithmes ---------------------------------------------------------
CIPHERS=$(val ciphers)
case "$CIPHERS" in
  *cbc*) ko "des chiffrements CBC sont encore acceptés : $CIPHERS" ;;
  "")    ko "ciphers non restreint (jeu par défaut)" ;;
  *)     ok "ciphers restreint : $CIPHERS" ;;
esac
MACS=$(val macs)
case "$MACS" in
  *hmac-sha1*|*-96*) ko "des MAC faibles sont encore acceptés : $MACS" ;;
  "")  ko "macs non restreint (jeu par défaut)" ;;
  *)   case "$MACS" in
         *-etm@openssh.com*) ok "macs restreint aux variantes EtM" ;;
         *) ko "macs restreint mais sans variante -etm : $MACS" ;;
       esac ;;
esac
KEX=$(val kexalgorithms)
case "$KEX" in
  *sha1*|*group1-*) ko "échange de clés faible encore accepté : $KEX" ;;
  "")  ko "kexalgorithms non restreint (jeu par défaut)" ;;
  *)   ok "kexalgorithms restreint : $KEX" ;;
esac

# --- 7. les fragments -------------------------------------------------------
if [ -d /etc/ssh/sshd_config.d ]; then
  LISTE=$(ls -1 /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tr '\n' ' ')
  note "fragments lus dans cet ordre : ${LISTE:-aucun}"
  if ls /etc/ssh/sshd_config.d/*.conf >/dev/null 2>&1 && \
     grep -rlq 'PasswordAuthentication[[:space:]]*yes' \
       /etc/ssh/sshd_config.d/ 2>/dev/null; then
    ko "un fragment contient encore PasswordAuthentication yes"
  else
    ok "aucun fragment ne réactive le mot de passe"
  fi
fi

# --- 8. les rapports --------------------------------------------------------
LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
for f in sshd-avant.txt ssh-audit-avant.txt; do
  [ -s "$HOMEDIR/lab14/rapports/$f" ] \
    && ok "trace présente : ~/lab14/rapports/$f" \
    || ko "trace manquante : ~/lab14/rapports/$f (photographie de l'existant)"
done

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
