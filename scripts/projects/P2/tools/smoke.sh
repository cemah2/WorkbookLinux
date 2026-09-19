#!/usr/bin/env bash
# smoke.sh — test de fumée d'une instance Factura
# usage : smoke.sh http://factura-staging-web [tag_attendu]
set -uo pipefail
BASE="${1:?url de base}"; TAG="${2:-}"
FAIL=0
t() { if "$@" >/dev/null 2>&1; then echo "  ok   $*"; else echo "  FAIL $*"; FAIL=1; fi; }
t curl -fsS -m 5 "$BASE/health"
t curl -fsS -m 5 "$BASE/version"
t curl -fsS -m 5 "$BASE/api/factures"
code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"client":"smoke","montant_ht":10}' "$BASE/api/factures")
[ "$code" = 201 ] && echo "  ok   POST /api/factures -> 201" \
  || { echo "  FAIL POST /api/factures -> $code"; FAIL=1; }
if [ -n "$TAG" ]; then
  v=$(curl -fsS -m 5 "$BASE/version" | jq -r .version)
  [ "$v" = "$TAG" ] && echo "  ok   version $v" \
    || { echo "  FAIL version $v != $TAG"; FAIL=1; }
fi
exit $FAIL
