#!/usr/bin/env bash
# check_PC_1_1.sh — vérifie le ticket PC.1.1 (certificat expiré)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.1.1 =="
SAUV=/root/.breakfix-backup; ID=PC_1_1
CRT=/etc/ssl/factura/factura.lab.local.crt
KEY=/etc/ssl/factura/factura.lab.local.key

# 1. le certificat servi par nginx
SERVI=$(echo | openssl s_client -connect 127.0.0.1:443 \
  -servername factura.lab.local 2>/dev/null | openssl x509 2>/dev/null)
if [ -z "$SERVI" ]; then
  ko "rien en HTTPS sur :443 (nginx actif ? ss -tlnp | grep 443)"
else
  ok "nginx sert un certificat sur :443"
  if echo "$SERVI" | openssl x509 -noout -checkend 604800 >/dev/null; then
    ok "le certificat servi est valide plus de 7 jours"
  else
    ko "le certificat SERVI expire dans moins de 7 jours (reload fait ?)"
  fi
  echo "$SERVI" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
    | grep -q 'factura.lab.local' \
    && ok "le SAN contient factura.lab.local" \
    || ko "le certificat servi ne couvre pas factura.lab.local (SAN)"
  ISS=$(echo "$SERVI" | openssl x509 -noout -issuer)
  case "$ISS" in
    *"Factura Lab CA"*) ok "émis par la CA de lab (chaîne de confiance)" ;;
    *) ko "émetteur inattendu : $ISS (un auto-signé casse la confiance)" ;;
  esac
fi

# 2. cohérence clé / certificat sur disque
if [ -r "$CRT" ] && [ -r "$KEY" ]; then
  A=$(openssl x509 -in "$CRT" -noout -pubkey 2>/dev/null | md5sum)
  B=$(openssl pkey -in "$KEY" -pubout 2>/dev/null | md5sum)
  [ "$A" = "$B" ] && ok "clé et certificat correspondent" \
    || ko "la clé $KEY ne correspond pas au certificat"
else
  note "clé non lisible (lance avec sudo pour ce test)"
fi

# 3. bout en bout
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version)
[ "$CODE" = "200" ] && ok "curl HTTPS sans -k : 200" \
  || ko "curl https://factura.lab.local renvoie « $CODE » (validation TLS)"

# 4. prévention : une surveillance de l'expiration existe-t-elle ?
TROUVE=0
for g in '/etc/cron.d/*cert*' '/etc/systemd/system/*cert*.timer' \
         '/usr/local/bin/*cert*' '/usr/local/sbin/*cert*'; do
  compgen -G "$g" >/dev/null && TROUVE=1
done
if [ "$TROUVE" -eq 1 ]; then
  ok "un mécanisme de surveillance/renouvellement du certificat existe"
else
  ko "aucune surveillance de l'expiration (timer, cron ou script attendu)"
fi

# 5. discipline
if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement (interdit)"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
