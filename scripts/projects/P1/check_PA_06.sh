#!/usr/bin/env bash
# check_PA_06.sh — vérifie le jalon PA.6 (journaux centralisés, rotation)
# À lancer sur lab-web et lab-db (émetteurs) puis sur lab-ops (collecteur).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.6 sur $HOST =="

# --- commun : journald persistant et borné --------------------------------
[ -d /var/log/journal ] && ok "journald persistant (/var/log/journal)" \
  || ko "journald volatile : Storage=persistent + /var/log/journal"
grep -rhsq '^SystemMaxUse=' /etc/systemd/journald.conf \
     /etc/systemd/journald.conf.d/ \
  && ok "SystemMaxUse défini" || ko "SystemMaxUse non défini pour journald"
[ "$(systemctl is-active rsyslog)" = active ] && ok "rsyslog actif" \
  || ko "rsyslog inactif"
sudo -n rsyslogd -N1 >/dev/null 2>&1 && ok "rsyslogd -N1 : config valide" \
  || note "rsyslogd -N1 non exécutable ici (sudo -n)"

case "$HOST" in
lab-web|lab-db)
  grep -rhs '@@10.10.10.14:10514\|target="10.10.10.14"' /etc/rsyslog.d/ \
    | grep -q . && ok "transfert vers lab-ops:10514 en TCP configuré" \
    || ko "aucun fragment /etc/rsyslog.d/ n'envoie vers @@10.10.10.14:10514"
  grep -rhs 'queue.type\|queue.filename\|action.resumeRetryCount' \
    /etc/rsyslog.d/ | grep -q . \
    && ok "file d'attente disque configurée pour le transfert" \
    || ko "pas de file d'attente (queue.type/queue.filename) : les journaux \
seront perdus si lab-ops est injoignable"
  timeout 3 bash -c 'exec 3<>/dev/tcp/10.10.10.14/10514' 2>/dev/null \
    && ok "10514 de lab-ops joignable" || ko "10514 de lab-ops injoignable"
  logger -t factura-check "PA.6 test depuis $HOST $(date +%s)"
  note "une ligne de test vient d'être émise : vérifie-la sur lab-ops"
  if [ "$HOST" = lab-web ]; then
    ls /etc/logrotate.d/factura* >/dev/null 2>&1 \
      && ok "règle logrotate factura présente" \
      || ko "/etc/logrotate.d/factura absent"
    for f in /etc/logrotate.d/factura*; do
      [ -e "$f" ] || continue
      sudo -n logrotate -d "$f" >/dev/null 2>&1 \
        && ok "logrotate -d $f : sans erreur" \
        || ko "logrotate -d $f signale une erreur"
      grep -Eq 'daily|weekly' "$f" && ok "$f : fréquence définie" \
        || ko "$f : ni daily ni weekly"
      grep -q 'compress' "$f" && ok "$f : compression" \
        || ko "$f : pas de compress"
      grep -Eq 'rotate [0-9]+' "$f" && ok "$f : rétention chiffrée" \
        || ko "$f : rotate N manquant"
    done
    grep -rhs 'syslog:' /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ \
      | grep -q . && ok "nginx envoie ses journaux à syslog" \
      || ko "nginx n'écrit pas vers syslog (access_log syslog:server=...)"
  fi
  ;;
lab-ops)
  ss -Hltn 'sport = :10514' | grep -q . && ok "10514 en écoute" \
    || ko "rien n'écoute sur 10514 (module imtcp)"
  grep -rhs 'imtcp' /etc/rsyslog.d/ /etc/rsyslog.conf | grep -q . \
    && ok "module imtcp chargé" || ko "imtcp non chargé"
  for h in lab-web lab-db; do
    D=/var/log/remote/$h
    if sudo -n test -d "$D" 2>/dev/null || [ -d "$D" ]; then
      ok "$D existe"
      RECENT="$(sudo -n find "$D" -type f -mmin -60 2>/dev/null | head -n1)"
      [ -n "$RECENT" ] && ok "$h : un fichier a bougé dans l'heure ($RECENT)" \
        || ko "$h : rien reçu depuis une heure (logger sur $h puis regarde)"
    else
      ko "$D absent : template par hôte (\$fromhost-ip / hostname) attendu"
    fi
  done
  sudo -n grep -rqs 'factura-check' /var/log/remote/ 2>/dev/null \
    && ok "la ligne de test factura-check est arrivée" \
    || note "pas de ligne factura-check reçue (lance le check sur lab-web)"
  ls /etc/logrotate.d/remote* /etc/logrotate.d/rsyslog-remote* \
    >/dev/null 2>&1 && ok "rotation des journaux distants configurée" \
    || ko "pas de règle logrotate pour /var/log/remote"
  S="$(sudo -n ufw status 2>/dev/null || ufw status 2>/dev/null)"
  echo "$S" | grep -E '10514' | grep -Eq '10.10.10.1[12]' \
    && ok "ufw : 10514 restreint aux émetteurs" \
    || ko "ufw : 10514 doit être autorisé depuis 10.10.10.11 et .12 seulement"
  ;;
*) note "hostname $HOST hors projet" ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
