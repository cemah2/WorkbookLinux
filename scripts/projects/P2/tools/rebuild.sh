#!/usr/bin/env bash
# rebuild.sh — reconstruction complète chronométrée d'un environnement
# usage : tools/rebuild.sh <staging|prod> <image_tag>
# Journal : docs/rebuild-<date>.log (utilisé par check_PB_09.sh)
set -euo pipefail
ENV="${1:?env}"; TAG="${2:?tag}"
cd "$(dirname "$0")/.."
LOG="docs/rebuild-$(date +%Y%m%d-%H%M).log"
T0=$(date +%s)
step() { printf '[%5ds] %s\n' "$(( $(date +%s) - T0 ))" "$*" | tee -a "$LOG"; }
step "reconstruction $ENV démarrée (tag $TAG)"
step "1/5 destruction des VM"
tofu -chdir=infra workspace select "$ENV"
tofu -chdir=infra destroy -auto-approve -var-file="envs/$ENV.tfvars" \
  >>"$LOG" 2>&1
step "2/5 provisionnement OpenTofu"
tofu -chdir=infra apply -auto-approve -var-file="envs/$ENV.tfvars" \
  >>"$LOG" 2>&1
for h in $(awk '/ansible_host=/{sub("ansible_host=","",$2); print $2}' \
           "ansible/inventory/$ENV.ini"); do
  ssh-keygen -R "$h" >/dev/null 2>&1 || true
  until ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
        "mathieu@$h" true 2>/dev/null; do sleep 5; done
done
step "3/5 baseline Ansible"
ansible-playbook -i "ansible/inventory/$ENV.ini" \
  ansible/playbooks/baseline.yml >>"$LOG" 2>&1
step "4/5 déploiement de l'application ($TAG)"
ansible-playbook -i "ansible/inventory/$ENV.ini" \
  ansible/playbooks/deploy.yml -e "factura_image_tag=$TAG" \
  -e ansible_user=deploy >>"$LOG" 2>&1
step "5/5 restauration de la dernière sauvegarde"
ansible-playbook -i "ansible/inventory/$ENV.ini" \
  ansible/playbooks/restore.yml >>"$LOG" 2>&1
WEB=$(awk '/web.*ansible_host=/{sub("ansible_host=","",$2); print $2}' \
      "ansible/inventory/$ENV.ini" | head -1)
tools/smoke.sh "http://$WEB" "$TAG" | tee -a "$LOG"
T1=$(date +%s)
step "TOTAL: $((T1 - T0)) s"
