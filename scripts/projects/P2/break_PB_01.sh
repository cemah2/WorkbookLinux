#!/usr/bin/env bash
# break_PB_01.sh — INC-B1 : le pipeline est vert, la prod calcule mal la TVA
# À lancer avec sudo sur lab-adm. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/INC-B1/ (image d'origine, digest).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
REPO="${REPO:-$LAB_HOME/factura-v2}"
BK=/root/.breakfix-backup/INC-B1
PROD_WEB=10.10.10.31
REG=lab-ops.lab.local:3000
NS=mathieu
mkdir -p "$BK"
u() { sudo -u "$LAB_USER" -H env PATH="$LAB_HOME/.local/bin:$PATH" "$@"; }

TAG=$(curl -fsS -m 5 "http://$PROD_WEB/version" | jq -r .version)
[ -n "$TAG" ] && [ "$TAG" != null ] || { echo "prod injoignable" >&2; exit 1; }
IMG="$REG/$NS/factura-api:$TAG"

# 1. sauvegarde de l'image d'origine (telle que construite par la CI)
if [ ! -f "$BK/factura-api-$TAG.tar" ]; then
  u docker pull -q "$IMG" >/dev/null
  u docker image inspect --format '{{index .RepoDigests 0}}' "$IMG" \
    > "$BK/digest-origine-$TAG.txt"
  u docker save "$IMG" > "$BK/factura-api-$TAG.tar"
  echo "$TAG" > "$BK/tag.txt"
fi

# 2. image « corrigée » par un collègue, poussée sous le MÊME tag
TMP=$(mktemp -d); chown "$LAB_USER" "$TMP"
cat > "$TMP/Dockerfile" <<EOF
FROM $IMG
USER root
RUN sed -i 's/taux=0.20)/taux=0.196)/' /app/app.py
USER app
EOF
u docker build -q -t "$IMG" "$TMP" >/dev/null
rm -rf "$TMP"
VAULT=$(u ansible-vault view --vault-password-file "$REPO/.vault-pass" \
        "$REPO/ansible/inventory/group_vars/prod/vault.yml")
RU=$(echo "$VAULT" | awk -F'"' '/vault_registry_user/{print $2}')
RT=$(echo "$VAULT" | awk -F'"' '/vault_registry_token/{print $2}')
printf '%s' "$RT" | u docker login "$REG" -u "$RU" --password-stdin >/dev/null 2>&1
u docker push -q "$IMG" >/dev/null
u docker logout "$REG" >/dev/null 2>&1 || true

# 3. « relance du déploiement avec le même tag » faite à la main sur la VM
sudo -u "$LAB_USER" ssh -o BatchMode=yes "deploy@$PROD_WEB" bash -s <<'EOS' >/dev/null 2>&1
set -e
cd /srv/factura
ACT=$(awk -F= '/^ACTIVE=/{print $2}' state.env)
[ "$ACT" = blue ] && NEW=green || NEW=blue
TAG=$(curl -fsS localhost/version | jq -r .version)
sed -i "s/^TAG_$(echo $NEW | tr a-z A-Z)=.*/TAG_$(echo $NEW | tr a-z A-Z)=$TAG/" state.env
sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=blue,green/" state.env
docker compose --env-file .env --env-file state.env --profile blue --profile green \
  pull -q api-$NEW
docker compose --env-file .env --env-file state.env --profile blue --profile green \
  up -d --force-recreate api-$NEW
for i in $(seq 30); do
  curl -fsS "localhost:$([ $NEW = blue ] && echo 8081 || echo 8082)/health" \
    >/dev/null 2>&1 && break; sleep 2
done
bin/switch.sh $NEW "redeploiement $TAG (rafraichissement)"
EOS

cat <<EOF
Symptôme : le service comptable signale des TTC faux depuis ce matin.
  curl -s http://$PROD_WEB/version            -> tag $TAG (comme vendredi)
  POST /api/factures {"montant_ht":100}        -> montant_ttc 119.6 en prod
  Le staging renvoie 120.0. Le dernier run cd-prod est vert.
EOF
