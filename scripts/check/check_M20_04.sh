#!/usr/bin/env bash
# check_M20_04.sh — vérifie le lab L20.4 (module vm-ubuntu, moved, inventaire,
# qualité). À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute tofu test.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L20.4 =="

BASE="$HOME/lab20"
MOD="$BASE/modules/vm-ubuntu"
ROOT="$BASE/04-modules"
INV="$BASE/ansible/inventory.ini"
TOFU=$(command -v tofu || command -v terraform || true)
[ -n "$TOFU" ] || { ko "ni tofu ni terraform dans le PATH"; exit 1; }
if [ -r "$BASE/.env" ]; then set -a; . "$BASE/.env"; set +a; fi

# --- 1. le module ----------------------------------------------------------
for f in variables.tf main.tf outputs.tf versions.tf README.md; do
  [ -s "$MOD/$f" ] && ok "module : $f" || ko "module : $f absent"
done
for v in name vm_id ip gateway node_name template_id cores memory disk_gb ssh_keys tags user_data; do
  grep -qE "variable \"$v\"" "$MOD/variables.tf" 2>/dev/null \
    || ko "module : variable \"$v\" absente"
done
ok "variables du module vérifiées"
grep -q 'proxmox_virtual_environment_file' "$MOD/main.tf" 2>/dev/null \
  && ok "module : ressource proxmox_virtual_environment_file (snippet)" \
  || ko "module : pas de ressource proxmox_virtual_environment_file"
grep -qE 'content_type *= *"snippets"' "$MOD/main.tf" 2>/dev/null \
  && ok "module : content_type snippets" || ko "module : content_type doit valoir snippets"
grep -q 'user_data_file_id' "$MOD/main.tf" 2>/dev/null \
  && ok "module : initialization.user_data_file_id référencé" \
  || ko "module : user_data_file_id absent"
grep -qE 'count *= *.*user_data|for_each *= *.*user_data' "$MOD/main.tf" 2>/dev/null \
  && ok "module : snippet conditionnel (count/for_each sur user_data)" \
  || ko "module : le snippet doit être créé seulement si user_data est fourni"
for o in vm_id name ip; do
  grep -qE "output \"$o\"" "$MOD/outputs.tf" 2>/dev/null || ko "module : output \"$o\" absent"
done
ok "outputs du module vérifiés"
[ "$(grep -c . "$MOD/README.md" 2>/dev/null)" -ge 8 ] && ok "README.md du module substantiel" \
  || ko "README.md du module trop court (dix lignes attendues)"

# --- 2. la racine 04-modules ---------------------------------------------------
cd "$ROOT" 2>/dev/null || { ko "$ROOT absent"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
grep -qE 'source *= *"(\.\./modules/vm-ubuntu|git::.*vm-ubuntu\?ref=v[0-9])' ./*.tf \
  && ok "module \"vm\" appelé (source locale ou git ref)" \
  || ko "module vm-ubuntu non appelé, ou source sans ref=vX.Y.Z"
grep -qE 'ref=v0\.1\.0|ref=v1\.0\.0' ./*.tf \
  && ok "source git versionnée par tag" || ko "source non versionnée (git::...?ref=v0.1.0)"
git -C "$BASE" tag 2>/dev/null | grep -q '^v0\.1\.0$' && ok "tag git v0.1.0" \
  || ko "tag v0.1.0 absent dans ~/lab20 (git init, commit, tag)"
grep -q 'moved' ./*.tf && ok "blocs moved présents" || note "aucun bloc moved (déjà retirés ?)"
grep -qE 'ssh *\{' providers.tf 2>/dev/null && ok "provider : bloc ssh {} configuré" \
  || ko "provider : bloc ssh {} manquant (nécessaire pour les snippets)"
grep -q 'backend "s3"' ./*.tf && ok "backend s3 déclaré" || ko "backend s3 absent"
[ -s templates/inventory.tftpl ] && ok "templates/inventory.tftpl" || ko "templates/inventory.tftpl absent"
grep -q 'local_file' ./*.tf && ok "local_file.inventory déclaré" || ko "pas de local_file"
[ -s tests/vms.tftest.hcl ] && ok "tests/vms.tftest.hcl" || ko "tests/vms.tftest.hcl absent"
grep -qE 'command *= *plan' tests/vms.tftest.hcl 2>/dev/null && ok "test en mode plan" \
  || ko "le run du test doit être en command = plan"
grep -qE 'hooks:' "$BASE/.pre-commit-config.yaml" 2>/dev/null \
  && grep -q 'fmt' "$BASE/.pre-commit-config.yaml" && grep -q 'validate' "$BASE/.pre-commit-config.yaml" \
  && ok ".pre-commit-config.yaml avec fmt et validate" \
  || ko ".pre-commit-config.yaml absent ou sans hooks fmt/validate"

"$TOFU" fmt -check -recursive "$BASE" >/dev/null 2>&1 && ok "tofu fmt -check -recursive" \
  || ko "tofu fmt -check -recursive signale des fichiers"
for d in "$ROOT" "$MOD"; do
  ( cd "$d" && "$TOFU" init -backend=false -input=false >/dev/null 2>&1 \
      && "$TOFU" validate >/dev/null 2>&1 ) \
    && ok "validate : ${d#$BASE/}" || ko "validate échoue dans ${d#$BASE/}"
done

# --- 3. état et plan ------------------------------------------------------------
"$TOFU" init -input=false >/dev/null 2>&1
SL=$("$TOFU" state list 2>/dev/null)
[ "$(grep -c '^module\.vm\["' <<<"$SL")" -ge 5 ] \
  && ok "état : module.vm[\"...\"] (5 VM)" || ko "état : les VM ne sont pas dans module.vm"
grep -q 'module\.vm\["lab2-web"\]\.proxmox_virtual_environment_vm' <<<"$SL" \
  && ok "module.vm[\"lab2-web\"] présent" || ko "module.vm[\"lab2-web\"] absent"
grep -q 'module\.vm\["lab2-ops"\]\.proxmox_virtual_environment_file' <<<"$SL" \
  && ok "snippet de lab2-ops dans l'état" || ko "aucun snippet pour lab2-ops (étape 3)"
grep -q '^proxmox_virtual_environment_vm\.rhel$' <<<"$SL" \
  && ok "rhel toujours hors module" || ko "rhel absente de l'état"
grep -q '^local_file\.inventory$' <<<"$SL" && ok "local_file.inventory dans l'état" \
  || ko "local_file.inventory absent de l'état"
if "$TOFU" plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1; then
  ok "tofu plan vide"
else
  rc=$?
  [ "$rc" -eq 2 ] && ko "tofu plan non vide" || ko "tofu plan échoue"
fi

# --- 4. inventaire et Ansible ------------------------------------------------------
if [ -s "$INV" ]; then
  ok "inventory.ini présent"
  [ "$(awk '/^\[lab2\]/{f=1;next} /^\[/{f=0} f && /ansible_host=/' "$INV" | wc -l)" -eq 5 ] \
    && ok "[lab2] : 5 hôtes" || ko "[lab2] ne contient pas 5 lignes ansible_host="
  awk '/^\[docker\]/{f=1;next} /^\[/{f=0} f' "$INV" | grep -q '^lab2-ops' \
    && ok "[docker] contient lab2-ops" || ko "[docker] sans lab2-ops"
  grep -q 'ansible_user=mathieu' "$INV" && ok "[lab2:vars] ansible_user=mathieu" \
    || ko "ansible_user=mathieu absent"
  if command -v ansible >/dev/null 2>&1; then
    P=$(ansible -i "$INV" lab2 -m ping -o 2>/dev/null | grep -c SUCCESS)
    [ "$P" -eq 5 ] && ok "ansible ping : 5 SUCCESS" || ko "ansible ping : $P/5 SUCCESS"
  else note "ansible absent : ping sauté"; fi
else
  ko "$INV absent (généré par local_file.inventory)"
fi
ssh -o BatchMode=yes -o ConnectTimeout=5 mathieu@10.10.10.105 \
  'docker version --format {{.Server.Version}}' 2>/dev/null | grep -q . \
  && ok "docker actif sur lab2-ops (snippet appliqué)" \
  || ko "docker absent sur lab2-ops (user-data non appliqué ?)"

# --- 5. tofu test ----------------------------------------------------------------
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : tofu test sauté"
elif "$TOFU" test >/dev/null 2>&1; then ok "tofu test vert"
else ko "tofu test échoue (lis la sortie de tofu test)"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
