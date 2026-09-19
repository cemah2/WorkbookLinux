#!/usr/bin/env bash
# check_M27_05.sh — vérifie le lab L27.5 (exporter Prometheus)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L27.5 =="

S="$HOME/lab27/bin/factura_exporter.py"
PY="$HOME/lab27/venv/bin/python"; [ -x "$PY" ] || PY=python3
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; [ "${EXP_PID:-0}" -gt 0 ] && kill "$EXP_PID" 2>/dev/null' EXIT
PORT=19105

[ -f "$S" ] || { ko "$S est absent"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
ok "le script existe"

printf 'id;client;montant;statut;date\n1;A;100.00;payee;2026-09-01\n2;B;50.50;payee;2026-09-02\n3;C;10;emise;2026-09-03\n' \
  > "$TMP/f.csv"
printf '[http]\nport = %s\n[source]\ncsv = "%s"\n' "$PORT" "$TMP/f.csv" > "$TMP/e.toml"

"$PY" "$S" -c "$TMP/e.toml" > "$TMP/srv.out" 2>&1 &
EXP_PID=$!
sleep 1.5
kill -0 "$EXP_PID" 2>/dev/null && ok "l'exporter tourne" \
  || { ko "l'exporter s'est arrêté : $(tail -1 "$TMP/srv.out")"; exit 1; }

curl -s -o "$TMP/m" -w '%{http_code}' "http://127.0.0.1:$PORT/metrics" > "$TMP/code"
[ "$(cat "$TMP/code")" = 200 ] && ok "GET /metrics -> 200" || ko "/metrics doit répondre 200"
grep -q '^# TYPE factura_factures_total gauge' "$TMP/m" \
  && ok "# TYPE factura_factures_total gauge" || ko "ligne « # TYPE factura_factures_total gauge » attendue"
grep -Eq '^factura_factures_total\{statut="payee"\} 2(\.0)?$' "$TMP/m" \
  && ok 'factura_factures_total{statut="payee"} 2' || ko 'attendu : factura_factures_total{statut="payee"} 2'
grep -Eq '^factura_montant_euros\{statut="payee"\} 150\.5' "$TMP/m" \
  && ok 'factura_montant_euros{statut="payee"} 150.50' || ko 'attendu : montant payee = 150.50'
c=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/autre")
[ "$c" = 404 ] && ok "autre chemin -> 404" || ko "un chemin autre que /metrics doit répondre 404"

# fraîcheur : la source change, la valeur suit au scrape suivant
printf '4;D;1;payee;2026-09-04\n' >> "$TMP/f.csv"
curl -s "http://127.0.0.1:$PORT/metrics" | grep -Eq 'payee"\} 3' \
  && ok "les valeurs sont lues à chaque scrape" || ko "la source a changé mais pas la métrique (cache ?)"

kill -TERM "$EXP_PID"; sleep 1
kill -0 "$EXP_PID" 2>/dev/null && ko "SIGTERM n'arrête pas l'exporter" || ok "SIGTERM arrête proprement"
EXP_PID=0

if [ -f /etc/systemd/system/factura-exporter.service ]; then
  ok "unité factura-exporter.service présente"
  systemctl is-active factura-exporter.service >/dev/null 2>&1 \
    && ok "le service est actif" || note "le service n'est pas actif"
else note "pas d'unité systemd : partie déploiement non vérifiée"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
