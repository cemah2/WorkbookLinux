#!/usr/bin/env bash
# check_M20_05.sh — vérifie le défi D20 (lab2 reconstruit en une commande)
# À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute tofu test et Ansible.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D20 =="

BASE="$HOME/lab20"
ROOT="$BASE/04-modules"
MOD="$BASE/modules/vm-ubuntu"
TOFU=$(command -v tofu || command -v terraform || true)
[ -n "$TOFU" ] || { ko "ni tofu ni terraform dans le PATH"; exit 1; }
if [ -r "$BASE/.env" ]; then set -a; . "$BASE/.env"; set +a; fi
cd "$ROOT" 2>/dev/null || { ko "$ROOT absent"; exit 1; }

# --- 1. Makefile -----------------------------------------------------------
if [ -s Makefile ]; then
  ok "Makefile présent"
  for t in fmt validate test plan apply inventory configure deploy destroy; do
    grep -qE "^$t:" Makefile || ko "cible make « $t » absente"
  done
  ok "cibles du Makefile vérifiées"
  grep -qE 'plan\.bin' Makefile && grep -qE 'plan\.txt' Makefile \
    && ok "plan écrit plan.bin et plan.txt" || ko "plan doit produire plan.bin ET plan.txt"
  awk '/^apply:/{f=1;next} /^[a-z]+:/{f=0} f' Makefile | grep -q 'plan.bin' \
    && ok "apply n'accepte que plan.bin" || ko "la cible apply doit appliquer plan.bin"
  grep -q '\.env' Makefile && ok "Makefile charge .env" || ko "Makefile ne lit pas .env"
  grep -qE 'terraform@pve!|AWS_SECRET' Makefile && ko "secret en dur dans le Makefile" || true
  make -n fmt >/dev/null 2>&1 && ok "make -n fmt : Makefile analysable" \
    || ko "make -n fmt échoue (tabulations ? missing separator ?)"
else
  ko "Makefile absent"
fi

# --- 2. module v1.0.0 ---------------------------------------------------------
git -C "$BASE" tag 2>/dev/null | grep -q '^v1\.0\.0$' && ok "tag git v1.0.0" \
  || ko "tag v1.0.0 absent"
grep -qE 'ref=v1\.0\.0' ./*.tf && ok "04-modules consomme ref=v1.0.0" \
  || ko "source du module sans ref=v1.0.0"
[ -s "$MOD/templates/user-data.tftpl" ] && ok "templates/user-data.tftpl" \
  || ko "$MOD/templates/user-data.tftpl absent"
head -n1 "$MOD/templates/user-data.tftpl" 2>/dev/null | grep -q '^#cloud-config' \
  && ok "user-data.tftpl commence par #cloud-config" \
  || ko "user-data.tftpl doit commencer par #cloud-config"
grep -q 'templatefile' "$MOD/main.tf" 2>/dev/null && ok "user_data généré par templatefile" \
  || ko "templatefile absent du module"
grep -qE 'variable "extra_disks"' "$MOD/variables.tf" 2>/dev/null \
  && grep -qE 'list\(number\)' "$MOD/variables.tf" \
  && ok "variable extra_disks = list(number)" || ko "variable extra_disks list(number) absente"
grep -qE 'dynamic *"disk"' "$MOD/main.tf" 2>/dev/null && ok "dynamic \"disk\" pour extra_disks" \
  || ko "pas de bloc dynamic \"disk\" dans le module"
grep -qE 'variable "packages"' "$MOD/variables.tf" 2>/dev/null && ok "variable packages" \
  || ko "variable packages absente (liste de paquets par VM)"
grep -q 'postgresql' terraform.tfvars 2>/dev/null && grep -q 'docker.io' terraform.tfvars \
  && ok "tfvars : postgresql (db) et docker.io (ops)" || ko "tfvars : paquets par VM incomplets"
grep -qE 'extra_disks *= *\[ *5 *\]' terraform.tfvars 2>/dev/null \
  && ok "tfvars : lab2-db extra_disks = [5]" || ko "tfvars : extra_disks = [5] sur lab2-db"

# --- 3. tests, hygiène, README, rapport ------------------------------------------
[ -s tests/deploy.tftest.hcl ] && ok "tests/deploy.tftest.hcl" || ko "tests/deploy.tftest.hcl absent"
grep -qE '910[15]' tests/deploy.tftest.hcl 2>/dev/null && ok "test : plage VMID 9101-9105" \
  || ko "test : la plage 9101-9105 n'est pas vérifiée"
grep -q 'extra_disks\|scsi1\|disk' tests/deploy.tftest.hcl 2>/dev/null \
  && ok "test : second disque de lab2-db" || ko "test : deux disques sur lab2-db non vérifiés"
PC="$BASE/.pre-commit-config.yaml"
grep -q 'tfstate' "$PC" 2>/dev/null && grep -q '\.env' "$PC" \
  && ok "pre-commit refuse tfstate et .env" || ko "pre-commit : hook refusant *.tfstate et .env"
for p in '.env' '*.tfstate' '.terraform/' 'plan.bin'; do
  grep -qF "$p" "$BASE/.gitignore" 2>/dev/null || ko ".gitignore : $p manquant"
done
ok ".gitignore vérifié"
git -C "$BASE" ls-files 2>/dev/null | grep -qE '(^|/)(\.env|.*\.tfstate)$' \
  && ko "un .env ou un tfstate est suivi par git" || ok "aucun .env/tfstate suivi par git"
[ -s README.md ] && grep -qi 'rotation' README.md \
  && ok "README.md avec procédure de rotation du token" \
  || ko "README.md absent ou sans procédure de rotation"
[ -s plan.txt ] && grep -qE 'Plan: [0-9]+ to add' plan.txt \
  && ok "plan.txt de la reconstruction présent" || ko "plan.txt absent ou sans résumé de plan"
RAP="$BASE/rapports/d20.md"
if [ -s "$RAP" ]; then
  ok "rapport d20.md présent"
  grep -qiE 'dur[ée]e|min|s\b' "$RAP" && ok "rapport : durée du deploy" || ko "rapport : durée absente"
  grep -qi 'idempot' "$RAP" && ok "rapport : idempotence" || ko "rapport : idempotence absente"
  grep -qi 'token' "$RAP" && grep -qiE '[ée]tat|state' "$RAP" && grep -qi 'template' "$RAP" \
    && ok "rapport : trois risques (état, token, template)" \
    || ko "rapport : les trois risques état/token/template"
else
  ko "$RAP absent"
fi

# --- 4. état réel -------------------------------------------------------------------
"$TOFU" fmt -check -recursive "$BASE" >/dev/null 2>&1 && ok "tofu fmt -check" \
  || ko "tofu fmt -check signale des fichiers"
"$TOFU" init -input=false >/dev/null 2>&1 && "$TOFU" validate >/dev/null 2>&1 \
  && ok "tofu validate" || ko "tofu validate échoue"
SL=$("$TOFU" state list 2>/dev/null)
[ "$(grep -c '^module\.vm\["[^"]*"\]\.proxmox_virtual_environment_vm' <<<"$SL")" -eq 5 ] \
  && ok "5 VM dans module.vm" || ko "5 VM attendues dans module.vm"
[ "$(grep -c '^module\.vm\["[^"]*"\]\.proxmox_virtual_environment_file' <<<"$SL")" -eq 5 ] \
  && ok "un snippet par VM" || ko "5 snippets attendus (un par VM)"
grep -q '^proxmox_virtual_environment_vm\.rhel$' <<<"$SL" && ok "rhel a survécu" \
  || ko "rhel n'est plus dans l'état (prevent_destroy contourné ?)"
"$TOFU" state show 'module.vm["lab2-db"].proxmox_virtual_environment_vm.this' 2>/dev/null \
  | grep -qE 'interface *= *"scsi1"' && ok "lab2-db : disque scsi1 présent" \
  || ko "lab2-db : pas de scsi1 dans l'état"
if "$TOFU" plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1; then
  ok "tofu plan vide"
else
  rc=$?; [ "$rc" -eq 2 ] && ko "tofu plan non vide" || ko "tofu plan échoue"
fi
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : tofu test et Ansible sautés"
else
  "$TOFU" test >/dev/null 2>&1 && ok "tofu test vert" || ko "tofu test échoue"
  if command -v ansible-playbook >/dev/null 2>&1; then
    OUT=$(ansible-playbook -i "$BASE/ansible/inventory.ini" "$BASE/ansible/base.yml" 2>/dev/null)
    [ "$(grep -cE 'changed=0 .*failed=0' <<<"$OUT")" -eq 5 ] \
      && ok "base.yml idempotent (changed=0 sur 5 hôtes)" \
      || ko "base.yml : changed != 0 ou échec sur au moins un hôte"
  fi
fi
ssh -o BatchMode=yes -o ConnectTimeout=5 mathieu@10.10.10.103 'lsblk -dn -o NAME' 2>/dev/null \
  | grep -q '^sdb$' && ok "lab2-db voit /dev/sdb" || ko "lab2-db : /dev/sdb absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
