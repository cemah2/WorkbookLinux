#!/usr/bin/env bash
# check_PC_5_1.sh — vérifie le ticket PC.5.1 (compte lecture seule prestataire)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.5.1 =="
SAUV=/root/.breakfix-backup; ID=PC_5_1
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
q()  { sudo -u postgres psql -tAqc "$1" 2>/dev/null; }
qd() { sudo -u postgres psql -tAqd factura -c "$1" 2>/dev/null; }

# on cherche un rôle dédié au prestataire (nom contenant revizor/audit/lecture)
ROLE=$(q "select rolname from pg_roles where rolname ~* \
'revizor|audit|lecture|readonly|ro_'" | head -1)
if [ -z "$ROLE" ]; then
  ko "aucun rôle d'audit/lecture trouvé (create role ... login)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "rôle prestataire trouvé : $ROLE"

# 1. pas de superutilisateur ni de création
ATTR=$(q "select rolsuper||' '||rolcreatedb||' '||rolcreaterole \
from pg_roles where rolname='$ROLE'")
[ "$ATTR" = "f f f" ] && ok "aucun privilège d'administration ($ATTR)" \
  || ko "le rôle a des attributs d'admin (super/createdb/createrole = $ATTR)"

# 2. il peut lire
if qd "grant usage on schema public to \"$ROLE\"" >/dev/null 2>&1; then :; fi
SEL=$(sudo -u postgres psql -tAqd factura -c \
  "set role \"$ROLE\"; select count(*) from factures" 2>&1)
echo "$SEL" | grep -qE '^[0-9]+$' && ok "le rôle peut lire la table factures" \
  || ko "le rôle ne peut pas lire factures : $SEL"

# 3. il ne peut PAS écrire
INS=$(sudo -u postgres psql -tAqd factura -c \
  "set role \"$ROLE\"; insert into factures(client_id,montant) values(1,1)" 2>&1)
echo "$INS" | grep -qi 'permission denied' \
  && ok "écriture refusée (permission denied) : lecture seule respectée" \
  || ko "le rôle a pu écrire (ou autre erreur) : $INS"

# 4. limites de sûreté : mot de passe, expiration, connexions bornées
VU=$(q "select rolvaliduntil from pg_roles where rolname='$ROLE'")
[ -n "$VU" ] && [ "$VU" != "infinity" ] \
  && ok "le compte expire ($VU)" \
  || ko "le compte n'a pas de date d'expiration (VALID UNTIL)"
CL=$(q "select rolconnlimit from pg_roles where rolname='$ROLE'")
[ "${CL:--1}" -ge 0 ] && ok "limite de connexions fixée ($CL)" \
  || note "pas de limite de connexions (CONNECTION LIMIT), recommandé"

# 5. l'accès réseau est restreint dans pg_hba (pas 0.0.0.0/0)
if grep -E "^host.*(all|$ROLE)" /etc/postgresql/16/main/pg_hba.conf \
     | grep -q '0.0.0.0/0'; then
  ko "pg_hba autorise 0.0.0.0/0 : restreins à l'hôte du prestataire"
else
  ok "pg_hba ne s'ouvre pas à tout Internet"
fi

if [ -r "$SAUV/$ID.debut" ]; then
  note "temps écoulé : $(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
