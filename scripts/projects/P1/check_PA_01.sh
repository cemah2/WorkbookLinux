#!/usr/bin/env bash
# check_PA_01.sh — vérifie le jalon PA.1 (terrain, comptes, arborescence)
# À lancer sur chaque VM du projet : les tests dépendent du hostname.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.1 sur $HOST =="

# --- résolution de noms, partout ----------------------------------------
for h in lab-adm:10.10.10.10 lab-web:10.10.10.11 lab-db:10.10.10.12 \
         lab-ops:10.10.10.14 factura.lab.local:10.10.10.11; do
  name="${h%%:*}"; ip="${h##*:}"
  if getent hosts "$name" | grep -q "^$ip"; then
    ok "$name -> $ip"
  else
    ko "$name ne résout pas vers $ip (complète /etc/hosts)"
  fi
done

# --- helpers ------------------------------------------------------------
dir_is() {   # dir_is <chemin> <owner:group>[|<owner:group>] <mode>
  local d="$1" own="$2" mode="$3" got o
  if [ ! -d "$d" ]; then ko "$d absent"; return; fi
  got="$(stat -c '%U:%G %a' "$d")"
  for o in ${own//|/ }; do
    [ "$got" = "$o $mode" ] && { ok "$d ($got)"; return; }
  done
  ko "$d : $got attendu $own $mode"
}
svc_user() {  # svc_user <nom> <home>
  local u="$1" home="$2" ent shell uid
  ent="$(getent passwd "$u")" || { ko "compte $u absent"; return; }
  shell="${ent##*:}"; uid="$(echo "$ent" | cut -d: -f3)"
  case "$shell" in
    */nologin|*/false) ok "compte $u sans shell interactif" ;;
    *) ko "compte $u a un shell interactif ($shell) : compte de service ?" ;;
  esac
  [ "$uid" -lt 1000 ] && ok "compte $u est un compte système (uid $uid)" \
    || ko "compte $u a un uid >= 1000 : utilise useradd -r / --system"
  [ "$(echo "$ent" | cut -d: -f6)" = "$home" ] \
    && ok "home de $u = $home" || ko "home de $u attendu : $home"
}

[ -d /usr/local/src/factura ] \
  && ok "sources déposées dans /usr/local/src/factura (setup_P1.sh)" \
  || ko "lance sudo bash setup_P1.sh d'abord"

case "$HOST" in
lab-web)
  svc_user factura /srv/factura
  dir_is /opt/factura      root:root       755
  dir_is /etc/factura      root:factura    750
  dir_is /srv/factura      root:root       755
  dir_is /srv/factura/www  root:root       755
  dir_is /srv/factura/exports factura:factura 750
  # LogsDirectory= (PA.3) remet le groupe du service : les deux sont admis
  dir_is /var/log/factura  'factura:adm|factura:factura' 750
  dir_is /var/lib/factura  factura:factura 750
  dir_is /var/backups/factura factura:factura 750
  ;;
lab-db)
  dir_is /var/log/factura  root:adm        750
  dir_is /etc/factura      root:root       750
  ;;
lab-ops)
  if ent="$(getent passwd backup)"; then
    ok "compte backup présent"
    [ "$(echo "$ent" | cut -d: -f6)" = /srv/backups ] \
      && ok "home de backup = /srv/backups" \
      || ko "home de backup attendu : /srv/backups"
    [ "$(echo "$ent" | cut -d: -f3)" -lt 1000 ] \
      && ok "backup est un compte système" \
      || ko "backup doit être un compte système (useradd -r)"
    case "${ent##*:}" in
      */nologin|*/false) ko "backup a le shell ${ent##*:} : la commande \
forcée (rrsync) serait refusée, usermod -s /bin/sh backup" ;;
      *) ok "backup a un shell (${ent##*:}) pour la commande forcée" ;;
    esac
  else
    ko "compte backup absent (il recevra les sauvegardes par rsync/ssh)"
  fi
  dir_is /srv/backups      root:root       755
  dir_is /srv/backups/factura backup:backup 750
  if [ -L /var/log/factura ]; then   # DynamicUser + LogsDirectory (PA.8)
    ok "/var/log/factura -> $(readlink /var/log/factura) (DynamicUser)"
  else
    dir_is /var/log/factura root:adm   750
  fi
  ;;
lab-adm)
  H="$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)"
  [ -d "$H/P1/pki" ] && ok "$H/P1/pki existe" \
    || ko "crée $H/P1/pki (elle servira au jalon PA.5)"
  [ -f "$H/P1/journal.md" ] && [ "$(wc -l < "$H/P1/journal.md")" -ge 5 ] \
    && ok "journal de bord commencé" \
    || ko "journal de bord vide : note au moins ce que tu as fait en PA.1"
  ;;
*)
  note "hostname $HOST hors projet : seuls les tests communs sont faits" ;;
esac

# --- aucun secret dans un répertoire lisible par tous ---------------------
if [ -d /etc/factura ]; then
  if find /etc/factura -type f -perm /o+r 2>/dev/null | grep -q .; then
    ko "un fichier de /etc/factura est lisible par tous (chmod o-r)"
  else
    ok "aucun fichier de /etc/factura lisible par « others »"
  fi
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
