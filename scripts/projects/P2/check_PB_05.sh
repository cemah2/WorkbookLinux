#!/usr/bin/env bash
# check_PB_05.sh — vérifie le jalon PB.5 (rôle de déploiement Compose + vault)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.5 =="
REPO="${REPO:-$HOME/factura-v2}"
export PATH="$HOME/.local/bin:$PATH"
A="$REPO/ansible"
r() { ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$1" "$2" 2>/dev/null; }

[ -d "$A/roles/factura_compose" ] && ok "rôle factura_compose présent" \
  || ko "rôle ansible/roles/factura_compose manquant"
ls "$A"/roles/factura_compose/templates/*.j2 >/dev/null 2>&1 \
  && ok "templates Jinja du rôle présents" \
  || ko "aucun template .j2 dans le rôle (compose.yaml, .env)"
[ -f "$A/playbooks/deploy.yml" ] && ok "playbook deploy.yml présent" \
  || ko "ansible/playbooks/deploy.yml absent"
for e in staging prod; do
  V="$A/inventory/group_vars/$e/vault.yml"
  if [ -f "$V" ]; then
    head -1 "$V" | grep -q '^\$ANSIBLE_VAULT;' \
      && ok "vault $e chiffré" || ko "$V n'est PAS chiffré"
  else
    ko "$V absent"
  fi
done
git -C "$REPO" ls-files --error-unmatch .vault-pass >/dev/null 2>&1 \
  && ko ".vault-pass est versionné !" || ok ".vault-pass non versionné"
grep -rq 'vault_' "$A/inventory/group_vars/staging/main.yml" \
  "$A/inventory/group_vars/prod/main.yml" 2>/dev/null \
  && ok "indirection var -> vault_var dans main.yml" \
  || ko "les variables claires ne référencent pas vault_* (pattern d'indirection)"
if (cd "$REPO" && ansible-playbook -i ansible/inventory/staging.ini \
      ansible/playbooks/deploy.yml --check --diff >/tmp/ap.log 2>&1); then
  grep -qE 'changed=0 .*failed=0' /tmp/ap.log \
    && ok "deploy.yml idempotent sur staging (--check : changed=0)" \
    || ko "deploy.yml n'est pas idempotent (changed>0 en --check, /tmp/ap.log)"
else
  ko "ansible-playbook deploy.yml --check échoue (/tmp/ap.log)"
fi

for e in staging prod; do
  case $e in staging) W=10.10.10.21; D=10.10.10.22;; *) W=10.10.10.31; D=10.10.10.32;; esac
  echo "-- $e"
  r "$W" 'stat -c %a:%U /srv/factura/.env' | grep -qE '^600:(deploy|root)' \
    && ok "$e : /srv/factura/.env en 0600" \
    || ko "$e : /srv/factura/.env absent ou lisible par tous"
  r "$W" 'grep -c "^DB_PASSWORD=" /srv/factura/.env' | grep -q 1 \
    && ok "$e : DB_PASSWORD injecté depuis le vault" \
    || ko "$e : DB_PASSWORD absent du .env"
  r "$W" 'cat /srv/factura/.env' | grep -qE 'devpass|changeme' \
    && ko "$e : mot de passe de dev en prod/staging !" \
    || ok "$e : pas de mot de passe de démo"
  r "$W" 'docker ps --format {{.Names}}' >/tmp/ps.$$
  for c in nginx api worker redis; do
    grep -q "$c" /tmp/ps.$$ && ok "$e web : conteneur $c" \
      || ko "$e web : conteneur $c absent"
  done
  r "$D" 'docker ps --format {{.Names}}' | grep -q postgres \
    && ok "$e db : conteneur postgres" || ko "$e db : postgres absent"
  r "$D" 'sudo ufw status' | grep -E '5432' | grep -q "$W" \
    && ok "$e db : 5432 ouvert uniquement pour $W" \
    || ko "$e db : 5432 n'est pas restreint à la VM web"
  curl -fsS -m 5 "http://$W/health" | grep -q '"status":"ok"' \
    && ok "$e : http://$W/health -> ok" \
    || ko "$e : /health ne répond pas ok"
  rm -f /tmp/ps.$$
done
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
