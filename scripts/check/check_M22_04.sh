#!/usr/bin/env bash
# check_M22_04.sh — vérifie le lab L22.4 (pile Compose factura)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L22.4 =="

D="$HOME/lab22/compose"
docker info >/dev/null 2>&1 || { ko "Docker inaccessible (L22.1)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
[ -f "$D/compose.yaml" ] || { ko "$D/compose.yaml absent"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
cd "$D" || exit 1

# --- 1. fichiers valides ------------------------------------------------
CONF=$(docker compose config 2>/dev/null)
[ -n "$CONF" ] && ok "compose.yaml (+ override) est valide" \
  || ko "docker compose config échoue : $(docker compose config 2>&1 | head -1)"
[ "$(docker compose config --format json 2>/dev/null | jq -r .name)" \
  = factura ] && ok "nom de projet : factura" \
  || ko "le projet doit s'appeler factura (name: factura)"
for s in proxy app db cache; do
  echo "$CONF" | grep -qE "^  $s:" && ok "service $s défini" \
    || ko "service $s absent"
done
docker compose config --services 2>/dev/null | grep -qx adminer \
  && ko "adminer démarre sans profil : profiles: [debug] manquant" \
  || ok "adminer n'est pas actif par défaut"
docker compose --profile debug config --services 2>/dev/null \
  | grep -qx adminer && ok "adminer disponible avec --profile debug" \
  || ko "adminer absent du profil debug"
[ -f compose.override.yaml ] && ok "compose.override.yaml présent" \
  || ko "compose.override.yaml manquant"
if [ -f compose.prod.yaml ]; then
  PROD=$(docker compose -f compose.yaml -f compose.prod.yaml config \
    --format json 2>/dev/null)
  [ -n "$PROD" ] && ok "compose.prod.yaml valide" \
    || ko "compose.prod.yaml invalide"
  echo "$PROD" | jq -e '.services.app.image | test("lab-ops.lab.local:5000")' \
    >/dev/null 2>&1 && ok "prod : image tirée du registre" \
    || ko "prod : app.image doit pointer sur lab-ops.lab.local:5000/…"
  echo "$PROD" | jq -e '.services.app.build == null' >/dev/null 2>&1 \
    && ok "prod : pas de build:" \
    || ko "prod : la clé build: est encore présente (build: !reset null)"
  echo "$PROD" | jq -e '.services.app.logging.options["max-size"]' \
    >/dev/null 2>&1 && ok "prod : rotation des journaux définie" \
    || ko "prod : logging.options.max-size manquant sur app"
else
  ko "compose.prod.yaml manquant"
fi

# --- 2. dépendances et santé -------------------------------------------
J=$(docker compose config --format json 2>/dev/null)
for s in db cache; do
  echo "$J" | jq -e ".services.$s.healthcheck.test" >/dev/null 2>&1 \
    && ok "healthcheck sur $s" || ko "healthcheck manquant sur $s"
  [ "$(echo "$J" | jq -r ".services.app.depends_on.$s.condition")" \
    = service_healthy ] && ok "app attend $s healthy" \
    || ko "app.depends_on.$s doit avoir condition: service_healthy"
done
[ "$(echo "$J" | jq -r '.services.proxy.depends_on.app.condition')" \
  = service_healthy ] && ok "proxy attend app healthy" \
  || ko "proxy.depends_on.app doit avoir condition: service_healthy"

# --- 3. secret et durcissement ------------------------------------------
echo "$J" | jq -e '.secrets.db_password.file' >/dev/null 2>&1 \
  && ok "secret db_password déclaré (file)" \
  || ko "secret db_password manquant au niveau racine"
echo "$J" | jq -e '.services.app.environment | to_entries[] | select(.value | tostring | test("Factura-2024|password|passwd"; "i"))' \
  >/dev/null 2>&1 && ko "un mot de passe transite par environment: de app" \
  || ok "pas de mot de passe dans environment: de app"
echo "$J" | jq -e '.services.app.read_only == true' >/dev/null 2>&1 \
  && ok "app en lecture seule" || ko "app : read_only: true manquant"
echo "$J" | jq -e '.services.app.cap_drop | index("ALL")' >/dev/null 2>&1 \
  && ok "app : cap_drop ALL" || ko "app : cap_drop: [ALL] manquant"
RP=0
for s in proxy app db cache; do
  [ "$(echo "$J" | jq -r ".services.$s.restart")" = unless-stopped ] \
    || { ko "$s : restart: unless-stopped attendu"; RP=1; }
done
[ "$RP" -eq 0 ] && ok "restart: unless-stopped sur les quatre services"

# --- 4. pile en marche --------------------------------------------------
for s in app db cache; do
  ST=$(docker inspect "factura-$s-1" --format '{{.State.Health.Status}}' \
    2>/dev/null)
  [ "$ST" = healthy ] && ok "factura-$s-1 est healthy" \
    || ko "factura-$s-1 n'est pas healthy (état : ${ST:-absent})"
done
[ "$(docker inspect factura-proxy-1 --format '{{.State.Running}}' \
  2>/dev/null)" = true ] && ok "factura-proxy-1 tourne" \
  || ko "factura-proxy-1 ne tourne pas"
curl -fsS --max-time 4 http://127.0.0.1:8080/clients 2>/dev/null \
  | grep -q clients && ok "/clients répond via le proxy (PostgreSQL OK)" \
  || ko "/clients ne répond pas sur :8080 (proxy, DATABASE_URL, secret ?)"
curl -fsS --max-time 4 http://127.0.0.1:8080/compteur 2>/dev/null \
  | grep -q compteur && ok "/compteur répond via le proxy (Redis OK)" \
  || ko "/compteur ne répond pas sur :8080"
if SEC=$(cat secrets/db_password.txt 2>/dev/null) && [ -n "$SEC" ]; then
  docker inspect factura-app-1 --format '{{.Config.Env}}' 2>/dev/null \
    | grep -qF "$SEC" && ko "le mot de passe est visible dans docker inspect" \
    || ok "le mot de passe n'apparaît pas dans docker inspect de app"
fi
[ -s "$HOME/lab22/rapports/compose.md" ] && ok "rapport compose.md présent" \
  || ko "~/lab22/rapports/compose.md absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
