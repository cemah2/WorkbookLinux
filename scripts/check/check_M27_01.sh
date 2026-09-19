#!/usr/bin/env bash
# check_M27_01.sh — vérifie le lab L27.1 (logstats.py)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L27.1 =="

S="$HOME/lab27/bin/logstats.py"
LOG="$HOME/lab27/data/access.log"
PY="$HOME/lab27/venv/bin/python"; [ -x "$PY" ] || PY=python3
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

[ -f "$S" ] || { ko "$S est absent"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
ok "le script existe"
[ -f "$LOG" ] || { ko "$LOG absent : relance setup_M27.sh"; exit 1; }
[ -x "$S" ] && ok "bit d'exécution présent" || ko "chmod +x $S"
head -1 "$S" | grep -q '^#!/usr/bin/env python3' \
  && ok "shebang #!/usr/bin/env python3" || ko "shebang attendu : #!/usr/bin/env python3"

# --- aide et codes -------------------------------------------------------
"$PY" "$S" --help > "$TMP/aide" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -qi 'usage' "$TMP/aide" \
  && ok "--help sort en 0 avec un usage" || ko "--help : usage attendu, code 0"
"$PY" "$S" "$TMP/nexiste.pas" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" -eq 1 ] && ok "fichier absent -> code 1" \
  || ko "fichier absent : code 1 attendu, obtenu $rc (attrape OSError)"
grep -q 'Traceback' "$TMP/err" && ko "un Traceback fuit sur stderr : gère l'exception" \
  || ok "pas de Traceback pour un fichier absent"

# --- exécution nominale --------------------------------------------------
"$PY" "$S" "$LOG" > "$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 0 ] && ok "analyse d'access.log : code 0" || ko "code 0 attendu, obtenu $rc"
grep -q '10\.10\.10\.14' "$TMP/out" && grep -q '1212' "$TMP/out" \
  && ok "top IP : 10.10.10.14 avec 1212 requêtes" \
  || ko "10.10.10.14 (1212 requêtes) attendu en tête du top IP"
grep -Eq '200.*5906|5906.*200' "$TMP/out" && ok "code 200 : 5906" \
  || ko "5906 requêtes en 200 attendues"
grep -q '0\.537' "$TMP/out" && ok "p95 de latence = 0.537 s" \
  || ko "p95 attendu 0.537 (nearest-rank sur la liste triée)"

# --- JSON ----------------------------------------------------------------
"$PY" "$S" --json "$LOG" > "$TMP/j" 2>/dev/null
if "$PY" - "$TMP/j" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lignes"] == 7200, d.get("lignes")
lat = d["latence"] if "latence" in d else d
assert abs(float(lat["p95"]) - 0.537) < 1e-6, lat
EOF
then ok "--json : JSON valide, lignes=7200, p95=0.537"
else ko "--json doit produire un JSON avec 'lignes' et 'latence.p95'"; fi

# --- stdin et gzip -------------------------------------------------------
head -100 "$LOG" | "$PY" "$S" - > "$TMP/stdin" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q '100' "$TMP/stdin" \
  && ok "lecture depuis stdin avec '-'" || ko "'-' doit lire stdin (100 lignes)"
"$PY" "$S" "$HOME/lab27/data/access.log.1.gz" > "$TMP/gz" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q '1200' "$TMP/gz" \
  && ok "lecture transparente du .gz (1200 lignes)" \
  || ko "un .gz doit être lu (gzip.open en mode 'rt')"

# --- qualité -------------------------------------------------------------
if "$PY" -m ruff --version >/dev/null 2>&1; then
  "$PY" -m ruff check --quiet "$S" >/dev/null 2>&1 && ok "ruff check muet" \
    || ko "ruff check signale des problèmes : $PY -m ruff check $S"
else note "ruff absent du venv (pip install ruff)"; fi
grep -q 'access.log' "$TMP/out" 2>/dev/null || true

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
