#!/usr/bin/env bash
# check_M18_04.sh — vérifie le lab L18.4 (mini-PKI, HTTPS, surveillance)
# À lancer depuis lab-adm : le contrôle porte sur le service distant.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L18.4 =="

LAB_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
PKI="$LAB_HOME/lab18/pki"
CIBLE=${CIBLE:-app.lab.local}
IP=${IP:-10.10.10.11}

# --- 1. la PKI locale --------------------------------------------------
if [ -f "$PKI/ca.crt" ] && [ -f "$PKI/ca.key" ]; then
  ok "la CA existe dans $PKI"
  M=$(stat -c '%a' "$PKI/ca.key")
  [ "$M" = 600 ] || [ "$M" = 400 ] \
    && ok "la clé de la CA est en $M" \
    || ko "la clé de la CA est en $M : personne d'autre que son \
propriétaire ne doit pouvoir la lire (chmod 600)"
  openssl x509 -in "$PKI/ca.crt" -noout -checkend 0 >/dev/null 2>&1 \
    && ok "le certificat de la CA est valide" \
    || ko "le certificat de la CA est expiré"
else
  ko "pas de CA dans $PKI (étape 1)"
fi

if [ -f "$PKI/app.crt" ]; then
  openssl verify -CAfile "$PKI/ca.crt" "$PKI/app.crt" >/dev/null 2>&1 \
    && ok "le certificat serveur est bien signé par la CA" \
    || ko "openssl verify échoue : le certificat n'est pas signé par \
cette CA"
  SAN=$(openssl x509 -in "$PKI/app.crt" -noout -ext subjectAltName \
        2>/dev/null)
  grep -q "DNS:$CIBLE" <<<"$SAN" \
    && ok "le SAN contient DNS:$CIBLE" \
    || ko "le SAN ne couvre pas $CIBLE : les clients modernes ignorent \
le CN (voir Q18.16)"
  grep -q "IP Address:$IP" <<<"$SAN" \
    && ok "le SAN contient IP:$IP" \
    || note "le SAN ne contient pas l'IP : https://$IP échouera"
  # clé et certificat appariés
  if [ -f "$PKI/app.key" ]; then
    A=$(openssl x509 -in "$PKI/app.crt" -noout -modulus | openssl sha256)
    B=$(openssl rsa -in "$PKI/app.key" -noout -modulus 2>/dev/null \
        | openssl sha256)
    [ "$A" = "$B" ] \
      && ok "la clé privée correspond au certificat" \
      || ko "la clé et le certificat ne correspondent pas"
  fi
else
  ko "pas de certificat serveur dans $PKI (étape 2)"
fi

# --- 2. la confiance côté client --------------------------------------
if [ -f /usr/local/share/ca-certificates/lab-local-ca.crt ] \
   || [ -f /etc/pki/ca-trust/source/anchors/lab-local-ca.crt ]; then
  ok "le CA du lab est déposé dans le magasin système"
else
  ko "le CA n'est pas dans le magasin système (update-ca-certificates)"
fi
getent hosts "$CIBLE" >/dev/null 2>&1 \
  && ok "$CIBLE se résout" \
  || ko "$CIBLE ne se résout pas (ajoute-le à /etc/hosts)"

# --- 3. le service distant --------------------------------------------
H=$(curl -sI --max-time 6 "https://$CIBLE/" 2>/dev/null)
if [ -n "$H" ]; then
  ok "curl https://$CIBLE aboutit SANS -k (la chaîne est validée)"
else
  ko "curl https://$CIBLE échoue : $(curl -sI --max-time 6 \
"https://$CIBLE/" 2>&1 | head -1)"
fi

grep -qi '^strict-transport-security' <<<"$H" \
  && ok "l'en-tête HSTS est présent" \
  || ko "pas d'en-tête Strict-Transport-Security"

MA=$(grep -io 'max-age=[0-9]*' <<<"$H" | head -1 | cut -d= -f2)
[ "${MA:-0}" -ge 63072000 ] \
  && ok "max-age = $MA (>= 2 ans)" \
  || ko "max-age = ${MA:-absent}, l'énoncé demande au moins 63072000"

# redirection 80 -> 443
R=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 6 \
    "http://$CIBLE/" 2>/dev/null)
grep -qE '^30[18] https://' <<<"$R" \
  && ok "HTTP redirige en permanence vers HTTPS ($R)" \
  || ko "pas de redirection 301 de 80 vers 443 (obtenu : $R)"

# --- 4. ce que sert réellement le serveur ------------------------------
S=$(openssl s_client -connect "$IP:443" -servername "$CIBLE" \
    </dev/null 2>/dev/null)
grep -q 'Verify return code: 0 (ok)' <<<"$S" \
  && ok "openssl s_client : Verify return code 0 (ok)" \
  || ko "openssl s_client ne valide pas la chaîne : \
$(grep 'Verify return code' <<<"$S" | head -1)"

PROTO=$(grep -oE 'TLSv1\.[0-9]' <<<"$S" | head -1)
case "$PROTO" in
  TLSv1.2|TLSv1.3) ok "protocole négocié : $PROTO" ;;
  *) ko "protocole négocié : ${PROTO:-inconnu} — TLS 1.0/1.1 sont à \
proscrire" ;;
esac

printf '%s' "$S" | openssl x509 -noout -checkend 2592000 >/dev/null 2>&1 \
  && ok "le certificat servi n'expire pas dans les 30 jours" \
  || ko "le certificat servi expire sous 30 jours (ou est déjà expiré)"

# --- 5. le script de surveillance --------------------------------------
V="$LAB_HOME/lab18/bin/verif-certs.sh"
if [ -x "$V" ]; then
  ok "$V existe et est exécutable"
  OUT=$("$V" "$CIBLE:443" 2>/dev/null); RC=$?
  grep -qE '[0-9]+' <<<"$OUT" \
    && ok "le script produit une sortie exploitable" \
    || ko "le script ne renvoie rien d'utilisable"
  [ "$RC" -le 2 ] \
    && ok "code retour $RC conforme au contrat (0/1/2)" \
    || ko "code retour $RC hors contrat"
else
  ko "~/lab18/bin/verif-certs.sh absent ou non exécutable (étape 8)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
