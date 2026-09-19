#!/usr/bin/env bash
# check_M04_02.sh — vérifie le lab L4.2 (compte de service facturasvc)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L4.2 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"

getent passwd facturasvc >/dev/null || {
  ko "le compte facturasvc n'existe plus : il fallait le corriger, pas le supprimer"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

SVC_UID=$(id -u facturasvc)
SHELL_SVC=$(getent passwd facturasvc | cut -d: -f7)
HOME_SVC=$(getent passwd facturasvc | cut -d: -f6)
HASH_SVC=$(getent shadow facturasvc | cut -d: -f2)

# --- 1. UID système -----------------------------------------------------
if [ "$SVC_UID" -lt 1000 ] && [ "$SVC_UID" -ge 100 ]; then
  ok "UID $SVC_UID dans la plage système (100-999)"
else
  ko "UID $SVC_UID hors plage système (usermod -u, plage SYS_UID_* de login.defs)"
fi

# --- 2. shell sans connexion -------------------------------------------
case "$SHELL_SVC" in
  */nologin|*/false)
    ok "shell $SHELL_SVC : aucune connexion interactive" ;;
  *)
    ko "shell $SHELL_SVC : un compte de service ne doit pas avoir de shell" ;;
esac

# --- 3. mot de passe inutilisable --------------------------------------
case "$HASH_SVC" in
  '*'|'!'|'!!')
    ok "champ mot de passe = '$HASH_SVC' : aucune authentification possible" ;;
  '!'*)
    ko "le hachage d'origine est encore là sous le '!' (usermod -p '*' l'écrase)" ;;
  '')
    ko "champ mot de passe VIDE : connexion sans mot de passe, c'est pire" ;;
  *)
    ko "facturasvc a toujours un mot de passe utilisable" ;;
esac

# --- 4. plus aucun groupe d'administration ------------------------------
BAD=""
for g in sudo wheel adm root docker; do
  getent group "$g" >/dev/null || continue
  id -nG facturasvc | tr ' ' '\n' | grep -qx "$g" && BAD="$BAD $g"
done
if [ -z "$BAD" ]; then
  ok "facturasvc n'appartient à aucun groupe d'administration"
else
  ko "facturasvc est encore dans :$BAD (gpasswd -d facturasvc <groupe>)"
fi

# --- 5. home applicatif -------------------------------------------------
case "$HOME_SVC" in
  /home/*)
    ko "home $HOME_SVC : un compte de service ne vit pas dans /home" ;;
  /nonexistent)
    ok "home /nonexistent : convention Debian pour un compte sans home" ;;
  *)
    ok "home $HOME_SVC hors de /home"
    if [ -d "$HOME_SVC" ]; then
      mode=$(stat -c '%a' "$HOME_SVC")
      case "$mode" in
        7[05]0|750|700) ok "  $HOME_SVC en $mode (pas d'accès pour other)" ;;
        *)              ko "  $HOME_SVC en $mode, attendu 750 ou plus strict" ;;
      esac
      [ "$(stat -c '%U' "$HOME_SVC")" = facturasvc ] \
        && ok "  $HOME_SVC appartient à facturasvc" \
        || ko "  $HOME_SVC n'appartient pas à facturasvc"
    fi ;;
esac
[ -d /home/facturasvc ] && \
  note "/home/facturasvc existe encore : à supprimer une fois les données déplacées"

# --- 6. aucune ouverture de session possible ----------------------------
if su - facturasvc -c true >/dev/null 2>&1; then
  ko "su - facturasvc ouvre encore une session"
else
  ok "su - facturasvc échoue"
fi

# --- 7. le service continue de fonctionner ------------------------------
if pgrep -u facturasvc >/dev/null 2>&1; then
  ok "un processus tourne toujours sous facturasvc (service préservé)"
else
  ko "plus aucun processus sous facturasvc : le service a été interrompu"
fi
if su -s /bin/sh facturasvc -c 'cat /opt/factura/etc/factura.conf' \
     >/dev/null 2>&1; then
  ok "le service lit toujours /opt/factura/etc/factura.conf"
else
  ko "le service ne peut plus lire sa configuration (groupe factura perdu ?)"
fi

# --- 8. plus aucun fichier orphelin -------------------------------------
ORPH=$(find /etc /home /opt /srv /usr /var -xdev \( -nouser -o -nogroup \) \
       -print 2>/dev/null | head -5)
if [ -z "$ORPH" ]; then
  ok "aucun fichier sans propriétaire dans /etc /home /opt /srv /usr /var"
else
  ko "fichiers orphelins après changement d'UID, par exemple : $(echo "$ORPH" \
     | head -1) (find / -xdev -uid <ancien> -exec chown ...)"
fi

# --- 9. rapport d'état des lieux ----------------------------------------
RAP="$LAB_HOME/lab04/rapports/facturasvc-avant.txt"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 5 ]; then
  ok "le constat initial est consigné dans facturasvc-avant.txt"
else
  ko "rapport $RAP absent ou trop court (état des lieux de l'étape 1)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
