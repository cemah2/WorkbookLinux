#!/usr/bin/env bash
# check_M27_02.sh — vérifie le lab L27.2 (inventaire.py)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L27.2 =="

S="$HOME/lab27/bin/inventaire.py"
FX="$HOME/lab27/fixtures/proxmox-qemu.json"
PY="$HOME/lab27/venv/bin/python"; [ -x "$PY" ] || PY=python3
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

[ -f "$S" ] || { ko "$S est absent"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
ok "le script existe"
[ -f "$FX" ] || { ko "$FX absent : relance setup_M27.sh"; exit 1; }

# --- INI par défaut ------------------------------------------------------
"$PY" "$S" --fixture "$FX" > "$TMP/ini" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 0 ] && ok "--fixture : code 0" || ko "code 0 attendu, obtenu $rc"
grep -Eq '^lab-web[[:space:]]+ansible_host=10\.10\.10\.11' "$TMP/ini" \
  && ok "lab-web ansible_host=10.10.10.11 (depuis ipconfig0)" \
  || ko "attendu : « lab-web ansible_host=10.10.10.11 » (parse ipconfig0)"
grep -q 'tpl-ubuntu-2404' "$TMP/ini" && ko "le template tpl-ubuntu-2404 ne doit pas apparaître" \
  || ok "le template est ignoré"
grep -q 'ct-dns' "$TMP/ini" && ko "le conteneur LXC ct-dns ne doit pas apparaître" \
  || ok "le conteneur LXC est ignoré"
grep -q 'lab-web-old' "$TMP/ini" && ko "lab-web-old est arrêtée : exclue sans --all" \
  || ok "la VM arrêtée est exclue par défaut"
grep -q '^\[prod\]' "$TMP/ini" && ok "groupe [prod] présent (tag Proxmox)" \
  || ko "un groupe [prod] est attendu (tags séparés par ';')"
awk '/^\[prod\]/{f=1;next} /^\[/{f=0} f' "$TMP/ini" | grep -q 'lab-db' \
  && ok "lab-db est dans [prod]" || ko "lab-db doit être membre de [prod]"
grep -q 'lab-sandbox' "$TMP/ini" && ko "lab-sandbox (dhcp, sans DNS) doit être omise" \
  || ok "la VM sans adresse est omise"
grep -qi 'sandbox' "$TMP/err" && ok "et signalée sur stderr" \
  || ko "l'omission de lab-sandbox doit être journalisée sur stderr"

# --- --all ---------------------------------------------------------------
"$PY" "$S" --fixture "$FX" --all 2>/dev/null | grep -q 'lab-web-old' \
  && ok "--all inclut la VM arrêtée" || ko "--all doit inclure lab-web-old"

# --- YAML ----------------------------------------------------------------
"$PY" "$S" --fixture "$FX" --format yaml > "$TMP/yaml" 2>/dev/null
if "$PY" - "$TMP/yaml" <<'EOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
h = d["all"]["hosts"]
assert h["lab-db"]["ansible_host"] == "10.10.10.12", h
assert "lab-web" in d["all"]["children"]["prod"]["hosts"]
EOF
then ok "--format yaml : structure all/hosts/children valide"
else ko "--format yaml : all.hosts.lab-db.ansible_host et all.children.prod attendus"; fi

# --- erreurs -------------------------------------------------------------
"$PY" "$S" --fixture "$TMP/nope.json" >/dev/null 2>"$TMP/e2"; rc=$?
[ "$rc" -eq 1 ] && ! grep -q Traceback "$TMP/e2" \
  && ok "fixture absente -> code 1, sans Traceback" \
  || ko "fixture absente : code 1 attendu sans Traceback (obtenu $rc)"
env -u PVE_TOKEN "$PY" "$S" --url https://10.10.10.1:8006 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "sans PVE_TOKEN -> code 2" \
  || ko "sans PVE_TOKEN, code 2 attendu (obtenu $rc)"

if command -v ansible-inventory >/dev/null 2>&1; then
  ansible-inventory -i "$TMP/ini" --list >/dev/null 2>&1 \
    && ok "ansible-inventory accepte le fichier INI" \
    || ko "ansible-inventory -i fichier --list refuse ton INI"
else note "ansible-inventory absent : validation Ansible sautée"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
