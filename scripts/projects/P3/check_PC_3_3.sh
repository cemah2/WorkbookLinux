#!/usr/bin/env bash
# check_PC_3_3.sh — vérifie le ticket PC.3.3 (DNS/résolution interne cassée)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.3.3 =="
SAUV=/root/.breakfix-backup; ID=PC_3_3

# 1. lab-db se résout de nouveau
if getent hosts lab-db >/dev/null 2>&1; then
  ok "lab-db se résout ($(getent hosts lab-db | awk '{print $1}'))"
else
  ko "lab-db ne se résout pas (getent hosts lab-db)"
fi

# 2. /sante repasse au vert
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/sante)
[ "$CODE" = "200" ] && ok "/sante répond 200 (résolution rétablie)" \
  || ko "/sante répond « $CODE » (l'API ne résout toujours pas sa base)"
curl -s http://127.0.0.1:8081/sante | grep -q '"db_resolution": *"ok' \
  && ok "l'API résout sa base" \
  || ko "db_resolution encore en échec dans /sante"

# 3. le correctif est au bon endroit (résolution), pas une IP en dur dans api.env
if grep -qsE '^(DB_HOST|REDIS_HOST)=([0-9]{1,3}\.){3}[0-9]{1,3}$' \
     /etc/factura/api.env; then
  ko "MALUS : IP codée en dur dans api.env — corrige la résolution, pas la conf"
else
  ok "api.env pointe toujours la base par son nom"
fi

# 4. le site répond de bout en bout
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/sante)
[ "$CODE" = "200" ] && ok "site en service via nginx" \
  || ko "le site renvoie « $CODE »"

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
