#!/usr/bin/env bash
# check_M23_03.sh — vérifie le lab L23.3 (sante.py + timer)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L23.3 =="

S="$HOME/lab23/bin/sante.py"
PY="$HOME/lab23/venv/bin/python"; [ -x "$PY" ] || PY=python3
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; [ "${HTTP_PID:-0}" -gt 0 ] && kill "$HTTP_PID" 2>/dev/null' EXIT

[ -f "$S" ] || { ko "$S est absent"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
ok "le script existe"

# un serveur HTTP jetable pour avoir une cible qui répond
mkdir -p "$TMP/www"; echo 'sante ok' > "$TMP/www/index.html"
( cd "$TMP/www" && exec python3 -m http.server 18080 --bind 127.0.0.1 >/dev/null 2>&1 ) &
HTTP_PID=$!
sleep 1

cat > "$TMP/ok.yaml" <<EOF
timeout: 2
verifications:
  - {nom: web, type: http, url: "http://127.0.0.1:18080/", contient: "sante"}
  - {nom: port, type: tcp, hote: 127.0.0.1, port: 18080}
  - {nom: racine, type: disque, chemin: /, pct_max: 99}
  - {nom: cmd, type: commande, argv: ["true"]}
EOF
cat > "$TMP/ko.yaml" <<EOF
timeout: 2
verifications:
  - {nom: web, type: http, url: "http://127.0.0.1:18080/"}
  - {nom: mort, type: tcp, hote: 127.0.0.1, port: 1}
  - {nom: plein, type: disque, chemin: /, pct_max: 0}
EOF

# --- tout OK -------------------------------------------------------------
"$PY" "$S" -c "$TMP/ok.yaml" > "$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 0 ] && ok "configuration saine -> code 0" || ko "code 0 attendu, obtenu $rc"
if "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["statut"]=="OK"; assert len(d["verifications"])==4' "$TMP/out" 2>/dev/null
then ok "stdout est un JSON avec statut OK et 4 vérifications"
else ko "stdout doit être un JSON : {statut, verifications[...]}"; fi

# --- CRITICAL ------------------------------------------------------------
"$PY" "$S" -c "$TMP/ko.yaml" > "$TMP/out2" 2>/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "port fermé + disque plein -> code 2 (CRITICAL)" \
  || ko "code 2 attendu (le pire des statuts), obtenu $rc"
grep -q '"CRITICAL"' "$TMP/out2" && ok "statut CRITICAL dans le JSON" \
  || ko "le JSON doit porter le statut CRITICAL"
"$PY" "$S" -c "$TMP/ko.yaml" --only web >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--only web -> code 0" || ko "--only NOM doit ne lancer qu'une vérification"

# --- UNKNOWN et robustesse -------------------------------------------------
"$PY" "$S" -c "$TMP/absent.yaml" >/dev/null 2>"$TMP/e3"; rc=$?
[ "$rc" -eq 3 ] && ok "configuration absente -> code 3 (UNKNOWN)" \
  || ko "code 3 attendu pour une configuration absente, obtenu $rc"
grep -q Traceback "$TMP/e3" && ko "Traceback sur stderr : attrape OSError" || ok "pas de Traceback"

# --- écriture atomique ---------------------------------------------------
"$PY" "$S" -c "$TMP/ok.yaml" -o "$TMP/sante.json" >/dev/null 2>&1
[ -s "$TMP/sante.json" ] && ok "-o écrit le fichier JSON" || ko "-o FICHIER doit écrire le rapport"
[ "$(find "$TMP" -maxdepth 1 -name '.*' -o -maxdepth 1 -name '*.tmp' | wc -l)" -eq 0 ] \
  && ok "aucun fichier temporaire résiduel" || ko "un temporaire traîne : os.replace après écriture"

# --- systemd -------------------------------------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^sante.timer'; then
  ok "sante.timer est installé"
  systemctl is-enabled sante.timer >/dev/null 2>&1 && ok "sante.timer est activé" \
    || ko "systemctl enable --now sante.timer"
  grep -q 'lab23/venv/bin/python\|/opt/.*venv/bin' /etc/systemd/system/sante.service 2>/dev/null \
    && ok "sante.service lance le python du venv" \
    || ko "ExecStart doit appeler l'interpréteur du venv par chemin absolu"
else note "sante.timer absent : la partie systemd n'est pas vérifiée"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
