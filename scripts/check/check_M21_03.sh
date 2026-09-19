#!/usr/bin/env bash
# check_M21_03.sh — vérifie le lab L21.3 (blue/green derrière nginx)
# À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L21.3 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab21"
API=http://10.10.10.14:3000/api/v1
TOKEN=$(tr -d '[:space:]' < "$BASE/.gitea-token" 2>/dev/null || true)
REPO="$API/repos/mathieu/factura"
api() { curl -s -m 10 -H "Authorization: token $TOKEN" "$@"; }
SSH="ssh -i $BASE/keys/bg -o BatchMode=yes -o ConnectTimeout=5 \
 -o StrictHostKeyChecking=accept-new deploy@10.10.10.11"

# --- 1. nginx en frontal, couleur annoncée ---------------------------------
H=$(curl -sI -m 5 http://10.10.10.11/ | tr -d '\r')
COLOR=$(printf '%s' "$H" | awk 'tolower($1)=="x-factura-color:"{print $2}')
if printf '%s' "$H" | grep -q '^HTTP/.* 200'; then
  ok "http://10.10.10.11/ répond 200 via nginx"
else
  ko "http://10.10.10.11/ ne répond pas 200 (site factura.conf ? symlink ?)"
fi
case "$COLOR" in
  blue|green) ok "en-tête X-Factura-Color : $COLOR" ;;
  *) ko "X-Factura-Color absent ou invalide ('$COLOR') : map + add_header ?" ;;
esac

# --- 2. deux couleurs, deux tags ------------------------------------------
ST=$($SSH status 2>/dev/null || true)
if printf '%s' "$ST" | grep -q 'live='; then
  ok "factura-bg status : $(printf '%s' "$ST" | head -1)"
  TB=$(printf '%s' "$ST" | sed -n 's/^TAG_BLUE=//p')
  TG=$(printf '%s' "$ST" | sed -n 's/^TAG_GREEN=//p')
  if [ -n "$TB" ] && [ -n "$TG" ] && [ "$TB" != "$TG" ]; then
    ok "blue ($TB) et green ($TG) portent des tags différents"
  else
    ko "TAG_BLUE et TAG_GREEN doivent être définis et différents"
  fi
  LIVE=$(printf '%s' "$ST" | sed -n 's/.*live=\([a-z]*\).*/\1/p' | head -1)
  [ "$LIVE" = "$COLOR" ] && ok "couleur live ($LIVE) = couleur servie" \
    || ko "status dit live=$LIVE mais nginx sert $COLOR"
else
  ko "la clé bg ne renvoie pas « status » (authorized_keys, factura-bg ?)"
fi
V=$($SSH smoke 2>/dev/null | tr -d '[:space:]')
[ -n "$V" ] && ok "sous-commande smoke : la couleur inactive sert $V" \
  || ko "« smoke » ne renvoie rien (curl local sur le port inactif)"

# --- 3. pas de coupure pendant une bascule --------------------------------
if [ -n "$ST" ]; then
  codes=""
  ( for i in $(seq 1 40); do
      curl -s -o /dev/null -m 2 -w '%{http_code} ' http://10.10.10.11/
      sleep 0.1
    done ) > /tmp/check_m21_03_codes &
  sleep 1
  $SSH switch >/dev/null 2>&1; sleep 1
  $SSH back >/dev/null 2>&1
  wait
  codes=$(cat /tmp/check_m21_03_codes); rm -f /tmp/check_m21_03_codes
  if printf '%s' "$codes" | tr ' ' '\n' | grep -v '^$' | grep -qv '^200$'; then
    ko "codes autres que 200 pendant switch/back : $codes"
  else
    ok "40 requêtes en 200 pendant un switch puis un back"
  fi
fi

# --- 4. le workflow ------------------------------------------------------
WF=$(api "$REPO/raw/.gitea/workflows/ci.yaml")
printf '%s' "$WF" | python3 - <<'EOF' && ok "deploy : stage → smoke → switch → smoke, back conditionné à l'issue de switch" \
  || ko "deploy : attendu steps stage/smoke/switch/smoke et back avec steps.<switch>.outcome"
import sys, yaml
w = yaml.safe_load(sys.stdin)
steps = w["jobs"]["deploy"]["steps"]
txt = [str(s.get("run", "")) for s in steps]
i_stage = next(i for i, t in enumerate(txt) if "stage" in t)
i_switch = next(i for i, t in enumerate(txt) if "switch" in t)
i_back = next(i for i, t in enumerate(txt) if "back" in t)
assert i_stage < i_switch < i_back
assert any("smoke" in t for t in txt[i_stage + 1:i_switch])
assert "outcome" in str(steps[i_back].get("if", "")) and "failure()" in str(steps[i_back].get("if", ""))
EOF

# --- 5. rapport -------------------------------------------------------------
grep -qiE 'canar|split_clients|weight' "$BASE/rapports/pipeline.md" 2>/dev/null \
  && ok "pipeline.md aborde le canari nginx" \
  || ko "pipeline.md : section canari (weight ou split_clients) attendue"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
