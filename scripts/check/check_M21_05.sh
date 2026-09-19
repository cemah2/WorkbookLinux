#!/usr/bin/env bash
# check_M21_05.sh — vérifie le lab L21.5 (forge Gitea sur lab-ops)
# À lancer depuis lab-adm (ou n'importe quelle VM du lab).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification L21.5 =="

URL=${GITEA_URL:-http://10.10.10.14:3000}
D="$HOME/lab21/factura-infra"

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/" || echo 000)
[ "$code" = 200 ] && ok "Gitea répond sur $URL (HTTP $code)" \
                  || ko "Gitea ne répond pas sur $URL (HTTP $code) : service \
lancé ? ss -tlnp | grep 3000 sur lab-ops"

ver=$(curl -s --max-time 5 "$URL/api/v1/version" 2>/dev/null)
printf '%s' "$ver" | has '"version"' \
  && ok "API v1 accessible : $ver" \
  || ko "l'API $URL/api/v1/version ne répond pas"

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  "$URL/api/v1/repos/infra/factura-infra" || echo 000)
[ "$code" = 200 ] && ok "le dépôt infra/factura-infra existe et est lisible" \
                  || ko "infra/factura-infra introuvable sur Gitea (HTTP $code)"

br=$(curl -s --max-time 5 "$URL/api/v1/repos/infra/factura-infra/branches" \
     2>/dev/null)
printf '%s' "$br" | has '"name":"main"' \
  && ok "la branche main est poussée" || ko "pas de branche main sur Gitea"

prot=$(curl -s --max-time 5 \
  "$URL/api/v1/repos/infra/factura-infra/branch_protections" 2>/dev/null)
if printf '%s' "$prot" | has '"branch_name":"main"'; then
  ok "une protection de branche existe sur main"
else
  note "protection de main non visible sans jeton (normal si l'API l'exige) ; \
vérifie dans Settings > Branches"
fi

if git -C "$D" remote get-url gitea 2>/dev/null | has '10.10.10.14\|lab-ops'
then ok "remote « gitea » déclaré dans ~/lab21/factura-infra"
else ko "pas de remote gitea dans $D (git remote add gitea ...)"; fi

if ssh -o BatchMode=yes -o ConnectTimeout=5 -p 2222 git@10.10.10.14 2>&1 \
   | has -i 'gitea\|does not provide shell'; then
  ok "le SSH de Gitea (port 2222) accepte ta clé"
else note "SSH Gitea sur 2222 non vérifiable (clé non enregistrée, ou HTTP only)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
