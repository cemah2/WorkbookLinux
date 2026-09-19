#!/usr/bin/env bash
# check_PC_1_3.sh — vérifie le ticket PC.1.3 (vhost docs.factura.lab.local)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.1.3 =="
SAUV=/root/.breakfix-backup; ID=PC_1_3
H=docs.factura.lab.local
R="--resolve $H:443:127.0.0.1 --resolve $H:80:127.0.0.1"

# 1. HTTPS sert la documentation
CODE=$(curl -s -o /dev/null -w '%{http_code}' $R "https://$H/")
[ "$CODE" = "200" ] && ok "https://$H/ répond 200" \
  || ko "https://$H/ répond « $CODE » (vhost, server_name, droits ?)"
curl -s $R "https://$H/" | grep -q 'Documentation Factura' \
  && ok "le contenu de /srv/www/docs est servi" \
  || ko "la page servie n'est pas celle de /srv/www/docs"
CODE=$(curl -s -o /dev/null -w '%{http_code}' $R "https://$H/api/")
[ "$CODE" = "200" ] && ok "sous-répertoire /api/ accessible" \
  || ko "https://$H/api/ répond « $CODE » (droits sur les sous-répertoires ?)"

# 2. HTTP redirige vers HTTPS
LOC=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' $R "http://$H/")
case "$LOC" in
  30[18]\ https://$H/*) ok "HTTP redirige vers HTTPS ($LOC)" ;;
  *) ko "http://$H/ ne redirige pas en 301/308 vers https://$H/ ($LOC)" ;;
esac

# 3. le site principal n'a pas été cassé
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version)
[ "$CODE" = "200" ] && ok "factura.lab.local toujours en service" \
  || ko "factura.lab.local répond « $CODE » : régression sur le vhost principal"

# 4. le certificat couvre le nouveau nom
echo | openssl s_client -connect 127.0.0.1:443 -servername "$H" 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -q "$H" \
  && ok "le certificat présenté couvre $H" \
  || ko "le certificat présenté pour $H ne le contient pas dans son SAN"

# 5. droits sains sur la livraison (lisible par nginx, pas 777)
if [ "$(id -u)" -eq 0 ]; then
  W=$(find /srv/www/docs -perm -o+w 2>/dev/null | wc -l)
  [ "$W" -eq 0 ] && ok "aucun fichier world-writable dans /srv/www/docs" \
    || ko "$W fichier(s) modifiables par tous dans /srv/www/docs"
fi
nginx -t >/dev/null 2>&1 && ok "nginx -t : configuration valide" \
  || ko "nginx -t échoue"

if [ -r "$SAUV/$ID.debut" ]; then
  note "temps écoulé : $(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
