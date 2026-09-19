#!/usr/bin/env bash
# check_PB_04.sh — vérifie le jalon PB.4 (images et stack Compose)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.4 =="
REPO="${REPO:-$HOME/factura-v2}"
cd "$REPO/app" 2>/dev/null || { ko "$REPO/app introuvable"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

for img in api worker; do
  D="$img/Dockerfile"
  [ -f "$D" ] || { ko "$D absent"; continue; }
  [ "$(grep -ciE '^FROM ' "$D")" -ge 2 ] && ok "$D : multi-stage" \
    || ko "$D : un seul FROM (multi-stage attendu)"
  grep -qE '^USER +[a-z0-9_]+' "$D" && ! grep -qE '^USER +root' "$D" \
    && ok "$D : USER non-root" || ko "$D : pas de USER non-root"
  grep -qE '^HEALTHCHECK' "$D" && ok "$D : HEALTHCHECK" \
    || ko "$D : HEALTHCHECK manquant"
  grep -qiE 'python:3\.[0-9]+-slim|alpine|distroless' "$D" \
    && ok "$D : image de base légère" || ko "$D : image de base lourde ?"
  [ -f "$img/.dockerignore" ] && ok "$img/.dockerignore présent" \
    || ko "$img/.dockerignore manquant (tests/ et caches entrent dans l'image)"
done
grep -qE 'ARG +APP_VERSION' api/Dockerfile \
  && ok "la version est injectée au build (ARG APP_VERSION)" \
  || ko "pas d'ARG APP_VERSION : /version ne pourra pas dire quoi tourne"

# --- images construites localement -------------------------------------
if docker image inspect factura-api:dev >/dev/null 2>&1; then
  ok "image factura-api:dev existe"
  U=$(docker image inspect -f '{{.Config.User}}' factura-api:dev)
  [ -n "$U" ] && [ "$U" != root ] && [ "$U" != 0 ] \
    && ok "factura-api:dev tourne en $U" || ko "factura-api:dev tourne en root"
  S=$(docker image inspect -f '{{.Size}}' factura-api:dev)
  [ "$S" -lt 250000000 ] && ok "taille image $((S/1000000)) Mo (< 250)" \
    || ko "image trop grosse : $((S/1000000)) Mo (multi-stage ? slim ?)"
  docker image inspect -f '{{.Config.Healthcheck}}' factura-api:dev \
    | grep -q CMD && ok "healthcheck présent dans l'image" \
    || ko "pas de healthcheck dans l'image"
else
  ko "image factura-api:dev absente (docker build -t factura-api:dev api/)"
fi

# --- scan ---------------------------------------------------------------
if [ -f "$REPO/docs/scan-api.txt" ] || ls "$REPO"/docs/scan-*.{txt,json} \
   >/dev/null 2>&1; then
  ok "rapport de scan présent dans docs/"
else
  ko "aucun rapport de scan dans docs/ (trivy image ... > docs/scan-api.txt)"
fi

# --- compose -------------------------------------------------------------
[ -f compose.yaml ] || { ko "app/compose.yaml absent"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
if docker compose config -q 2>/tmp/cc.log; then
  ok "docker compose config valide"
else
  ko "compose.yaml invalide : $(head -1 /tmp/cc.log)"
fi
SVC=$(docker compose config --services 2>/dev/null)
for s in nginx api worker postgres redis; do
  echo "$SVC" | grep -qx "$s" && ok "service $s défini" \
    || ko "service $s absent de compose.yaml"
done
docker compose config 2>/dev/null | grep -A3 'postgres:' | grep -q healthcheck \
  || docker compose config 2>/dev/null | grep -q 'pg_isready' \
  && ok "healthcheck PostgreSQL" || ko "pas de healthcheck sur postgres"
docker compose config 2>/dev/null | grep -q 'condition: service_healthy' \
  && ok "depends_on avec condition service_healthy" \
  || ko "depends_on sans condition : l'API démarre avant la base"
docker compose config 2>/dev/null | grep -E '^\s+- (published|target):' \
  | grep -qE '5432|6379' \
  && ko "postgres ou redis publie son port sur l'hôte" \
  || ok "postgres/redis non publiés sur l'hôte"
# stack en marche ?
if docker compose ps --status running 2>/dev/null | grep -q api; then
  ok "la stack tourne"
  P=$(docker compose port nginx 80 2>/dev/null | sed 's/.*://')
  curl -fsS -m 5 "http://127.0.0.1:${P:-8080}/health" | grep -q '"ok"' \
    && ok "/health via nginx répond ok" \
    || ko "/health via nginx ne répond pas ok (docker compose logs api)"
  curl -fsS -m 5 -X POST -H 'Content-Type: application/json' \
    -d '{"client":"check","montant_ht":50}' \
    "http://127.0.0.1:${P:-8080}/api/factures" | grep -q '"id"' \
    && ok "POST /api/factures crée une facture" \
    || ko "POST /api/factures échoue"
  sleep 2
  docker compose logs worker 2>/dev/null | grep -q 'facture trait' \
    && ok "le worker traite les jobs" || ko "le worker ne traite rien"
else
  ko "la stack n'est pas démarrée (docker compose up -d)"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
