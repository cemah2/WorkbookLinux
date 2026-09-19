#!/usr/bin/env bash
# check_PC_4_4.sh — vérifie le ticket PC.4.4 (healthcheck trop strict)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.4.4 =="
SAUV=/root/.breakfix-backup; ID=PC_4_4
command -v docker >/dev/null 2>&1 || { echo "Docker absent"; exit 0; }

# 1. le conteneur tourne et est en bonne santé
ETAT=$(docker inspect -f '{{.State.Health.Status}}' factura-worker 2>/dev/null || echo absent)
case "$ETAT" in
  healthy) ok "factura-worker est healthy" ;;
  starting) note "factura-worker en cours de démarrage, relance le check dans 20 s" ;;
  *) ko "factura-worker n'est pas healthy (état: $ETAT)" ;;
esac

# 2. il ne redémarre plus en boucle : uptime > 90 s
STARTED=$(docker inspect -f '{{.State.StartedAt}}' factura-worker 2>/dev/null)
if [ -n "$STARTED" ]; then
  AGE=$(( $(date +%s) - $(date -d "$STARTED" +%s) ))
  [ "$AGE" -ge 90 ] && ok "conteneur stable depuis ${AGE}s" \
    || ko "conteneur redémarré il y a ${AGE}s (< 90 s : encore en boucle ?)"
  RC=$(docker inspect -f '{{.RestartCount}}' factura-worker 2>/dev/null)
  note "RestartCount = $RC"
fi

# 3. le healthcheck a été détendu au bon endroit
TO=$(grep -E '^HC_TIMEOUT=' /etc/factura/worker.env | cut -d= -f2)
sec() { echo "$1" | tr -dc 0-9; }
if [ "$(sec "$TO")" -ge 3 ]; then
  ok "HC_TIMEOUT = $TO (> temps de réponse de la sonde ~1,5 s)"
else
  ko "HC_TIMEOUT = $TO : toujours plus court que la sonde (1,5 s)"
fi
RE=$(grep -E '^HC_RETRIES=' /etc/factura/worker.env | cut -d= -f2)
[ "${RE:-1}" -ge 3 ] && ok "HC_RETRIES = $RE (tolère un pic isolé)" \
  || ko "HC_RETRIES = $RE : une seule tentative, aucun amortissement"

# 4. pas de contournement : le healthcheck n'a pas été purement supprimé
HC=$(docker inspect -f '{{if .Config.Healthcheck}}présent{{else}}absent{{end}}' \
     factura-worker 2>/dev/null)
[ "$HC" = "présent" ] && ok "un healthcheck est toujours défini" \
  || ko "MALUS : le healthcheck a été supprimé au lieu d'être corrigé"

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
