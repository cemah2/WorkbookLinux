#!/usr/bin/env bash
# check_PA_05.sh — vérifie le jalon PA.5 (nginx TLS, PKI, en-têtes, logs)
# À lancer sur lab-web (serveur) puis sur lab-adm (client, CA de confiance).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.5 sur $HOST =="
FQDN=factura.lab.local

case "$HOST" in
lab-web)
  [ "$(systemctl is-active nginx)" = active ] && ok "nginx actif" \
    || ko "nginx inactif"
  sudo -n nginx -t >/dev/null 2>&1 && ok "nginx -t : configuration valide" \
    || note "nginx -t non exécutable ici (sudo -n) : vérifie à la main"
  ss -Hltn 'sport = :443' | grep -q . && ok "443 en écoute" \
    || ko "rien n'écoute sur 443"
  ss -Hltn 'sport = :80'  | grep -q . && ok "80 en écoute (redirection)" \
    || ko "rien n'écoute sur 80"

  C="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' \
       -H "Host: $FQDN" http://127.0.0.1/)"
  case "$C" in
    "301 https://$FQDN/"*) ok "HTTP -> 301 vers https://$FQDN/" ;;
    *) ko "HTTP répond « $C » : on attend 301 vers https://$FQDN/" ;;
  esac

  H="$(curl -sk -D - -o /dev/null --resolve "$FQDN:443:127.0.0.1" \
       "https://$FQDN/")"
  echo "$H" | head -n1 | grep -q ' 200' && ok "https://$FQDN/ -> 200" \
    || ko "https://$FQDN/ ne répond pas 200 : $(echo "$H" | head -n1)"
  for hdr in 'strict-transport-security' 'x-content-type-options: nosniff' \
             'x-frame-options' 'referrer-policy' 'content-security-policy'; do
    echo "$H" | grep -qi "^$hdr" && ok "en-tête $hdr présent" \
      || ko "en-tête $hdr absent"
  done
  echo "$H" | grep -qi '^server: nginx/' \
    && ko "l'en-tête Server dévoile la version (server_tokens off)" \
    || ok "server_tokens off"

  B="$(curl -sk --resolve "$FQDN:443:127.0.0.1" "https://$FQDN/api/health")"
  echo "$B" | grep -q '"status"' && ok "/api/health passe par le proxy" \
    || ko "/api/health ne renvoie pas le JSON de l'API ($B)"
  M="$(curl -sk -o /dev/null -w '%{http_code}' \
       --resolve "$FQDN:443:127.0.0.1" "https://$FQDN/api/metrics")"
  [ "$M" = 403 ] && ok "/api/metrics refusé (403) hors de lab-ops" \
    || ko "/api/metrics répond $M depuis 127.0.0.1 : allow 10.10.10.14 ; \
deny all"
  T="$(curl -sk -o /dev/null -w '%{content_type}' \
       --resolve "$FQDN:443:127.0.0.1" "https://$FQDN/app.js")"
  echo "$T" | grep -q 'javascript' && ok "statiques servis (app.js)" \
    || ko "/app.js n'est pas servi en javascript ($T) : root /srv/factura/www"

  # --- TLS ----------------------------------------------------------------
  CERT="$(openssl s_client -connect 127.0.0.1:443 -servername "$FQDN" \
          </dev/null 2>/dev/null | openssl x509 2>/dev/null)"
  if [ -n "$CERT" ]; then
    echo "$CERT" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
      | grep -q "DNS:$FQDN" && ok "SAN contient DNS:$FQDN" \
      || ko "le certificat n'a pas DNS:$FQDN dans subjectAltName"
    echo "$CERT" | openssl x509 -noout -checkend 2592000 >/dev/null \
      && ok "certificat valable plus de 30 jours" \
      || ko "certificat expiré ou expirant sous 30 jours"
    ISS="$(echo "$CERT" | openssl x509 -noout -issuer)"
    SUB="$(echo "$CERT" | openssl x509 -noout -subject)"
    [ "${ISS#issuer=}" != "${SUB#subject=}" ] \
      && ok "certificat signé par une CA (pas auto-signé)" \
      || ko "certificat auto-signé : il doit être émis par ta CA de lab"
  else
    ko "impossible de lire le certificat servi sur 443"
  fi
  # SECLEVEL=0 : sinon le client OpenSSL d'Ubuntu refuse lui-même TLS 1.1
  openssl s_client -connect 127.0.0.1:443 -tls1_1 \
    -cipher 'DEFAULT:@SECLEVEL=0' </dev/null >/dev/null 2>&1 \
    && ko "TLS 1.1 accepté : ssl_protocols TLSv1.2 TLSv1.3" \
    || ok "TLS 1.1 refusé"
  openssl s_client -connect 127.0.0.1:443 -tls1_3 -servername "$FQDN" \
    </dev/null 2>/dev/null | grep -q 'TLSv1.3' && ok "TLS 1.3 négocié" \
    || ko "TLS 1.3 non négociable"

  for k in /etc/nginx/ssl/*.key /etc/ssl/private/factura*.key; do
    [ -e "$k" ] || continue
    P="$(sudo -n stat -c '%a' "$k" 2>/dev/null || stat -c '%a' "$k")"
    case "$P" in 600|640|400|440) ok "clé $k en $P" ;;
      *) ko "clé $k en $P : 0640 root:root maximum" ;; esac
  done

  # --- journaux ----------------------------------------------------------
  { [ -f /var/log/nginx/factura.access.log ] || sudo -n test -f \
    /var/log/nginx/factura.access.log 2>/dev/null; } \
    && ok "/var/log/nginx/factura.access.log présent" \
    || ko "journal d'accès dédié /var/log/nginx/factura.access.log absent"
  sudo -n grep -q 'request_time\|rt=' /var/log/nginx/factura.access.log \
    2>/dev/null && ok "le format de log inclut le temps de réponse" \
    || note "temps de réponse non trouvé dans le journal (log_format ?)"

  # --- pare-feu ----------------------------------------------------------
  S="$(sudo -n ufw status 2>/dev/null || ufw status 2>/dev/null)"
  echo "$S" | grep -q 'Status: active' && ok "ufw actif" || ko "ufw inactif"
  echo "$S" | grep -Eq '^443(/tcp)? ' && ok "ufw : 443 ouvert" \
    || ko "ufw : 443 non ouvert"
  echo "$S" | grep -Eq '^8000' \
    && ko "ufw : 8000 ne doit pas être ouvert" || ok "ufw : 8000 fermé"
  ;;

lab-adm)
  HOME_U="$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)"
  PKI="$HOME_U/P1/pki"
  [ -f "$PKI/ca.crt" ] && ok "CA de lab : $PKI/ca.crt" \
    || ko "$PKI/ca.crt absent"
  if [ -f "$PKI/ca.key" ]; then
    [ "$(stat -c '%a' "$PKI/ca.key")" = 600 ] && ok "ca.key en 0600" \
      || ko "ca.key doit être en 0600"
  else
    ko "$PKI/ca.key absent"
  fi
  ls /usr/local/share/ca-certificates/*.crt >/dev/null 2>&1 \
    && ok "CA installée dans /usr/local/share/ca-certificates" \
    || ko "CA non installée (update-ca-certificates)"
  C="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$FQDN/")"
  [ "$C" = 200 ] && ok "curl https://$FQDN/ -> 200 sans -k (CA reconnue)" \
    || ko "curl https://$FQDN/ -> « $C » (CA non reconnue ? /etc/hosts ? \
pare-feu ?)"
  curl -s --max-time 5 "https://$FQDN/api/health" | grep -q '"status"' \
    && ok "/api/health accessible depuis lab-adm" \
    || ko "/api/health inaccessible depuis lab-adm"
  timeout 3 bash -c 'exec 3<>/dev/tcp/10.10.10.11/8000' 2>/dev/null \
    && ko "8000 de lab-web joignable depuis lab-adm : gunicorn exposé" \
    || ok "8000 de lab-web injoignable depuis lab-adm"
  ;;
*) note "ce jalon se vérifie sur lab-web puis sur lab-adm" ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
