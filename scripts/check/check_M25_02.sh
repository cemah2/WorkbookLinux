#!/usr/bin/env bash
# check_M25_02.sh — vérifie le lab L25.2 (pipeline complet + rollback)
# À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L25.2 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab25"
API=http://10.10.10.14:3000/api/v1
TOKEN=$(tr -d '[:space:]' < "$BASE/.gitea-token" 2>/dev/null || true)
REPO="$API/repos/mathieu/factura"
REG=http://10.10.10.14:5000
REGAUTH='mathieu:Factura-Reg-2026'
api() { curl -s -m 10 -H "Authorization: token $TOKEN" "$@"; }
json() { python3 -c "import sys,json; d=json.load(sys.stdin); $1" 2>/dev/null; }
SSH="ssh -i $BASE/keys/deploy -o BatchMode=yes -o ConnectTimeout=5 \
 -o StrictHostKeyChecking=accept-new deploy@10.10.10.11"

# --- 1. registre : image du dernier commit de main -------------------------
git -C "$BASE/factura" fetch -q origin main 2>/dev/null
SHA=$(git -C "$BASE/factura" rev-parse --short=12 origin/main 2>/dev/null)
TAGS=$(curl -s -m 5 -u "$REGAUTH" "$REG/v2/factura/tags/list")
if printf '%s' "$TAGS" | grep -q "\"$SHA\""; then
  ok "le registre contient factura:$SHA (dernier commit de main)"
else
  ko "pas d'image factura:$SHA dans le registre (job build/push passé ?)"
fi

# --- 2. la prod sert une version identifiable -----------------------------
V=$(curl -fs -m 5 http://10.10.10.11:8080/version | tr -d '[:space:]')
if [ -n "$V" ]; then
  ok "lab-web:8080/version répond : $V"
  if [ "$V" = "$SHA" ]; then
    ok "la prod sert le dernier commit de main"
  elif git -C "$BASE/factura" cat-file -e "$V^{commit}" 2>/dev/null; then
    note "la prod sert $V (un commit connu, pas le dernier : rollback en cours ?)"
  else
    ko "la version servie ($V) ne correspond à aucun commit du dépôt"
  fi
else
  ko "http://10.10.10.11:8080/version ne répond pas (compose sur lab-web ?)"
fi

# --- 3. la clé de déploiement est bien bridée ----------------------------
OUT=$($SSH id 2>&1 || true)
if printf '%s' "$OUT" | grep -q 'uid='; then
  ko "la clé deploy exécute des commandes arbitraires (commande forcée absente)"
elif [ -z "$OUT" ] && ! $SSH status >/dev/null 2>&1; then
  ko "ssh deploy@lab-web refuse la connexion (authorized_keys ? from= ?)"
else
  ok "commande forcée active : « id » n'est pas exécuté"
fi
ST=$($SSH status 2>/dev/null || true)
printf '%s' "$ST" | grep -q '^TAG=' \
  && ok "sous-commande status : $(printf '%s' "$ST" | grep '^TAG=')" \
  || ko "« status » ne renvoie pas TAG= (factura-deploy incomplet ?)"
$SSH "deploy latest" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then
  ok "« deploy latest » refusé (code 2)"
else
  ko "« deploy latest » doit sortir en 2 avant toute action (code obtenu : $rc)"
fi

# --- 4. le workflow ------------------------------------------------------
WF=$(api "$REPO/raw/.gitea/workflows/ci.yaml")
printf '%s' "$WF" | python3 - <<'EOF' && ok "ci.yaml : build (needs) → deploy (main, concurrency) avec rollback if: failure()" \
  || ko "ci.yaml : attendu build needs [lint,test], deploy needs build + concurrency, step if: failure()"
import sys, yaml
w = yaml.safe_load(sys.stdin); j = w["jobs"]
assert set(j["build"]["needs"]) >= {"lint", "test"}
d = j["deploy"]
assert "build" in str(d["needs"]) and "concurrency" in d
assert "main" in str(d.get("if", ""))
assert any("failure()" in str(s.get("if", "")) for s in d["steps"])
assert "trivy" in str(j["build"]["steps"])
EOF
printf '%s' "$WF" | grep -q 'password-stdin' \
  && ok "login registre par --password-stdin" \
  || ko "pas de docker login par --password-stdin dans le workflow"
printf '%s' "$WF" | grep -qE 'run:.*\$\{\{ *secrets\.' \
  && ko "un secret est interpolé directement dans un run: (passe par env:)" \
  || ok "aucun secret interpolé directement dans un run:"

# --- 5. secrets et variables du dépôt --------------------------------------
S=$(api "$REPO/actions/secrets")
for s in DEPLOY_SSH_KEY REGISTRY_PASSWORD; do
  printf '%s' "$S" | grep -qi "\"name\": *\"$s\"" \
    && ok "secret $s déclaré" || ko "secret $s absent du dépôt"
done
Vv=$(api "$REPO/actions/variables")
printf '%s' "$Vv" | grep -qi '"LAB_WEB_HOSTKEY"' \
  && ok "variable LAB_WEB_HOSTKEY déclarée" || ko "variable LAB_WEB_HOSTKEY absente"

# --- 6. rapports ------------------------------------------------------------
[ -s "$BASE/rapports/pipeline.md" ] && ok "rapports/pipeline.md présent" \
  || ko "rapports/pipeline.md absent"
for f in .gitlab-ci.yml github-ci.yaml; do
  p="$BASE/rapports/equivalents/$f"
  if [ -s "$p" ]; then
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$p" 2>/dev/null \
      && ok "equivalents/$f : YAML valide" || ko "equivalents/$f : YAML invalide"
  else
    note "equivalents/$f absent (étape 9)"
  fi
done

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
