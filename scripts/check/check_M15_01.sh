#!/usr/bin/env bash
# check_M15_01.sh — vérifie le lab L15.1 (vhost nginx complet) sur lab-web
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L15.1 =="

H=factura-demo.lab.local
SUDO=""; sudo -n true 2>/dev/null && SUDO="sudo -n"
C() { curl -s --max-time 10 "$@"; }
code() { C -o /dev/null -w '%{http_code}' "$@"; }

# --- 0. nginx et activation --------------------------------------------
if $SUDO nginx -t >/dev/null 2>&1; then ok "nginx -t : configuration valide"
else ko "nginx -t échoue (lis le message : fichier et ligne)"; fi
[ -e /etc/nginx/sites-enabled/factura-demo ] \
  && ok "site factura-demo activé" \
  || ko "sites-enabled/factura-demo absent (ln -s depuis sites-available)"
[ -e /etc/nginx/sites-enabled/default ] \
  && ko "le site default est encore activé" || ok "site default désactivé"

# --- base d'URL : https si 443 écoute, sinon http ------------------------
if ss -Hltn 'sport = :443' | grep -q 443; then
  B="https://$H"; R=(-k --resolve "$H:443:127.0.0.1")
else
  B="http://$H"; R=(--resolve "$H:80:127.0.0.1")
fi
note "test sur $B"

# --- 1. front SPA --------------------------------------------------------
[ "$(code "${R[@]}" "$B/")" = 200 ] && ok "/ répond 200" \
  || ko "/ ne répond pas 200 (root, index, try_files ?)"
[ "$(code "${R[@]}" "$B/route/inconnue")" = 200 ] \
  && ok "URI inconnue -> index.html (SPA)" \
  || ko "URI inconnue ne renvoie pas index.html (try_files ... /index.html)"
SRV="$(C "${R[@]}" -D - -o /dev/null "$B/" | grep -i '^server:' | tr -d '\r')"
grep -qiE '^server: nginx\s*$' <<<"$SRV" && ok "server_tokens off" \
  || ko "en-tête Server expose la version : $SRV (server_tokens off)"

# --- 2. static : cache et gzip -----------------------------------------
HD="$(C "${R[@]}" --compressed -D - -o /dev/null "$B/static/gros.txt")"
grep -qi 'content-encoding: gzip' <<<"$HD" && ok "gzip actif sur /static" \
  || ko "pas de gzip sur /static/gros.txt (gzip on ; gzip_types text/plain)"
grep -qiE 'cache-control: .*max-age=2592000' <<<"$HD" \
  && ok "cache 30 jours sur /static" \
  || ko "Cache-Control max-age=2592000 absent sur /static (expires 30d)"

# --- 3. docs protégées -------------------------------------------------
[ "$(code "${R[@]}" "$B/docs/")" = 401 ] && ok "/docs/ exige une auth (401)" \
  || ko "/docs/ ne répond pas 401 (auth_basic, auth_basic_user_file)"

# --- 4. upstream : deux instances, en-têtes ------------------------------
INST="$(for _ in 1 2 3 4 5 6; do C "${R[@]}" "$B/api/whoami" | jq -r .instance 2>/dev/null; done | sort -u | wc -l)"
[ "$INST" -ge 2 ] && ok "les deux instances répondent derrière /api/" \
  || ko "une seule instance vue sur 6 requêtes (upstream à deux server ?)"
W="$(C "${R[@]}" "$B/api/whoami")"
grep -q '"X-Forwarded-For"' <<<"$W" && ok "X-Forwarded-For transmis" \
  || ko "X-Forwarded-For absent côté backend (proxy_set_header)"
grep -q "\"Host\": \"$H\"" <<<"$W" && ok "Host transmis = $H" \
  || ko "Host reçu par le backend n'est pas $H (proxy_set_header Host \$host)"
grep -q '"http_version": "HTTP/1.1"' <<<"$W" \
  && ok "HTTP/1.1 vers l'upstream" \
  || ko "l'upstream reçoit du HTTP/1.0 (proxy_http_version 1.1 + keepalive)"

# --- 5. limit_req ------------------------------------------------------
N429="$(for _ in $(seq 12); do code "${R[@]}" "$B/api/login"; echo; done | grep -c '^429$')"
[ "$N429" -ge 3 ] && ok "limit_req sur /api/login : $N429 x 429 sur 12" \
  || ko "pas (assez) de 429 sur /api/login : $N429 (limit_req, limit_req_status 429)"

# --- 6. allow/deny -----------------------------------------------------
[ "$(code "${R[@]}" "$B/api/metrics")" = 403 ] \
  && ok "/api/metrics refusé depuis 127.0.0.1 (403)" \
  || ko "/api/metrics accessible depuis 127.0.0.1 (allow 10.10.10.14; deny all)"

# --- 7. stream ---------------------------------------------------------
L="$(C "${R[@]}" -N --max-time 3 "$B/api/stream" 2>/dev/null | wc -l)"
[ "$L" -ge 1 ] && [ "$L" -le 8 ] \
  && ok "/api/stream arrive au fil de l'eau ($L lignes en 3 s)" \
  || ko "/api/stream est mis en tampon ($L lignes en 3 s ; proxy_buffering off)"

# --- 8. taille de corps ------------------------------------------------
T3="$(mktemp)"; head -c 3145728 /dev/zero > "$T3"
T1="$(mktemp)"; head -c 1048576 /dev/zero > "$T1"
[ "$(code "${R[@]}" -X POST --data-binary @"$T3" "$B/api/upload")" = 413 ] \
  && ok "POST 3 Mo -> 413" || ko "POST 3 Mo n'est pas refusé en 413 (client_max_body_size 2m)"
[ "$(code "${R[@]}" -X POST --data-binary @"$T1" "$B/api/upload")" = 200 ] \
  && ok "POST 1 Mo -> 200" || ko "POST 1 Mo refusé (client_max_body_size trop bas)"
rm -f "$T3" "$T1"

# --- 9. journal --------------------------------------------------------
LOG=/var/log/nginx/factura.access.log
if $SUDO test -s "$LOG" 2>/dev/null; then
  LAST="$($SUDO tail -1 "$LOG")"
  grep -q 'rt=' <<<"$LAST" && grep -q 'ua=' <<<"$LAST" \
    && ok "log_format avec rt= et ua=" \
    || ko "$LOG ne contient pas rt=/ua= (log_format factura)"
else
  ko "$LOG absent ou vide (access_log dédié au vhost)"
fi

# --- 10. maintenance ---------------------------------------------------
if [ -n "$SUDO" ]; then
  $SUDO touch /srv/www/maintenance.on
  M="$(code "${R[@]}" "$B/")"; HM="$(code "${R[@]}" "$B/api/health")"
  $SUDO rm -f /srv/www/maintenance.on
  [ "$M" = 503 ] && ok "maintenance.on -> 503 sur /" \
    || ko "maintenance.on ne bascule pas / en 503 (obtenu $M)"
  [ "$HM" = 200 ] && ok "/api/health reste 200 en maintenance" \
    || ko "/api/health est touché par la maintenance (obtenu $HM)"
  [ "$(code "${R[@]}" "$B/")" = 200 ] && ok "retour à la normale sans reload" \
    || ko "le site ne revient pas après suppression du fichier"
else
  note "sudo indisponible : test de maintenance sauté"
fi

# --- 11. rapport -------------------------------------------------------
RAP="$HOME/lab15/rapports/web-412.md"
[ -f "$RAP" ] && [ "$(wc -l < "$RAP")" -ge 20 ] \
  && ok "rapport web-412.md présent" || ko "rapport $RAP absent ou trop court"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
