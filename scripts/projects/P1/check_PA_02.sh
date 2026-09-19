#!/usr/bin/env bash
# check_PA_02.sh — vérifie le jalon PA.2 (PostgreSQL, Redis, réseau, pare-feu)
# À lancer sur lab-db (tests principaux) puis sur lab-web (accès distant).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.2 sur $HOST =="

tcp_open() {  # tcp_open <ip> <port> : vrai si la connexion s'établit
  timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

case "$HOST" in
lab-db)
  # --- stockage : les données PG sur un volume logique dédié -------------
  if findmnt -n -o SOURCE /var/lib/postgresql 2>/dev/null | grep -q mapper; then
    ok "/var/lib/postgresql est un point de montage LVM \
($(findmnt -n -o SOURCE /var/lib/postgresql))"
  else
    ko "/var/lib/postgresql n'est pas monté depuis un LV (lsblk, findmnt)"
  fi
  grep -qs '/var/lib/postgresql' /etc/fstab \
    && ok "montage déclaré dans /etc/fstab" \
    || ko "montage absent de /etc/fstab : il ne survivra pas au reboot"

  # --- PostgreSQL ---------------------------------------------------------
  U=postgresql@16-main.service
  [ "$(systemctl is-active $U 2>/dev/null)" = active ] \
    && ok "$U actif" || ko "$U inactif (systemctl status $U)"
  if ss -Hltn 'sport = :5432' | grep -q '10.10.10.12:5432'; then
    ok "PostgreSQL écoute sur 10.10.10.12:5432"
  else
    ko "PostgreSQL n'écoute pas sur 10.10.10.12 (listen_addresses, \
puis restart — un reload ne suffit pas)"
  fi
  ss -Hltn 'sport = :5432' | grep -q '0.0.0.0:5432' \
    && ko "PostgreSQL écoute sur toutes les interfaces : restreins \
listen_addresses" || ok "PostgreSQL n'écoute pas sur 0.0.0.0"

  if command -v psql >/dev/null && [ -x "$(command -v sudo)" ]; then
    Q() { sudo -n -u postgres psql -tAc "$1" 2>/dev/null; }
    [ "$(Q "SELECT 1 FROM pg_database WHERE datname='factura'")" = 1 ] \
      && ok "base factura présente" || ko "base factura absente"
    [ "$(Q "SELECT 1 FROM pg_roles WHERE rolname='factura_app'")" = 1 ] \
      && ok "rôle factura_app présent" || ko "rôle factura_app absent"
    [ "$(Q "SELECT rolsuper FROM pg_roles WHERE rolname='factura_app'")" \
       = f ] && ok "factura_app n'est pas superuser" \
      || ko "factura_app est superuser (ou absent) : droits minimaux"
    [ "$(Q "SELECT rolcanlogin FROM pg_roles WHERE rolname='factura_app'")" \
       = t ] && ok "factura_app peut se connecter (LOGIN)" \
      || ko "factura_app n'a pas LOGIN"
    T="$(sudo -n -u postgres psql -d factura -tAc \
        "SELECT count(*) FROM invoices" 2>/dev/null)"
    if [ -n "$T" ]; then
      ok "table invoices présente ($T lignes)"
      [ "$T" -ge 5 ] && ok "données de démonstration chargées (seed.sql)" \
        || ko "moins de 5 factures : seed.sql n'a pas été joué"
    else
      ko "table invoices absente dans factura (schema.sql)"
    fi
    [ "$(sudo -n -u postgres psql -d factura -tAc \
       "SELECT 1 FROM pg_proc WHERE proname='next_invoice_number'" \
       2>/dev/null)" = 1 ] \
      && ok "fonction next_invoice_number() présente" \
      || ko "fonction next_invoice_number() absente (schema.sql complet ?)"
    ENC="$(Q "SHOW password_encryption")"
    [ "$ENC" = scram-sha-256 ] && ok "password_encryption = scram-sha-256" \
      || ko "password_encryption vaut « $ENC » : on veut scram-sha-256"
  else
    ko "psql ou sudo indisponible : impossible d'interroger PostgreSQL"
  fi

  HBA=/etc/postgresql/16/main/pg_hba.conf
  if [ -r "$HBA" ] || sudo -n test -r "$HBA" 2>/dev/null; then
    CAT() { sudo -n cat "$HBA" 2>/dev/null || cat "$HBA"; }
    CAT | grep -Ev '^\s*#|^\s*$' | grep -E '^host' \
      | grep -q '10\.10\.10\.11' \
      && ok "pg_hba : une règle host pour 10.10.10.11" \
      || ko "pg_hba : aucune règle host pour lab-web (10.10.10.11/32)"
    CAT | grep -Ev '^\s*#|^\s*$' | grep -E '^host' \
      | grep -Eq '\s(trust|password|md5)\s*$' \
      && ko "pg_hba : une règle host utilise trust/password/md5 : \
scram-sha-256 uniquement" \
      || ok "pg_hba : aucune règle host en trust/password/md5"
    CAT | grep -Ev '^\s*#|^\s*$' | grep -E '^host' \
      | grep -Eq '0\.0\.0\.0/0|::/0' \
      && ko "pg_hba : une règle ouvre le monde entier (0.0.0.0/0)" \
      || ok "pg_hba : pas de règle 0.0.0.0/0"
  else
    ko "pg_hba.conf illisible (lance ce check avec sudo)"
  fi

  # --- Redis ---------------------------------------------------------------
  [ "$(systemctl is-active redis-server.service 2>/dev/null)" = active ] \
    && ok "redis-server actif" || ko "redis-server inactif"
  if ss -Hltn 'sport = :6379' | grep -q '10.10.10.12:6379'; then
    ok "Redis écoute sur 10.10.10.12:6379"
  else
    ko "Redis n'écoute pas sur 10.10.10.12 (directive bind)"
  fi
  ss -Hltn 'sport = :6379' | grep -q '0.0.0.0:6379' \
    && ko "Redis écoute sur 0.0.0.0" || ok "Redis n'écoute pas sur 0.0.0.0"
  if command -v redis-cli >/dev/null; then
    R="$(redis-cli -h 10.10.10.12 ping 2>&1)"
    case "$R" in
      *NOAUTH*) ok "Redis exige une authentification (requirepass)" ;;
      PONG) ko "Redis répond PONG sans mot de passe : requirepass manquant" ;;
      *) ko "Redis injoignable sur 10.10.10.12 : $R" ;;
    esac
  fi

  # --- pare-feu ------------------------------------------------------------
  if command -v ufw >/dev/null; then
    S="$(sudo -n ufw status 2>/dev/null || ufw status 2>/dev/null)"
    echo "$S" | grep -q 'Status: active' && ok "ufw actif" \
      || ko "ufw inactif"
    echo "$S" | grep -E '5432' | grep -q '10.10.10.11' \
      && ok "ufw : 5432 autorisé depuis 10.10.10.11" \
      || ko "ufw : pas de règle 5432 sourcée sur 10.10.10.11"
    echo "$S" | grep -E '6379' | grep -q '10.10.10.11' \
      && ok "ufw : 6379 autorisé depuis 10.10.10.11" \
      || ko "ufw : pas de règle 6379 sourcée sur 10.10.10.11"
    echo "$S" | grep -E '5432|6379' | grep -q 'Anywhere *$' \
      && ko "ufw : 5432 ou 6379 ouvert à Anywhere" \
      || ok "ufw : 5432/6379 non ouverts à Anywhere"
    echo "$S" | grep -E '^22(/tcp)? ' | grep -q '10.10.10.10' \
      && ok "ufw : SSH restreint à lab-adm" \
      || note "ufw : SSH non restreint à 10.10.10.10 (recommandé)"
  else
    ko "ufw absent (apt install ufw)"
  fi
  ;;

lab-web)
  tcp_open 10.10.10.12 5432 && ok "5432 joignable depuis lab-web" \
    || ko "5432 injoignable depuis lab-web (ufw sur lab-db ? listen ?)"
  tcp_open 10.10.10.12 6379 && ok "6379 joignable depuis lab-web" \
    || ko "6379 injoignable depuis lab-web (ufw sur lab-db ? bind ?)"
  if command -v psql >/dev/null; then
    URL="$(sudo -n grep -h '^FACTURA_DB_URL=' /etc/factura/api.env \
           2>/dev/null | cut -d= -f2-)"
    if [ -n "$URL" ]; then
      psql "$URL" -tAc 'SELECT 1' 2>/dev/null | grep -q '^1$' \
        && ok "connexion applicative à la base OK (FACTURA_DB_URL)" \
        || ko "FACTURA_DB_URL de /etc/factura/api.env ne permet pas de se \
connecter (mot de passe, pg_hba, sslmode)"
    else
      note "/etc/factura/api.env pas encore écrit : test psql ignoré"
    fi
  else
    note "psql absent sur lab-web : installe postgresql-client pour tester"
  fi
  ;;

lab-adm|lab-ops)
  tcp_open 10.10.10.12 5432 \
    && ko "5432 de lab-db est joignable depuis $HOST : le pare-feu doit \
ne laisser passer que lab-web" \
    || ok "5432 de lab-db refusé depuis $HOST (attendu)"
  tcp_open 10.10.10.12 6379 \
    && ko "6379 de lab-db est joignable depuis $HOST" \
    || ok "6379 de lab-db refusé depuis $HOST (attendu)"
  ;;
*) note "hostname $HOST hors projet" ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
