#!/usr/bin/env bash
# break_M24_02.sh — panne BF24.2 : « le refactoring veut tout détruire ».
# Réindexe les VM lab2 dans l'état comme si elles avaient été créées avec
# count (lab[0]..lab[4] ou module.vm[0]..[4]) alors que le code est en
# for_each : le plan annonce 5 to add, 5 to destroy. Idempotent.
# Sauvegarde de l'état dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab24"
ENVF="$BASE/.env"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -r "$ENVF" ] || { echo "$ENVF absent : fais E24.8 d'abord" >&2; exit 1; }

DIR="${DIR:-$BASE/02-lab2}"
[ -f "$DIR/.terraform/terraform.tfstate" ] \
  || { echo "$DIR n'est pas initialisé (tofu init) : fais L24.2 d'abord" >&2; exit 1; }

tofu_as_user() {
  sudo -u "$LAB_USER" -H bash -c "set -a; . '$ENVF'; set +a; cd '$DIR' && $*"
}

ST=$(tofu_as_user tofu state pull)
[ -n "$ST" ] || { echo "impossible de lire l'état (tofu state pull)" >&2; exit 1; }
[ -f "$SAUV/M24_02_state.json" ] || printf '%s\n' "$ST" > "$SAUV/M24_02_state.json"

if jq -e '[.resources[] | select(.type == "proxmox_virtual_environment_vm"
           and .name == "lab" and (.module // "") == "")
           | .instances[] | select(.index_key | type == "string")] | length > 0' \
     <<<"$ST" >/dev/null; then
  # cas 02-lab2 : resource "lab" indexée par clé -> par entier
  NEW=$(jq '.serial += 1
    | (.resources[] | select(.type == "proxmox_virtual_environment_vm"
        and .name == "lab" and (.module // "") == ""))
      |= (.each = "list"
          | .instances = ([.instances[]] | sort_by(.index_key) | to_entries
                          | map(.value + {index_key: .key})))' <<<"$ST")
elif jq -e '[.resources[] | select((.module // "") | startswith("module.vm[\""))]
             | length > 0' <<<"$ST" >/dev/null; then
  # cas 04-modules : module.vm["nom"] -> module.vm[n]
  NEW=$(jq '.serial += 1
    | ([.resources[] | select((.module // "") | startswith("module.vm[\""))
        | .module] | unique | sort) as $mods
    | (.resources[] | select((.module // "") | startswith("module.vm[\"")))
      |= (.module as $m
          | .module = "module.vm[" + ($mods | index($m) | tostring) + "]")' \
    <<<"$ST")
else
  echo "l'état est déjà indexé par entier : rien à refaire"
  NEW=""
fi

if [ -n "$NEW" ]; then
  TMP=$(mktemp); printf '%s\n' "$NEW" > "$TMP"; chown "$LAB_USER" "$TMP"
  tofu_as_user tofu state push "$TMP" >/dev/null
  rm -f "$TMP"
fi

cat <<EOF

Symptôme attendu : dans $DIR, un collègue a remplacé count par for_each
(c'est le code actuel) et
  tofu plan
annonce 5 to add, 5 to destroy : les cinq VM lab2 seraient détruites puis
recréées, données comprises. Interdit d'appliquer, de revenir à count, ou de
faire state rm + import. Objectif : plan vide, relisible en PR.
EOF
