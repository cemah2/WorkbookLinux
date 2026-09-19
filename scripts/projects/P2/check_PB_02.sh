#!/usr/bin/env bash
# check_PB_02.sh — vérifie le jalon PB.2 (OpenTofu + cloud-init, workspaces)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.2 =="
REPO="${REPO:-$HOME/factura-v2}"
cd "$REPO/infra" 2>/dev/null || { ko "$REPO/infra introuvable"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
command -v tofu >/dev/null || { ko "tofu absent du PATH"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- code ----------------------------------------------------------------
ls ./*.tf >/dev/null 2>&1 && ok "fichiers .tf présents" || ko "aucun .tf"
grep -rqE 'source *= *"bpg/proxmox"' . --include='*.tf' \
  && ok "provider bpg/proxmox déclaré" || ko "provider bpg/proxmox non déclaré"
grep -rqE 'for_each' . --include='*.tf' \
  && ok "for_each utilisé" || ko "pas de for_each : une ressource par VM ?"
grep -rqE 'terraform\.workspace' . --include='*.tf' \
  && ok "terraform.workspace utilisé pour nommer/paramétrer" \
  || ko "terraform.workspace n'apparaît pas (comment distingues-tu les env ?)"
grep -rqE 'content_type *= *"snippets"|user_data_file_id' . --include='*.tf' \
  && ok "cloud-init user-data personnalisé (snippet)" \
  || ko "pas de user_data cloud-init personnalisé"
grep -rqE 'resource "local_file"' . --include='*.tf' \
  && ok "inventaire Ansible généré par local_file" \
  || ko "aucune ressource local_file : l'inventaire doit être généré"
for e in staging prod; do
  [ -f "envs/$e.tfvars" ] && ok "envs/$e.tfvars présent" \
    || ko "envs/$e.tfvars manquant"
done
git -C "$REPO" ls-files --error-unmatch infra/terraform.tfvars \
  >/dev/null 2>&1 && ko "terraform.tfvars est versionné (token !)" \
  || ok "terraform.tfvars non versionné"
grep -rqE '^\s*api_token\s*=\s*"[^"]*=[0-9a-f-]{36}"' . --include='*.tf' \
  && ko "un token Proxmox est écrit en dur dans un .tf" \
  || ok "aucun token en dur dans les .tf"

# --- état ----------------------------------------------------------------
tofu init -input=false >/dev/null 2>&1 || true
tofu validate >/dev/null 2>&1 && ok "tofu validate OK" || ko "tofu validate KO"
WS=$(tofu workspace list 2>/dev/null)
for e in staging prod; do
  echo "$WS" | grep -qw "$e" && ok "workspace $e existe" \
    || ko "workspace $e absent (tofu workspace new $e)"
done
CUR=$(tofu workspace show 2>/dev/null)
for e in staging prod; do
  tofu workspace select "$e" >/dev/null 2>&1 || continue
  N=$(tofu state list 2>/dev/null | grep -c proxmox_virtual_environment_vm)
  [ "$N" -ge 2 ] && ok "workspace $e : $N VM dans l'état" \
    || ko "workspace $e : $N VM dans l'état (attendu 2 : web et db)"
  if tofu plan -detailed-exitcode -input=false \
       -var-file="envs/$e.tfvars" >/dev/null 2>&1; then
    ok "workspace $e : plan vide (pas de drift)"
  else
    ko "workspace $e : tofu plan propose des changements"
  fi
done
tofu workspace select "$CUR" >/dev/null 2>&1

# --- inventaires et VM ---------------------------------------------------
for e in staging prod; do
  INV="$REPO/ansible/inventory/$e.ini"
  [ -f "$INV" ] && ok "inventaire $INV généré" || { ko "$INV absent"; continue; }
  grep -qE '^\[.*web' "$INV" && grep -qE '^\[.*db' "$INV" \
    && ok "inventaire $e : groupes web et db" \
    || ko "inventaire $e : groupes web/db manquants"
done
for h in 10.10.10.21 10.10.10.22 10.10.10.31 10.10.10.32; do
  if ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$h" \
       'command -v qemu-ga >/dev/null && hostname' >/tmp/h.$$ 2>/dev/null; then
    ok "$h : SSH par clé OK, hostname $(cat /tmp/h.$$), qemu-guest-agent installé"
  else
    ko "$h : SSH par clé impossible ou qemu-guest-agent absent (cloud-init ?)"
  fi
  rm -f /tmp/h.$$
done
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
