#!/usr/bin/env bash
# check_M20_03.sh — vérifie le lab L20.3 (état distant S3/MinIO, import rhel, drift)
# À lancer sur lab-adm, en tant que mathieu. Charge ~/lab20/.env.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L20.3 =="

BASE="$HOME/lab20"
DIR="${DIR:-$BASE/02-lab2}"
TOFU=$(command -v tofu || command -v terraform || true)
[ -n "$TOFU" ] || { ko "ni tofu ni terraform dans le PATH"; exit 1; }
cd "$DIR" 2>/dev/null || { ko "$DIR absent"; exit 1; }
if [ -r "$BASE/.env" ]; then set -a; . "$BASE/.env"; set +a; ok ".env chargé"
else ko "$BASE/.env absent"; fi
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] \
  && ok "identifiants S3 dans l'environnement" \
  || ko "AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY absents de .env"

# --- 1. backend ----------------------------------------------------------------
BK=.terraform/terraform.tfstate
if [ -s "$BK" ]; then
  T=$(jq -r '.backend.type // empty' "$BK" 2>/dev/null)
  [ "$T" = "s3" ] && ok "backend configuré : s3" || ko "backend configuré : ${T:-aucun} (attendu s3)"
  jq -r '.backend.config.key // empty' "$BK" | grep -q '^lab2/terraform.tfstate$' \
    && ok "clé lab2/terraform.tfstate" || ko "clé d'état inattendue"
  jq -r '.backend.config.endpoints.s3 // .backend.config.endpoint // empty' "$BK" \
    | grep -q '10.10.10.14:9000' && ok "endpoint MinIO 10.10.10.14:9000" \
    || ko "endpoint S3 : attendu http://10.10.10.14:9000"
  jq -e '.backend.config.use_lockfile == true' "$BK" >/dev/null 2>&1 \
    && ok "use_lockfile = true" || ko "use_lockfile absent ou false"
else
  ko "$BK absent : tofu init -migrate-state non fait ?"
fi
grep -qE 'access_key|secret_key' backend.tf ./*.tf 2>/dev/null \
  && ko "identifiants S3 en dur dans le HCL" || ok "pas d'identifiants S3 dans le HCL"
if [ -s terraform.tfstate ]; then
  jq -e '(.resources | length) == 0' terraform.tfstate >/dev/null 2>&1 \
    && ok "terraform.tfstate local vide" \
    || ko "terraform.tfstate local non vide : deux états divergent"
else
  ok "aucun terraform.tfstate local non vide"
fi

# --- 2. MinIO joignable ----------------------------------------------------------
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://10.10.10.14:9000/minio/health/live \
  | grep -q 200 && ok "MinIO répond sur lab-ops:9000" \
  || ko "MinIO injoignable sur http://10.10.10.14:9000 (docker ps sur lab-ops)"

# --- 3. état distant : import, plan vide ------------------------------------------
SL=$("$TOFU" state list 2>/dev/null)
[ -n "$SL" ] && ok "état distant lisible (state list)" || ko "state list vide ou en échec"
grep -q '^proxmox_virtual_environment_vm\.rhel$' <<<"$SL" \
  && ok "proxmox_virtual_environment_vm.rhel importée" \
  || ko "rhel absente de l'état (étape 4 : import pve/9004)"
[ "$(grep -c 'proxmox_virtual_environment_vm\.lab\[' <<<"$SL")" -eq 5 ] \
  && ok "les 5 VM lab2 sont toujours dans l'état" \
  || ko "les 5 instances lab[...] ne sont plus toutes dans l'état"
grep -q 'id *= *"pve/9004"' imports.tf rhel.tf 2>/dev/null \
  && ok "bloc import id = \"pve/9004\"" || note "bloc import pve/9004 non trouvé (déjà retiré ?)"
[ -s rhel.tf ] && ok "rhel.tf présent" || ko "rhel.tf absent"
grep -q 'ignore_changes' rhel.tf 2>/dev/null && note "rhel.tf utilise ignore_changes (documenté ?)"
"$TOFU" state show proxmox_virtual_environment_vm.rhel 2>/dev/null | grep -qE 'vm_id *= *9004' \
  && ok "state show rhel : vm_id 9004" || ko "state show rhel ne montre pas vm_id 9004"

if "$TOFU" plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1; then
  ok "tofu plan vide"
else
  rc=$?
  [ "$rc" -eq 2 ] && ko "tofu plan non vide (drift 9105 non résolu ? rhel.tf incomplet ?)" \
    || ko "tofu plan échoue (verrou orphelin ? force-unlock)"
fi

# --- 4. état : serial, lineage, workspace ----------------------------------------
ST=$("$TOFU" state pull 2>/dev/null)
jq -e '.serial > 0 and (.lineage | length) > 0' <<<"$ST" >/dev/null 2>&1 \
  && ok "état : serial et lineage présents" || ko "état illisible (state pull)"
WS=$("$TOFU" workspace show 2>/dev/null)
[ "$WS" = "default" ] && ok "workspace courant : default" \
  || ko "workspace courant : $WS (reviens sur default)"
"$TOFU" workspace list 2>/dev/null | grep -q recette && ok "workspace recette créé" \
  || note "workspace recette absent (étape 6)"
grep -qi 'workspace' notes.md 2>/dev/null && ok "notes.md parle des workspaces" \
  || ko "notes.md : explique pourquoi pas de workspaces prod/recette"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
