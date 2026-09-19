#!/usr/bin/env bash
# check_M20_02.sh — vérifie le lab L20.2 (cinq VM lab2 avec OpenTofu et for_each)
# À lancer sur lab-adm, en tant que mathieu. Charge ~/lab20/.env.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L20.2 =="

BASE="$HOME/lab20"
DIR="$BASE/02-lab2"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
TOFU=$(command -v tofu || command -v terraform || true)
[ -n "$TOFU" ] || { ko "ni tofu ni terraform dans le PATH (20.1)"; exit 1; }
cd "$DIR" 2>/dev/null || { ko "$DIR absent (setup_M20.sh)"; exit 1; }
if [ -r "$BASE/.env" ]; then set -a; . "$BASE/.env"; set +a; ok ".env chargé"
else ko "$BASE/.env absent (E20.8)"; fi

# --- 1. fichiers et forme --------------------------------------------------
for f in versions.tf providers.tf main.tf variables.tf outputs.tf terraform.tfvars; do
  [ -s "$f" ] && ok "$f présent" || ko "$f absent"
done
grep -q 'source *= *"bpg/proxmox"' versions.tf 2>/dev/null \
  && ok "provider bpg/proxmox déclaré" || ko "required_providers sans bpg/proxmox"
grep -qE 'api_token|endpoint' providers.tf 2>/dev/null \
  && ko "providers.tf contient endpoint/api_token : utilise les variables d'env" \
  || ok "providers.tf sans identifiants en dur"
grep -rqE 'terraform@pve!' --include='*.tf' --include='*.tfvars' . \
  && ko "un token Proxmox apparaît dans un fichier .tf/.tfvars" \
  || ok "aucun token dans le code"
grep -q 'for_each' main.tf 2>/dev/null && ok "for_each utilisé" \
  || ko "pas de for_each dans main.tf (étape 4)"
grep -q 'cidrhost' ./*.tf 2>/dev/null && ok "IP calculée avec cidrhost" \
  || ko "cidrhost absent : l'IP doit être calculée depuis host"
grep -q 'validation' variables.tf 2>/dev/null && ok "bloc validation présent" \
  || ko "aucune validation sur var.vms (VMID 9100-9199, host 100-129)"
grep -q 'optional(' variables.tf 2>/dev/null && ok "optional() utilisé" \
  || ko "pas d'optional() dans le type de vms"
grep -qE 'stop_on_destroy *= *true' main.tf && ok "stop_on_destroy = true" \
  || ko "stop_on_destroy = true manquant"
grep -qE 'enabled *= *true' main.tf && ok "agent activé" || ko "agent { enabled = true } manquant"
grep -q 'moved' ./*.tf && ok "bloc moved présent (web -> lab[\"lab2-web\"])" \
  || note "aucun bloc moved : la VM web a-t-elle été recréée ?"

"$TOFU" fmt -check -recursive >/dev/null 2>&1 && ok "tofu fmt -check" \
  || ko "tofu fmt -check signale des fichiers non formatés"
if "$TOFU" validate >/dev/null 2>&1; then ok "tofu validate"
else ko "tofu validate échoue (tofu init fait ? lis le message)"; fi

# --- 2. état et plan -----------------------------------------------------------
SL=$("$TOFU" state list 2>/dev/null)
N=$(grep -c '^proxmox_virtual_environment_vm\.lab\["' <<<"$SL")
[ "$N" -eq 5 ] && ok "5 instances lab[\"...\"] dans l'état" \
  || ko "$N instance(s) lab[\"...\"] dans l'état, 5 attendues"
for n in lab2-adm lab2-web lab2-db lab2-rhel lab2-ops; do
  grep -q "lab\[\"$n\"\]" <<<"$SL" || ko "lab[\"$n\"] absente de l'état"
done
grep -q '^proxmox_virtual_environment_vm\.web$' <<<"$SL" \
  && ko "la ressource web existe encore : bloc moved manquant" || true

if "$TOFU" plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1; then
  ok "tofu plan vide (idempotent)"
else
  rc=$?
  [ "$rc" -eq 2 ] && ko "tofu plan n'est pas vide (drift ou attribut non déclaré)" \
    || ko "tofu plan échoue (token, réseau, verrou ?)"
fi

# --- 3. outputs et VM joignables --------------------------------------------
IPS=$("$TOFU" output -json ips 2>/dev/null | jq -r 'to_entries[] | "\(.key) \(.value)"')
[ "$(wc -l <<<"$IPS")" -eq 5 ] && [ -n "$IPS" ] && ok "output ips : 5 entrées" \
  || ko "output ips absent ou incomplet"
"$TOFU" output -json vm_ids >/dev/null 2>&1 && ok "output vm_ids" || ko "output vm_ids absent"
"$TOFU" output -json ssh 2>/dev/null | grep -q 'ssh mathieu@' && ok "output ssh" \
  || ko "output ssh absent ou mal formé"
while read -r n ip; do
  [ -n "${ip:-}" ] || continue
  H=$($SSH "mathieu@$ip" hostname 2>/dev/null)
  [ "$H" = "$n" ] && ok "$n joignable en $ip" \
    || ko "$n ($ip) : ssh injoignable ou hostname différent ($H)"
done <<<"$IPS"
grep -q ' 10.10.10.103$' <<<"$IPS" && grep -q ' 10.10.10.105$' <<<"$IPS" \
  && ok "adressage 10.10.10.101-105 respecté" || ko "adressage inattendu dans ips"

# --- 4. notes ----------------------------------------------------------------
grep -qiE 'known after apply' notes.md 2>/dev/null && ok "notes.md : known after apply" \
  || ko "notes.md ne mentionne pas les attributs (known after apply)"
grep -qE '15m|timeout' notes.md 2>/dev/null && ok "notes.md : agent.timeout" \
  || ko "notes.md ne mentionne pas agent.timeout"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
