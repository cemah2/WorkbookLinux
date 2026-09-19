#!/usr/bin/env bash
# break_M24_03.sh — panne BF24.3 : « le token est dans le pipeline ».
# Dans ~/lab24/02-lab2 : variable avec le token en default + output de debug
# (debug.tf), log d'un job CI qui affiche l'output, plan.txt, commit git, et
# si possible un apply qui enregistre l'output dans l'état. Idempotent.
# Sauvegardes dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab24"
ENVF="$BASE/.env"
DIR="${DIR:-$BASE/02-lab2}"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -r "$ENVF" ] || { echo "$ENVF absent : fais E24.8 d'abord" >&2; exit 1; }
[ -d "$DIR" ] || { echo "$DIR absent : fais L24.2 d'abord" >&2; exit 1; }
set -a; . "$ENVF"; set +a
: "${PROXMOX_VE_API_TOKEN:?}"
TOKEN="$PROXMOX_VE_API_TOKEN"

as_user() { sudo -u "$LAB_USER" -H bash -c "set -a; . '$ENVF'; set +a; cd '$DIR' && $*"; }

if [ -f "$DIR/debug.tf" ] && grep -qF "$TOKEN" "$DIR/debug.tf"; then
  echo "debug.tf déjà en place : rien à refaire"
else
  [ -f "$DIR/debug.tf" ] && cp -a "$DIR/debug.tf" "$SAUV/M24_03_debug.tf.orig"
  as_user tofu state pull > "$SAUV/M24_03_state.json" 2>/dev/null || true

  # 1. le code : « pour faciliter le debug »
  cat > "$DIR/debug.tf" <<EOF
# Ajout temporaire pour le debug du job CI (à retirer un jour)
variable "api_token" {
  description = "token Proxmox utilisé par le pipeline"
  type        = string
  default     = "$TOKEN"
}

output "debug_token" {
  description = "affiché en fin de job pour vérifier que le CI a le bon token"
  value       = var.api_token
}
EOF

  # 2. le log du dernier job CI (les outputs sont affichés par apply)
  cat > "$DIR/ci-job-42.log" <<EOF
[job 42] tofu init -input=false
[job 42] tofu apply -auto-approve -input=false

No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

debug_token = "$TOKEN"
ips = {
  "lab2-adm" = "10.10.10.101"
  "lab2-web" = "10.10.10.102"
}
[job 42] Job succeeded
EOF

  # 3. un plan.txt « pour la revue », committé de force
  printf 'Changes to Outputs:\n  + debug_token = "%s"\n' "$TOKEN" > "$DIR/plan.txt"

  chown "$LAB_USER":"$LAB_USER" "$DIR/debug.tf" "$DIR/ci-job-42.log" "$DIR/plan.txt"

  # 4. l'historique git (le dépôt de L24.4, ou un dépôt créé pour l'occasion)
  sudo -u "$LAB_USER" -H bash -c "
    cd '$BASE' || exit 0
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || git init -q
    git config user.email >/dev/null || git config user.email julien@lab.local
    git config user.name  >/dev/null || git config user.name  Julien
    git add -f 02-lab2/debug.tf 02-lab2/ci-job-42.log 02-lab2/plan.txt
    git commit -qm 'debug : expose le token pour le job CI' || true
  "

  # 5. l'état : l'output y est enregistré si l'apply passe (meilleur effort)
  timeout 180 sudo -u "$LAB_USER" -H bash -c \
    "set -a; . '$ENVF'; set +a; cd '$DIR' && tofu apply -auto-approve \
     -input=false -refresh=false -lock-timeout=30s >/dev/null 2>&1" || true
fi

cat <<EOF

Symptôme attendu : la sécurité a repéré le token Proxmox en clair dans les
logs du dernier job CI (tofu apply affiche les outputs) et dans un fichier
committé. Le projet $DIR a été « amélioré pour faciliter le debug ».
Le job CI reste vert. Interdit de simplement supprimer l'output, et de garder
le token actuel. Objectif : lister TOUS les endroits où le secret a fui,
corriger le code, faire tourner le token, vérifier l'état, plan vide.
EOF
