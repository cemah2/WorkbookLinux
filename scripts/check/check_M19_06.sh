#!/usr/bin/env bash
# check_M19_06.sh — vérifie le défi D19 (dépôt d'infra de référence)
# À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute make check/deploy.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }
echo "== Vérification D19 =="

export PATH="$HOME/.local/bin:$PATH"
D="$HOME/lab19/factura-infra"
NOTES="$HOME/lab19/rapports/D19-notes.md"
cd "$D" 2>/dev/null || { ko "$D absent"; exit 1; }
g() { git "$@" 2>/dev/null; }

# --- 1. arborescence -------------------------------------------------------
for f in ansible.cfg site.yml requirements.yml .ansible-lint .yamllint \
         .gitignore README.md Makefile inventory/hosts.yml docs/RUNBOOK.md; do
  [ -f "$f" ] && ok "$f" || ko "$f manquant"
done
for p in baseline nginx postgresql rolling monitoring; do
  [ -f "playbooks/$p.yml" ] && ok "playbooks/$p.yml" || ko "playbooks/$p.yml manquant"
done
for r in common nginx_vitrine postgresql_vitrine node_exporter; do
  if [ -d "roles/$r" ]; then
    [ -f "roles/$r/defaults/main.yml" ] && [ -f "roles/$r/meta/main.yml" ] \
      && [ -f "roles/$r/README.md" ] && [ -f "roles/$r/tasks/main.yml" ] \
      && ok "roles/$r : defaults, meta, README, tasks" \
      || ko "roles/$r : defaults/main.yml, meta/main.yml, README.md ou tasks/main.yml manquant"
  else ko "roles/$r absent"; fi
done
for gdir in all web db ubuntu rhel; do
  [ -d "inventory/group_vars/$gdir" ] && ok "inventory/group_vars/$gdir/" \
    || ko "inventory/group_vars/$gdir/ (répertoire) manquant"
done

# --- 2. site.yml et playbooks ---------------------------------------------
n=$(grep -c 'import_playbook' site.yml 2>/dev/null)
[ "$n" -ge 4 ] && ok "site.yml importe $n playbooks" \
  || ko "site.yml doit importer les playbooks avec import_playbook ($n trouvé)"
grep -q 'baseline' site.yml && ok "site.yml : baseline importée" \
  || ko "site.yml n'importe pas playbooks/baseline.yml"
if command -v ansible-playbook >/dev/null; then
  ansible-playbook site.yml --syntax-check >/dev/null 2>&1 \
    && ok "site.yml --syntax-check" || ko "site.yml échoue en --syntax-check"
  hosts=$(ansible-playbook site.yml --list-hosts 2>/dev/null)
  for h in lab-web lab-db lab-rhel lab-ops; do
    printf '%s\n' "$hosts" | has "$h" || ko "site.yml ne cible jamais $h"
  done
  ok "site.yml --list-hosts lu"
fi
grep -rqE 'lab-(web|db|rhel|ops)|10\.10\.10\.' roles/*/tasks roles/*/templates \
  roles/*/defaults 2>/dev/null \
  && ko "IP ou nom du lab codé en dur dans un rôle (tout doit venir de l'inventaire)" \
  || ok "aucune IP / nom du lab dans roles/"

# --- 3. secrets ------------------------------------------------------------
for v in inventory/group_vars/all/vault.yml inventory/group_vars/db/vault.yml; do
  if [ -f "$v" ]; then
    head -1 "$v" | has '^\$ANSIBLE_VAULT' && ok "$v chiffré" || ko "$v en clair"
  else ko "$v manquant"; fi
done
grep -q '^\.vault_pass' .gitignore && ok ".vault_pass dans .gitignore" \
  || ko ".vault_pass absent de .gitignore"
g ls-files --error-unmatch .vault_pass >/dev/null 2>&1 \
  && ko ".vault_pass est VERSIONNÉ (git rm --cached, puis change le mot de passe)" \
  || ok ".vault_pass n'est pas versionné"
grep -rqE '^vault_' inventory/group_vars/*/vars.yml 2>/dev/null \
  && ko "une variable vault_* est définie dans un vars.yml en clair" \
  || ok "aucune variable vault_* définie en clair"
grep -rqE '\{\{ *vault_' inventory/group_vars 2>/dev/null \
  && ok "les vars.yml référencent des vault_*" \
  || ko "aucune référence {{ vault_* }} dans les vars.yml"
if g grep -il 'secret' -- ':!*.md' ':!docs' >/dev/null 2>&1; then
  g grep -i 'secret' -- ':!*.md' ':!docs' | has -viE 'vault|no_log|secrets found|\$ANSIBLE_VAULT' \
    && ko "git grep -i secret trouve quelque chose en clair (hors vault/no_log)" \
    || ok "git grep -i secret : rien en clair"
else ok "git grep -i secret : rien"; fi

# --- 4. qualité ------------------------------------------------------------
for t in lint check deploy; do
  grep -Eq "^$t:" Makefile && ok "cible make $t" || ko "cible make $t absente"
done
grep -q 'production' .ansible-lint && ok ".ansible-lint : profil production" \
  || ko ".ansible-lint : profile: production attendu"
if command -v yamllint >/dev/null; then
  yamllint . >/dev/null 2>&1 && ok "yamllint . propre" || ko "yamllint . signale des erreurs"
else note "yamllint absent"; fi
if command -v ansible-lint >/dev/null; then
  ansible-lint -q >/dev/null 2>&1 && ok "ansible-lint propre" \
    || ko "ansible-lint signale des problèmes (make lint)"
else note "ansible-lint absent"; fi
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : make check / make deploy non testés"
elif command -v ansible-playbook >/dev/null; then
  ansible-playbook site.yml --check --diff >/dev/null 2>&1 \
    && ok "make check (site.yml --check --diff) sort en 0" \
    || ko "site.yml --check --diff échoue"
  out=$(ansible-playbook site.yml 2>&1)
  if [ "$(printf '%s\n' "$out" | grep -c 'changed=0 .*failed=0')" -eq 4 ]; then
    ok "site.yml rejoué : changed=0 failed=0 sur les 4 hôtes"
  else ko "site.yml rejoué n'est pas changed=0 partout (relis le recap)"; fi
fi

# --- 5. documentation ------------------------------------------------------
for mot in pipx vault rolling; do
  grep -qi "$mot" README.md && ok "README parle de « $mot »" \
    || ko "README ne mentionne pas « $mot »"
done
grep -q '|' README.md && ok "README contient un tableau (variables par rôle)" \
  || ko "README : tableau des variables ajustables absent"
grep -qi 'molecule' README.md && ok "README : Molecule décrit" \
  || ko "README ne décrit pas la séquence molecule test"
for mot in UNREACHABLE 'sudo password' python handler idempot vault; do
  grep -qi "$mot" docs/RUNBOOK.md && ok "RUNBOOK : $mot" \
    || ko "RUNBOOK : erreur « $mot » non traitée"
done

# --- 6. git et rapport -----------------------------------------------------
n=$(g rev-list --count HEAD 2>/dev/null || echo 0)
[ "$n" -ge 5 ] && ok "git : $n commits" || ko "git : $n commit(s), attendu >= 5"
[ -z "$(g status --porcelain)" ] && ok "git : arbre de travail propre" \
  || ko "git : modifications non commitées"
if [ -f "$NOTES" ]; then
  ok "D19-notes.md présent"
  for mot in rôle defaults group_vars rollback; do
    grep -qi "$mot" "$NOTES" && ok "notes : « $mot »" || ko "notes : « $mot » absent"
  done
else ko "$NOTES absent"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
