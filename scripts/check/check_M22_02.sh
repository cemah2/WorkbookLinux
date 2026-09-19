#!/usr/bin/env bash
# check_M22_02.sh — vérifie le lab L22.2 (image factura-api:1.0 propre)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L22.2 =="

IMG=factura-api:1.0
API="$HOME/lab22/api"
insp() { docker image inspect "$IMG" --format "$1" 2>/dev/null; }

docker info >/dev/null 2>&1 || { ko "Docker inaccessible (L22.1)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

if docker image inspect "$IMG" >/dev/null 2>&1; then
  ok "l'image $IMG existe"
else
  ko "image $IMG introuvable (docker build --build-arg APP_VERSION=1.0 \
-t $IMG ~/lab22/api)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- 1. métadonnées de l'image ------------------------------------------
TAILLE=$(insp '{{.Size}}')
if [ "$TAILLE" -lt $((150 * 1024 * 1024)) ]; then
  ok "taille $((TAILLE / 1024 / 1024)) Mio (< 150)"
else
  ko "image trop grosse : $((TAILLE / 1024 / 1024)) Mio (base slim, \
multi-stage, pas d'outils inutiles, --no-cache-dir)"
fi
U=$(insp '{{.Config.User}}')
case "$U" in
  ""|root|0|0:0) ko "l'image tourne en root (USER manquant ou trop tôt)" ;;
  *) ok "utilisateur d'exécution : $U" ;;
esac
[ -n "$(insp '{{.Config.Healthcheck}}')" ] && \
  [ "$(insp '{{.Config.Healthcheck}}')" != "<nil>" ] \
  && ok "HEALTHCHECK présent" || ko "aucun HEALTHCHECK dans l'image"
EP=$(insp '{{index .Config.Entrypoint 0}}')
case "$EP" in
  /bin/sh|sh|/bin/bash|bash|"") ko "ENTRYPOINT absent ou en forme shell \
(inspect montre $EP) : forme exec attendue" ;;
  *) ok "ENTRYPOINT en forme exec ($EP)" ;;
esac
insp '{{.Config.Env}}' | grep -qiE 'FACTURA_CLE_API|Factura-2024' \
  && ko "un secret de l'ancien Dockerfile est encore dans ENV" \
  || ok "aucun secret dans les variables d'environnement de l'image"
[ "$(insp '{{index .Config.Labels "org.opencontainers.image.version"}}')" \
  = "1.0" ] \
  && ok "label org.opencontainers.image.version=1.0" \
  || ko "label org.opencontainers.image.version absent ou différent de 1.0"
BASE=$(insp '{{.Config.Env}}' | grep -o 'PYTHON_VERSION=[0-9.]*' | head -1)
[ -n "$BASE" ] && note "base Python détectée : $BASE"

# --- 2. contenu ---------------------------------------------------------
if docker run --rm --entrypoint sh "$IMG" -c \
  'ls /app/secret.txt /app/donnees /app/README.md 2>/dev/null' \
  | grep -q .; then
  ko "des fichiers parasites sont dans /app (secret.txt, donnees/, *.md) : \
.dockerignore"
else
  ok "pas de fichier parasite dans /app"
fi
[ -s "$API/.dockerignore" ] && ok ".dockerignore présent dans ~/lab22/api" \
  || ko "$API/.dockerignore manquant"
grep -qiE '^FROM .*:latest|^FROM python:3$|^FROM python$' "$API/Dockerfile" \
  2>/dev/null && ko "le Dockerfile utilise un tag flottant (latest / 3)" \
  || ok "image de base épinglée dans le Dockerfile"
grep -qE '^FROM .* AS ' "$API/Dockerfile" 2>/dev/null \
  && ok "Dockerfile multi-stage" || ko "pas de multi-stage (FROM … AS …)"

# --- 3. comportement : démarrage, santé, arrêt propre -------------------
docker rm -f chk18-02 >/dev/null 2>&1
if docker run -d --name chk18-02 -p 127.0.0.1:18002:8000 "$IMG" \
   >/dev/null 2>&1; then
  for _ in $(seq 1 30); do
    [ "$(docker inspect chk18-02 --format '{{.State.Health.Status}}' \
      2>/dev/null)" = healthy ] && break
    sleep 1
  done
  [ "$(docker inspect chk18-02 --format '{{.State.Health.Status}}')" \
    = healthy ] && ok "le conteneur passe à healthy" \
    || ko "le conteneur ne devient pas healthy en 30 s (docker inspect \
--format '{{json .State.Health}}')"
  curl -fsS --max-time 3 http://127.0.0.1:18002/sante >/dev/null 2>&1 \
    && ok "/sante répond" || ko "/sante ne répond pas sur 18002"
  UID_APP=$(curl -fsS --max-time 3 http://127.0.0.1:18002/ 2>/dev/null \
    | jq -r .uid 2>/dev/null)
  [ "$UID_APP" = 10001 ] && ok "l'API tourne avec l'UID 10001" \
    || ko "l'API tourne avec l'UID ${UID_APP:-?} au lieu de 10001"
  DEBUT=$(date +%s%N)
  docker stop chk18-02 >/dev/null 2>&1
  DUREE=$(( ($(date +%s%N) - DEBUT) / 1000000 ))
  [ "$DUREE" -lt 2000 ] && ok "docker stop en ${DUREE} ms" \
    || ko "docker stop a pris ${DUREE} ms : PID 1 sourd à SIGTERM"
  [ "$(docker inspect chk18-02 --format '{{.State.ExitCode}}')" = 0 ] \
    && ok "code de sortie 0 après stop" \
    || ko "code de sortie $(docker inspect chk18-02 \
--format '{{.State.ExitCode}}') après stop (attendu 0)"
  docker rm -f chk18-02 >/dev/null 2>&1
else
  ko "impossible de lancer l'image (port 18002 pris ? docker logs)"
fi

# --- 4. rapports --------------------------------------------------------
A="$HOME/lab22/rapports/audit-dockerfile.md"
[ -s "$A" ] && [ "$(grep -c '^|' "$A")" -ge 10 ] \
  && ok "audit-dockerfile.md présent avec un tableau d'au moins 8 lignes" \
  || ko "$A absent ou tableau trop court (8 défauts minimum)"
[ -s "$HOME/lab22/rapports/trivy-factura-api.txt" ] \
  && ok "rapport Trivy enregistré" \
  || ko "rapport ~/lab22/rapports/trivy-factura-api.txt absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
