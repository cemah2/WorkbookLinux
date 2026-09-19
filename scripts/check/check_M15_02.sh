#!/usr/bin/env bash
# check_M15_02.sh — vérifie le lab L15.2 (HTTPS et diagnostic) sur lab-web
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L15.2 =="
H=factura-demo.lab.local
SUDO=""; sudo -n true 2>/dev/null && SUDO="sudo -n"
R=(-k --resolve "$H:443:127.0.0.1" --resolve "$H:80:127.0.0.1")
C() { curl -s --max-time 10 "${R[@]}" "$@"; }

ss -Hltn 'sport = :443' | grep -q 443 && ok "nginx écoute sur 443" \
  || { ko "rien n'écoute sur 443 (listen 443 ssl)"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- TLS ---------------------------------------------------------------
S="$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$H" 2>/dev/null)"
grep -qE 'Protocol *: *TLSv1\.[23]' <<<"$S" && ok "TLS 1.2/1.3 négocié" \
  || ko "protocole TLS inattendu (ssl_protocols TLSv1.2 TLSv1.3)"
grep -q "$H" <<<"$S" && ok "certificat pour $H présenté" \
  || ko "le certificat présenté ne mentionne pas $H (SNI, server_name, SAN)"
if echo | openssl s_client -connect 127.0.0.1:443 -servername "$H" -tls1_1 \
     >/dev/null 2>&1; then ko "TLS 1.1 accepté"; else ok "TLS 1.1 refusé"; fi
V="$(C --http2 -o /dev/null -w '%{http_version}' "https://$H/")"
[ "$V" = 2 ] && ok "HTTP/2 actif" || ko "pas de HTTP/2 (obtenu HTTP/$V ; listen 443 ssl http2)"

# --- en-têtes ----------------------------------------------------------
for u in / /api/health; do
  HD="$(C -D - -o /dev/null "https://$H$u")"
  grep -qi '^strict-transport-security:' <<<"$HD" && ok "HSTS sur $u" \
    || ko "HSTS absent sur $u (add_header ... always ; héritage non additif)"
  grep -qi '^x-content-type-options: nosniff' <<<"$HD" \
    && ok "X-Content-Type-Options sur $u" || ko "X-Content-Type-Options absent sur $u"
done
HD="$(C -D - -o /dev/null "https://$H/")"
grep -qi '^x-frame-options:' <<<"$HD" && ok "X-Frame-Options présent" \
  || ko "X-Frame-Options absent"

# --- redirection 80 -> 443 ----------------------------------------------
HP="$(C -D - -o /dev/null "http://$H/page?x=1")"
grep -q ' 301' <<<"$HP" && grep -qi "^location: https://$H/page?x=1" <<<"$HP" \
  && ok "http -> 301 vers https (URI conservée)" \
  || ko "pas de 301 http->https avec \$request_uri (return 301 https://\$host\$request_uri)"
[ "$(C -o /dev/null -w '%{http_code}' "http://$H/.well-known/acme-challenge/test")" != 301 ] \
  && ok "/.well-known/acme-challenge/ n'est pas redirigé" \
  || ko "/.well-known/acme-challenge/ est redirigé (location ^~ dans le server 80)"
N="$(C -L --max-redirs 5 -o /dev/null -w '%{num_redirects}' "http://$H/")"
[ "$N" -le 1 ] && ok "aucune boucle de redirection" || ko "boucle : $N redirections"

# --- clé privée --------------------------------------------------------
K="$($SUDO nginx -T 2>/dev/null | grep -m1 ssl_certificate_key | awk '{print $2}' | tr -d ';')"
if [ -n "$K" ]; then
  M="$($SUDO stat -c '%a %U' "$K" 2>/dev/null)"
  [ "$M" = "600 root" ] && ok "clé privée $K en 0600 root" \
    || ko "clé privée $K : $M (attendu 0600 root)"
else
  ko "ssl_certificate_key introuvable dans la conf"
fi

# --- rapport de diagnostic ---------------------------------------------
RAP="$HOME/lab15/rapports/codes-http.md"
if [ -f "$RAP" ]; then
  ok "rapport codes-http.md présent"
  for c in 502 504 413 403 301 404; do
    grep -q "$c" "$RAP" && ok "cas $c documenté" || ko "cas $c absent du rapport"
  done
  grep -qiE 'connect\(\) failed|timed out|too large body|forbidden|Permission denied' "$RAP" \
    && ok "lignes d'error.log citées" || ko "aucune ligne d'error.log citée dans le rapport"
else
  ko "rapport $RAP absent"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
