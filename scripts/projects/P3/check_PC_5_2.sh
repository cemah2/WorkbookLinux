#!/usr/bin/env bash
# check_PC_5_2.sh — vérifie le ticket PC.5.2 (mise à jour qui remplace la conf)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.5.2 =="
SAUV=/root/.breakfix-backup; ID=PC_5_2
R="--resolve factura.lab.local:443:127.0.0.1"

# 1. le site répond de nouveau en HTTPS
CODE=$(curl -s -o /dev/null -w '%{http_code}' $R https://factura.lab.local/version)
[ "$CODE" = "200" ] && ok "https://factura.lab.local répond 200" \
  || ko "le site HTTPS renvoie « $CODE » (vhost TLS rétabli ?)"

# 2. ce n'est plus la page par défaut sur 80
if curl -s http://127.0.0.1/ | grep -qi 'Welcome to nginx'; then
  ko "la page par défaut « Welcome to nginx » est encore servie sur :80"
else
  ok "la page nginx par défaut n'est plus servie"
fi

# 3. le vhost applicatif est de nouveau actif et valide
nginx -t >/dev/null 2>&1 && ok "nginx -t : configuration valide" \
  || ko "nginx -t échoue"
if grep -qs 'proxy_pass' /etc/nginx/sites-available/factura.conf 2>/dev/null \
   && grep -qs 'ssl_certificate' /etc/nginx/sites-available/factura.conf; then
  ok "le vhost Factura (TLS + proxy) est restauré"
else
  ko "le vhost Factura restauré ne contient pas TLS + proxy_pass"
fi

# 4. le .dpkg-old a été traité (pas laissé traîner comme conf active)
if ls /etc/nginx/sites-enabled/*.dpkg-old >/dev/null 2>&1; then
  ko "un fichier .dpkg-old est activé dans sites-enabled (à retirer)"
else
  ok "aucun .dpkg-old actif dans sites-enabled"
fi

# 5. prévention : conf sous gestion (git) ou marquée pour dpkg
if [ -d /etc/nginx/.git ] || grep -rqs 'factura.conf' /etc/apt/apt.conf.d/ 2>/dev/null \
   || [ -f /etc/factura/.conf-versionnee ]; then
  ok "une trace de versionnage/protection de la conf existe"
else
  note "pense à versionner /etc/nginx (git) pour détecter ce genre d'écrasement"
  ok "site rétabli (prévention à documenter dans le ticket)"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
