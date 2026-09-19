#!/usr/bin/env bash
# check_M22_05.sh — vérifie le lab L22.5 (registre privé TLS + auth)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L22.5 =="

REG=lab-ops.lab.local:5000
docker info >/dev/null 2>&1 || { ko "Docker inaccessible (L22.1)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. conteneur -------------------------------------------------------
if [ "$(docker inspect registre --format '{{.State.Running}}' 2>/dev/null)" \
  = true ]; then
  ok "conteneur registre en cours d'exécution"
  docker inspect registre --format '{{.Config.Image}}' | grep -q '^registry:2' \
    && ok "image registry:2.x" || ko "l'image du registre n'est pas registry:2.x"
  docker inspect registre --format '{{range .Mounts}}{{.Name}} {{end}}' \
    | grep -qw registre-data && ok "volume registre-data monté" \
    || ko "le volume registre-data n'est pas monté sur le registre"
  [ "$(docker inspect registre --format '{{.HostConfig.RestartPolicy.Name}}')" \
    != no ] && ok "politique de redémarrage définie" \
    || ko "pas de --restart sur le registre"
  docker inspect registre --format '{{.Config.Env}}' \
    | grep -q 'REGISTRY_AUTH=htpasswd' && ok "authentification htpasswd activée" \
    || ko "REGISTRY_AUTH=htpasswd absent de l'environnement du registre"
  docker inspect registre --format '{{.Config.Env}}' \
    | grep -q 'REGISTRY_HTTP_TLS_CERTIFICATE=' && ok "TLS activé" \
    || ko "REGISTRY_HTTP_TLS_CERTIFICATE absent : le registre est en clair"
else
  ko "conteneur registre absent ou arrêté"
fi
getent hosts lab-ops.lab.local >/dev/null \
  && ok "lab-ops.lab.local se résout" \
  || ko "lab-ops.lab.local ne se résout pas (/etc/hosts)"

# --- 2. comportement HTTP ----------------------------------------------
CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 4 \
  "https://$REG/v2/" 2>/dev/null)
case "$CODE" in
  401) ok "https://$REG/v2/ répond 401 sans identifiants" ;;
  200) ko "le registre répond 200 sans identifiants : pas d'authentification" ;;
  *)   ko "https://$REG/v2/ ne répond pas en TLS (code ${CODE:-vide})" ;;
esac
curl -s -o /dev/null --max-time 4 "http://$REG/v2/" 2>/dev/null \
  && ko "le registre répond encore en HTTP clair" \
  || ok "pas de réponse en HTTP clair"

# --- 3. confiance et identifiants côté client --------------------------
CA="/etc/docker/certs.d/$REG/ca.crt"
[ -s "$CA" ] && ok "certificat de confiance déposé dans /etc/docker/certs.d" \
  || ko "$CA absent"
AUTH=$(jq -r --arg r "$REG" '.auths[$r].auth // empty' \
  "$HOME/.docker/config.json" 2>/dev/null)
if [ -n "$AUTH" ]; then
  ok "docker login enregistré pour $REG"
  CRED=$(echo "$AUTH" | base64 -d 2>/dev/null)
  CAT=$(curl -s --max-time 4 ${CA:+--cacert "$CA"} -k -u "$CRED" \
    "https://$REG/v2/_catalog" 2>/dev/null)
  echo "$CAT" | grep -q '"factura-api"' \
    && ok "factura-api présent dans le catalogue" \
    || ko "factura-api absent du catalogue ($CAT)"
  echo "$CRED" | grep -q '^ci:' && ok "utilisateur ci" \
    || note "utilisateur enregistré : ${CRED%%:*} (ci attendu)"
else
  ko "aucun identifiant pour $REG dans ~/.docker/config.json (docker login)"
fi
if [ -r /etc/docker/daemon.json ]; then
  jq -e '."insecure-registries" // [] | index("lab-ops.lab.local:5000")' \
    /etc/docker/daemon.json >/dev/null 2>&1 \
    && ko "lab-ops.lab.local:5000 est encore en insecure-registries" \
    || ok "insecure-registries ne mentionne plus le registre"
fi
docker image inspect "$REG/factura-api:1.0" >/dev/null 2>&1 \
  && ok "image locale taguée $REG/factura-api:1.0" \
  || note "pas d'image locale $REG/factura-api:1.0 (supprimée après push ?)"
[ -s "$HOME/lab22/rapports/registre.md" ] && ok "rapport registre.md présent" \
  || ko "~/lab22/rapports/registre.md absent"
note "les tests depuis lab-adm et lab-rhel ne sont pas vérifiés ici"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
