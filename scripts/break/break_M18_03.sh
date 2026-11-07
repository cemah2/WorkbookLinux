#!/usr/bin/env bash
# break_M18_03.sh — panne BF18.3 (certificat TLS expiré)
# À lancer sur lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

command -v openssl >/dev/null 2>&1 || {
  echo "openssl est requis" >&2; exit 1; }
command -v nginx >/dev/null 2>&1 || {
  echo "nginx est requis (lab L18.4 à faire d'abord)" >&2; exit 1; }

SAUV=/root/.breakfix-backup
TRAV="$SAUV/M18_03"
mkdir -p "$TRAV/newcerts"

# --- où nginx prend-il son certificat ? --------------------------------
CRT=$(nginx -T 2>/dev/null | awk '/^\s*ssl_certificate\s/{print $2}' \
      | tr -d ';' | head -1)
KEY=$(nginx -T 2>/dev/null | awk '/^\s*ssl_certificate_key\s/{print $2}' \
      | tr -d ';' | head -1)
CRT=${CRT:-/etc/ssl/certs/app.crt}
KEY=${KEY:-/etc/ssl/private/app.key}

[ -f "$KEY" ] || {
  echo "clé serveur introuvable ($KEY) : fais d'abord le lab L18.4" >&2
  exit 1; }

# --- sauvegarde de l'état avant de casser ------------------------------
[ -f "$SAUV/M18_03.crt.orig" ] && [ -f "$SAUV/M18_03.chemins" ] || {
  [ -f "$CRT" ] && cp -a "$CRT" "$SAUV/M18_03.crt.orig"
  printf '%s\n%s\n' "$CRT" "$KEY" > "$SAUV/M18_03.chemins"; }

# --- une autorité de circonstance, créée une seule fois ---------------
if [ ! -f "$TRAV/ca.key" ]; then
  openssl genrsa -out "$TRAV/ca.key" 2048 2>/dev/null
  chmod 600 "$TRAV/ca.key"
  openssl req -x509 -new -key "$TRAV/ca.key" -sha256 -days 3650 \
    -subj "/C=FR/O=Lab Ops/CN=Lab Ops CA" -out "$TRAV/ca.crt" \
    2>/dev/null
  : > "$TRAV/index.txt"
  echo 1000 > "$TRAV/serial"
  cat > "$TRAV/openssl.cnf" <<EOF
[ ca ]
default_ca = CA_lab
[ CA_lab ]
dir              = $TRAV
database         = \$dir/index.txt
new_certs_dir    = \$dir/newcerts
serial           = \$dir/serial
certificate      = \$dir/ca.crt
private_key      = \$dir/ca.key
default_md       = sha256
policy           = pol
unique_subject   = no
[ pol ]
commonName             = supplied
countryName            = optional
organizationName       = optional
organizationalUnitName = optional
stateOrProvinceName    = optional
[ ext_srv ]
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = DNS:app.lab.local, DNS:lab-web.lab.local, \
IP:10.10.10.11
EOF
fi

# --- un certificat pour la clé existante, périmé depuis 10 jours ------
DEBUT=$(date -u -d '-2 years'  +%Y%m%d%H%M%SZ)
FIN=$(date   -u -d '-10 days'  +%Y%m%d%H%M%SZ)

openssl req -new -key "$KEY" -out "$TRAV/app.csr" \
  -subj "/C=FR/O=Lab Local/CN=app.lab.local" 2>/dev/null

openssl ca -batch -config "$TRAV/openssl.cnf" -in "$TRAV/app.csr" \
  -out "$TRAV/app-expire.crt" -startdate "$DEBUT" -enddate "$FIN" \
  -extensions ext_srv 2>/dev/null

install -o root -g root -m 0644 "$TRAV/app-expire.crt" "$CRT"

# --- le CA de circonstance est ajouté au magasin local ----------------
# (sinon le message serait « issuer inconnu » et non « expiré »). Nom de
# fichier DISTINCT : le CA de l'apprenant (lab-local-ca.crt) doit rester
# de confiance, sinon le correctif attendu (réémission) échouerait ici.
if [ -d /usr/local/share/ca-certificates ]; then
  install -m 0644 "$TRAV/ca.crt" \
    /usr/local/share/ca-certificates/lab18-ops-ca.crt
  update-ca-certificates >/dev/null 2>&1 || true
elif [ -d /etc/pki/ca-trust/source/anchors ]; then
  install -m 0644 "$TRAV/ca.crt" \
    /etc/pki/ca-trust/source/anchors/lab18-ops-ca.crt
  update-ca-trust extract >/dev/null 2>&1 || true
fi

nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : sur lab-web, « curl https://app.lab.local » échoue
avec « SSL certificate problem: certificate has expired » ; depuis
lab-adm, la même commande échoue aussi. Le navigateur affiche un
avertissement plein écran.
nginx est démarré et vert, le port 443 écoute, la configuration n'a pas
été modifiée.
EOF
