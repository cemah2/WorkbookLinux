#!/usr/bin/env bash
# check_M19_03.sh — vérifie le lab L19.3 (PostgreSQL : base, rôle, accès réseau)
# À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute la 2e exécution.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }
echo "== Vérification L19.3 =="

export PATH="$HOME/.local/bin:$PATH"
BASE="$HOME/lab19"
cd "$BASE" 2>/dev/null || { ko "$BASE absent (setup_M19.sh)"; exit 1; }
command -v ansible >/dev/null || { ko "ansible introuvable dans le PATH"; exit 1; }
PB=playbooks/postgresql.yml
[ -f "$PB" ] && ok "$PB présent" || { ko "$PB absent"; exit 1; }

# --- 1. secrets : vault chiffré, référence en clair -----------------------
VAULT=""
for f in inventory/group_vars/db/vault.yml group_vars/db/vault.yml; do
  [ -f "$f" ] && VAULT=$f && break
done
if [ -n "$VAULT" ]; then
  head -1 "$VAULT" | has '^\$ANSIBLE_VAULT' \
    && ok "$VAULT chiffré (\$ANSIBLE_VAULT)" || ko "$VAULT n'est pas chiffré"
  ansible-vault view "$VAULT" 2>/dev/null | has '^vault_vitrine_db_password:' \
    && ok "vault_vitrine_db_password présent dans le vault (déchiffrable)" \
    || ko "vault_vitrine_db_password absent du vault ou vault indéchiffrable"
else ko "group_vars/db/vault.yml absent"; fi
nclair=$(grep -rl 'vault_vitrine_db_password' inventory/group_vars group_vars \
           2>/dev/null | grep -vc 'vault.yml$')
[ "$nclair" -eq 1 ] \
  && ok "une seule référence en clair à vault_vitrine_db_password" \
  || ko "vault_vitrine_db_password référencé dans $nclair fichier(s) clair(s) (attendu 1)"
grep -rEq 'vitrine_db_password:\s*"?\{\{\s*vault_vitrine_db_password' \
  inventory/group_vars group_vars 2>/dev/null \
  && ok "vitrine_db_password référence la variable vault_*" \
  || ko "vitrine_db_password ne pointe pas sur vault_vitrine_db_password"
grep -Eq 'lineinfile' "$PB" && grep -Eq 'postgresql\.conf' "$PB" \
  && ko "lineinfile sur postgresql.conf détecté (utilise postgresql_set)" \
  || ok "pas de lineinfile sur postgresql.conf"

# --- 2. état de lab-db -----------------------------------------------------
pgq() { # pgq <sql>  : exécuté en postgres sur lab-db, résultat brut
  ansible lab-db -b --become-user postgres -m ansible.builtin.command -o \
    -a "psql -tAc \"$1\"" 2>/dev/null | sed 's/.*(stdout) //'
}
r=$(pgq "SHOW listen_addresses")
printf '%s\n' "$r" | has '10.10.10.12' \
  && ok "listen_addresses contient 10.10.10.12 (effectif, donc redémarré)" \
  || ko "listen_addresses effectif = '$r' (postgresql_set + handler restart ?)"
r=$(pgq "SELECT datname||' '||pg_get_userbyid(datdba)||' '||pg_encoding_to_char(encoding) FROM pg_database WHERE datname='vitrine'")
printf '%s\n' "$r" | has 'vitrine vitrine_app UTF8' \
  && ok "base vitrine, propriétaire vitrine_app, UTF8" \
  || ko "base vitrine absente ou mauvais propriétaire/encodage ('$r')"
r=$(ansible lab-db -b -m ansible.builtin.shell -o \
      -a 'grep -E "^host\s+vitrine\s+vitrine_app\s+10.10.10.11/32\s+scram-sha-256" \
          /etc/postgresql/*/main/pg_hba.conf | wc -l' 2>/dev/null)
printf '%s\n' "$r" | has '| 1$' \
  && ok "entrée pg_hba host vitrine vitrine_app 10.10.10.11/32 scram-sha-256" \
  || ko "entrée pg_hba attendue absente (postgresql_pg_hba)"
r=$(ansible lab-db -b -m ansible.builtin.shell -o \
      -a 'ufw status | grep 5432 | grep -c 10.10.10.11' 2>/dev/null)
printf '%s\n' "$r" | has '| 1$' \
  && ok "ufw : 5432/tcp autorisé depuis 10.10.10.11" \
  || ko "ufw : règle 5432 depuis 10.10.10.11 absente sur lab-db"

# --- 3. connexion réseau depuis lab-web, refus depuis lab-adm --------------
PW=$(ansible lab-db -m ansible.builtin.debug -o \
       -a 'msg={{ vitrine_db_password }}' 2>/dev/null \
     | sed -n 's/.*"msg": *"\([^"]*\)".*/\1/p')
if [ -n "$PW" ]; then
  # PGPASSWORD via environment: impossible en ad hoc, on passe par shell
  r=$(ansible lab-web -m ansible.builtin.shell -o \
        -a "PGPASSWORD='$PW' PGCONNECT_TIMEOUT=5 psql -h 10.10.10.12 \
            -U vitrine_app -d vitrine -tAc 'SELECT 1'" 2>/dev/null)
  printf '%s\n' "$r" | has -E 'SUCCESS|CHANGED' && printf '%s\n' "$r" | has '(stdout) 1' \
    && ok "SELECT 1 réussit depuis lab-web avec vitrine_app" \
    || ko "psql depuis lab-web échoue (pg_hba, ufw, listen_addresses, client ?)"
  if command -v psql >/dev/null; then
    PGPASSWORD="$PW" PGCONNECT_TIMEOUT=5 psql -h 10.10.10.12 -U vitrine_app \
      -d vitrine -tAc 'SELECT 1' >/dev/null 2>&1 \
      && ko "psql depuis lab-adm est ACCEPTÉ (pg_hba ou ufw trop larges)" \
      || ok "psql depuis lab-adm est refusé (pg_hba / ufw)"
  else note "psql absent sur lab-adm : refus depuis lab-adm non testé"; fi
else ko "impossible de lire vitrine_db_password via Ansible (vault, vars.yml ?)"; fi

# --- 4. idempotence et lint ------------------------------------------------
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : seconde exécution non testée"
else
  out=$(ansible-playbook "$PB" 2>&1)
  if printf '%s\n' "$out" | has -E '^lab-db .*changed=0 .*failed=0' && \
     ! printf '%s\n' "$out" | has -E 'failed=[1-9]'; then
    ok "seconde exécution : changed=0 failed=0 sur lab-db"
  else ko "la seconde exécution n'est pas changed=0 (relis le recap)"; fi
fi
if command -v ansible-lint >/dev/null; then
  ansible-lint -q "$PB" >/dev/null 2>&1 && ok "ansible-lint muet sur $PB" \
    || ko "ansible-lint signale des problèmes sur $PB"
else note "ansible-lint absent, lint non testé"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
