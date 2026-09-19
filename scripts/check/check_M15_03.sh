#!/usr/bin/env bash
# check_M15_03.sh — vérifie le lab L15.3 (SELinux, application sur 8088)
# À lancer sur lab-rhel (Rocky 9).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L15.3 =="

LAB_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)

command -v getenforce >/dev/null 2>&1 || {
  ko "SELinux n'est pas présent : ce lab se fait sur lab-rhel (Rocky 9)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. le mode, maintenant ET au prochain démarrage -------------------
[ "$(getenforce)" = Enforcing ] \
  && ok "SELinux est en Enforcing" \
  || ko "SELinux est en $(getenforce) : tout l'intérêt du lab est de \
faire fonctionner l'application SANS baisser le mode"

CONF=$(awk -F= '/^SELINUX=/{print $2}' /etc/selinux/config 2>/dev/null)
[ "$CONF" = enforcing ] \
  && ok "/etc/selinux/config prévoit enforcing au démarrage" \
  || ko "/etc/selinux/config contient SELINUX=$CONF : au prochain reboot \
la protection tombe"

# --- 2. le port 8088 est déclaré comme port HTTP -----------------------
if command -v semanage >/dev/null 2>&1; then
  semanage port -l 2>/dev/null | grep -E '^http_port_t' | grep -q '8088' \
    && ok "8088/tcp est étiqueté http_port_t" \
    || ko "8088 n'est pas déclaré : semanage port -a -t http_port_t \
-p tcp 8088"
else
  ko "semanage absent (dnf install policycoreutils-python-utils)"
fi

# --- 3. le contexte du contenu ----------------------------------------
if [ -d /srv/api/public ]; then
  ok "/srv/api/public existe"
  CTX=$(ls -Zd /srv/api/public 2>/dev/null | awk '{print $1}')
  grep -q 'httpd_sys_content_t' <<<"$CTX" \
    && ok "le contexte est httpd_sys_content_t" \
    || ko "contexte actuel : $CTX — il faut httpd_sys_content_t"

  # déclaré dans la politique, pas seulement posé à la main (chcon)
  if semanage fcontext -l 2>/dev/null | grep -q '/srv/api'; then
    ok "le contexte est déclaré dans la politique (semanage fcontext)"
  else
    ko "aucune règle fcontext pour /srv/api : un chcon seul ne survit pas \
à un restorecon ni à une restauration de sauvegarde"
  fi

  # et il résiste à un restorecon
  if command -v restorecon >/dev/null 2>&1; then
    if restorecon -nv /srv/api/public 2>/dev/null | grep -q 'Would relabel'
    then
      ko "restorecon voudrait réétiqueter /srv/api/public : la politique \
et la réalité divergent"
    else
      ok "le contexte survit à un restorecon (politique cohérente)"
    fi
  fi
else
  ko "/srv/api/public absent (étape 2 du lab)"
fi

# --- 4. le booléen de connexion sortante ------------------------------
B=$(getsebool httpd_can_network_connect 2>/dev/null | awk '{print $3}')
[ "$B" = on ] \
  && ok "httpd_can_network_connect est activé" \
  || ko "httpd_can_network_connect est $B : le proxy_pass ne sortira pas"

if command -v semanage >/dev/null 2>&1; then
  semanage boolean -l 2>/dev/null \
    | grep '^httpd_can_network_connect' | grep -q '(on   ,   on)' \
    && ok "le booléen est persistant (setsebool -P)" \
    || ko "le booléen n'est pas persistant : sans -P il retombe au reboot"
fi

# --- 5. le service répond ---------------------------------------------
systemctl is-active nginx >/dev/null 2>&1 \
  && ok "nginx est actif" \
  || ko "nginx n'est pas actif (journalctl -u nginx)"

ss -tlnH 2>/dev/null | grep -q ':8088' \
  && ok "quelque chose écoute sur 8088" \
  || ko "rien n'écoute sur 8088"

C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    http://127.0.0.1:8088/ 2>/dev/null)
[ "$C" = 200 ] \
  && ok "http://127.0.0.1:8088/ répond 200" \
  || ko "http://127.0.0.1:8088/ répond $C (403 = contexte, 000 = pas \
d'écoute)"

CA=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
     http://127.0.0.1:8088/api/ 2>/dev/null)
case "$CA" in
  200|301|302) ok "le proxy_pass /api/ atteint lab-web ($CA)" ;;
  502|504) ko "/api/ répond $CA : connexion sortante refusée \
(booléen httpd_can_network_connect) ou lab-web injoignable" ;;
  404) note "/api/ répond 404 : le location existe mais lab-web ne sert \
rien à cette adresse" ;;
  *) ko "/api/ répond $CA" ;;
esac

# --- 6. plus aucun refus pour httpd_t ---------------------------------
if command -v ausearch >/dev/null 2>&1; then
  AVC=$(ausearch -m AVC -ts recent 2>/dev/null | grep -c 'httpd_t')
  [ "${AVC:-0}" -eq 0 ] \
    && ok "aucun AVC récent impliquant httpd_t" \
    || ko "$AVC lignes d'AVC récentes pour httpd_t : \
ausearch -m AVC -ts recent | audit2why"
else
  note "ausearch absent (dnf install audit) : contrôle des AVC ignoré"
fi

# --- 7. la procédure rendue à l'équipe --------------------------------
P="$LAB_HOME/lab15/procedure-selinux.md"
if [ -f "$P" ]; then
  if grep -qE 'setenforce|SELINUX=disabled|SELINUX=permissive' "$P"; then
    ko "la procédure contient encore un setenforce ou un mode dégradé"
  else
    ok "la procédure ne dégrade pas SELinux"
  fi
  grep -q 'semanage' "$P" \
    && ok "la procédure utilise semanage" \
    || ko "la procédure devrait s'appuyer sur semanage (port + fcontext)"
else
  ko "~/lab15/procedure-selinux.md absent (étape 7)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
