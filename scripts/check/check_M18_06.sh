#!/usr/bin/env bash
# check_M18_06.sh — vérifie le défi D18 (livraison de factura-api 2.0)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D18 =="

REG=lab-ops.lab.local:5000
IMG="$REG/factura-api:2.0"
D="$HOME/lab18/compose"
S="$HOME/lab18/bin/livrer.sh"
R="$HOME/lab18/rapports/runbook-docker.md"
insp() { docker image inspect "$IMG" --format "$1" 2>/dev/null; }

docker info >/dev/null 2>&1 || { ko "Docker inaccessible (L18.1)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. l'image ---------------------------------------------------------
if docker image inspect "$IMG" >/dev/null 2>&1; then
  ok "image $IMG présente localement"
  T=$(insp '{{.Size}}')
  [ "$T" -lt $((150 * 1024 * 1024)) ] \
    && ok "taille $((T / 1024 / 1024)) Mio (< 150)" \
    || ko "image trop grosse : $((T / 1024 / 1024)) Mio"
  case "$(insp '{{.Config.User}}')" in
    ""|root|0|0:0) ko "l'image tourne en root" ;;
    *[!0-9:]*) ko "USER doit être numérique (lu : $(insp '{{.Config.User}}'))" ;;
    *) ok "utilisateur numérique $(insp '{{.Config.User}}')" ;;
  esac
  [ "$(insp '{{.Config.Healthcheck}}')" != "<nil>" ] \
    && ok "HEALTHCHECK présent" || ko "HEALTHCHECK absent"
  case "$(insp '{{index .Config.Entrypoint 0}}')" in
    ""|sh|/bin/sh|bash|/bin/bash) ko "ENTRYPOINT absent ou forme shell" ;;
    *) ok "ENTRYPOINT en forme exec" ;;
  esac
  [ "$(insp '{{index .Config.Labels "org.opencontainers.image.version"}}')" \
    = "2.0" ] && ok "label version=2.0" || ko "label \
org.opencontainers.image.version doit valoir 2.0"
  insp '{{.RepoDigests}}' | grep -q "$REG/factura-api@sha256:" \
    && ok "l'image a été poussée dans le registre (RepoDigests)" \
    || ko "aucun digest $REG dans RepoDigests : docker push manquant"
else
  ko "image $IMG absente (livrer.sh 2.0 ?)"
fi
grep -qiE '^FROM .*:latest|^FROM [a-z]+:[0-9]+($| )' "$HOME/lab18/api/Dockerfile" \
  2>/dev/null && ko "Dockerfile : tag de base flottant" \
  || ok "Dockerfile : base épinglée"

# --- 2. la pile prod ----------------------------------------------------
if [ -f "$D/compose.yaml" ] && [ -f "$D/compose.prod.yaml" ]; then
  J=$(cd "$D" && APP_VERSION=2.0 docker compose -f compose.yaml \
    -f compose.prod.yaml config --format json 2>/dev/null)
  [ -n "$J" ] && ok "compose.yaml + compose.prod.yaml valides" \
    || ko "docker compose -f compose.yaml -f compose.prod.yaml config échoue"
  echo "$J" | jq -e '.services.app.build == null' >/dev/null 2>&1 \
    && ok "prod : pas de build:" || ko "prod : build: encore présent"
  echo "$J" | jq -e ".services.app.image | test(\"$REG\")" >/dev/null 2>&1 \
    && ok "prod : image du registre" || ko "prod : app.image hors registre"
  echo "$J" | jq -e '.services.app.read_only == true and (.services.app.cap_drop | index("ALL") != null)' \
    >/dev/null 2>&1 && ok "app : read_only + cap_drop ALL" \
    || ko "app : read_only: true et cap_drop: [ALL] attendus"
  echo "$J" | jq -e '.services.app.security_opt | map(test("no-new-privileges")) | any' \
    >/dev/null 2>&1 && ok "app : no-new-privileges" \
    || ko "app : security_opt no-new-privileges manquant"
  echo "$J" | jq -e '(.services.app.mem_limit // .services.app.deploy.resources.limits.memory) != null' \
    >/dev/null 2>&1 && ok "app : limite mémoire" || ko "app : mem_limit manquant"
  echo "$J" | jq -e '.services.app.logging.options["max-size"]' >/dev/null 2>&1 \
    && ok "app : journaux bornés" || ko "app : logging max-size manquant"
  echo "$J" | jq -e '.services.app.secrets' >/dev/null 2>&1 \
    && ok "app : secret déclaré" || ko "app : aucun secret Compose"
  [ "$(echo "$J" | jq -r '.services.app.depends_on.db.condition')" \
    = service_healthy ] && ok "app attend db healthy" \
    || ko "app.depends_on.db : condition service_healthy attendue"
else
  ko "$D/compose.yaml ou compose.prod.yaml manquant"
fi
V=$(curl -fsS --max-time 4 http://127.0.0.1:8080/version 2>/dev/null \
  | jq -r .version 2>/dev/null)
case "$V" in
  2.*) ok "/version répond $V via le proxy" ;;
  *)   ko "/version ne répond pas 2.x sur :8080 (lu : ${V:-rien})" ;;
esac
CI=$(docker inspect factura-app-1 --format '{{.Config.Image}}' 2>/dev/null)
echo "$CI" | grep -q "^$REG/" && ok "factura-app-1 tourne depuis $CI" \
  || ko "factura-app-1 ne tourne pas depuis l'image du registre (${CI:-absent})"
[ "$(docker inspect factura-app-1 --format '{{.State.Health.Status}}' \
  2>/dev/null)" = healthy ] && ok "factura-app-1 healthy" \
  || ko "factura-app-1 n'est pas healthy"

# --- 3. le script ------------------------------------------------------
if [ -x "$S" ]; then
  ok "livrer.sh présent et exécutable"
  head -5 "$S" | grep -q 'set -euo pipefail' && ok "bash strict" \
    || ko "livrer.sh : set -euo pipefail attendu en tête"
  grep -q 'trivy' "$S" && ok "livrer.sh appelle Trivy" \
    || ko "livrer.sh n'appelle pas trivy"
  grep -qE 'docker (image )?inspect' "$S" \
    && ok "livrer.sh lit l'image avec docker inspect" \
    || ko "livrer.sh doit contrôler taille et utilisateur via docker inspect"
  grep -q 'docker push' "$S" && ok "livrer.sh pousse l'image" \
    || ko "livrer.sh ne fait pas de docker push"
  grep -q -- '--wait' "$S" && ok "livrer.sh attend la santé (--wait)" \
    || ko "livrer.sh : docker compose up --wait attendu"
  bash -n "$S" 2>/dev/null && ok "syntaxe bash valide" \
    || ko "livrer.sh : erreur de syntaxe (bash -n)"
  grep -qE '\$\{1:\?|\$#|\$\{1\}|"\$1"' "$S" \
    && ok "livrer.sh prend la version en argument" \
    || ko "livrer.sh doit prendre la version en premier argument"
else
  ko "$S absent ou non exécutable"
fi
L="$HOME/lab18/rapports/livraisons.log"
[ -s "$L" ] && grep -q '2.0' "$L" && grep -q 'sha256' "$L" \
  && ok "livraisons.log contient la 2.0 avec son digest" \
  || ko "$L absent ou sans ligne 2.0 + digest"
grep -q '2.1' "$L" 2>/dev/null && ok "livraison 2.1 journalisée" \
  || ko "pas de livraison 2.1 dans le journal"

# --- 4. le runbook ------------------------------------------------------
if [ -s "$R" ]; then
  [ "$(wc -l < "$R")" -ge 40 ] && ok "runbook d'au moins 40 lignes" \
    || ko "runbook trop court"
  for mot in 'pg-data' '137' 'system df' 'docker.sock' 'privileged'; do
    grep -qi -- "$mot" "$R" && ok "runbook : $mot traité" \
      || ko "runbook : rien sur « $mot »"
  done
else
  ko "runbook $R absent"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
