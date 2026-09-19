#!/usr/bin/env bash
# check_PC_1_4.sh — vérifie le ticket PC.1.4 (502 après déploiement)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.1.4 =="
SAUV=/root/.breakfix-backup; ID=PC_1_4
R="--resolve factura.lab.local:443:127.0.0.1"

CODE=$(curl -s -o /dev/null -w '%{http_code}' $R https://factura.lab.local/version)
[ "$CODE" = "200" ] && ok "le site répond 200 à travers nginx" \
  || ko "le site répond « $CODE » (nginx error.log : connect() failed ?)"

V=$(curl -s $R https://factura.lab.local/version | grep -o '"version": *"[^"]*"' \
    | cut -d'"' -f4)
[ "$V" = "2.4.0" ] && ok "la version déployée (2.4.0) est en ligne : pas de rollback" \
  || ko "version en ligne « $V » : le déploiement 2.4.0 devait rester (interdit : rollback)"

systemctl is-active -q factura-api.service && ok "factura-api actif" \
  || ko "factura-api n'est pas actif"

# cohérence : le port où l'API écoute est celui que nginx cible
PA=$(ss -tlnpH 2>/dev/null | awk '/python3/ {print $4}' | sed 's/.*://' | head -1)
PN=$(grep -rhoE 'server 127\.0\.0\.1:[0-9]+' /etc/nginx/ 2>/dev/null \
     | head -1 | sed 's/.*://')
if [ -n "$PA" ] && [ "$PA" = "$PN" ]; then
  ok "l'API écoute sur $PA, nginx cible $PN : cohérent"
else
  ko "API sur « $PA », upstream nginx sur « $PN » : incohérent"
fi

# le fichier de déploiement a-t-il été corrigé à la source ?
if [ -r /etc/factura/api.env ]; then
  grep -q '^PORT=8081' /etc/factura/api.env \
    && note "PORT ramené à 8081 côté API (source de vérité : nginx)" \
    || note "PORT laissé à $(grep '^PORT=' /etc/factura/api.env) : nginx adapté"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
