#!/usr/bin/env bash
# break_M14_04.sh — panne BF14.4 (MaxAuthTries atteint : 5 clés parasites)
# À lancer SUR lab-adm, avec sudo, L14.3 en place (lab-web en MaxAuthTries 3).
# Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

CIBLE="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$CIBLE" | cut -d: -f6)
[ -n "$HOMEDIR" ] || { echo "utilisateur $CIBLE inconnu" >&2; exit 1; }

SAUV=/root/.breakfix-backup
LEG="$HOMEDIR/.ssh/legacy"
CONF="$HOMEDIR/.ssh/config"
mkdir -p "$SAUV"

# --- sauvegarde de la configuration et du bashrc, une seule fois ---------
[ -f "$SAUV/M14_04.config" ] || \
  cp -a "$CONF" "$SAUV/M14_04.config" 2>/dev/null || true
[ -f "$SAUV/M14_04.bashrc" ] || \
  cp -a "$HOMEDIR/.bashrc" "$SAUV/M14_04.bashrc" 2>/dev/null || true

# --- cinq clés parasites, comme en produirait un historique d'équipe -----
# cinq et pas six : lab-db (MaxAuthTries 6 par défaut) doit encore accepter
# la bonne clé en sixième position, lab-web (MaxAuthTries 3, L14.3) non.
install -d -o "$CIBLE" -g "$CIBLE" -m 700 "$LEG"
for n in 1 2 3 4 5; do
  [ -f "$LEG/cle$n" ] && continue
  runuser -u "$CIBLE" -- ssh-keygen -q -t ed25519 -N '' \
    -C "ancienne-cle-$n@lab-adm" -f "$LEG/cle$n"
done
chown -R "$CIBLE":"$CIBLE" "$LEG"

# --- elles passent devant la bonne clé dans le fichier de configuration --
touch "$CONF"
if ! grep -q '# lab14-legacy' "$CONF"; then
  TMP=$(mktemp)
  {
    echo "# lab14-legacy : identités héritées de l'ancienne équipe"
    echo "Host *"
    for n in 1 2 3 4 5; do
      echo "    IdentityFile ~/.ssh/legacy/cle$n"
    done
    echo "    IdentitiesOnly no"
    echo
    cat "$CONF"
  } > "$TMP"
  install -o "$CIBLE" -g "$CIBLE" -m 600 "$TMP" "$CONF"
  rm -f "$TMP"
fi

# --- et l'agent les charge à chaque ouverture de session -----------------
if ! grep -q 'lab14-legacy' "$HOMEDIR/.bashrc" 2>/dev/null; then
  cat >> "$HOMEDIR/.bashrc" <<'EOF'

# lab14-legacy : chargement des identités héritées
# (ssh-add -l sort en 1 si l'agent est vide, en 2 s'il est injoignable)
ssh-add -l >/dev/null 2>&1; [ $? -ne 2 ] && ssh-add -q ~/.ssh/legacy/cle[1-5] 2>/dev/null
EOF
  chown "$CIBLE":"$CIBLE" "$HOMEDIR/.bashrc"
fi

# --- on les charge aussi dans l'agent de la session en cours -------------
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ]; then
  runuser -u "$CIBLE" -- env SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
    ssh-add -q "$LEG"/cle1 "$LEG"/cle2 "$LEG"/cle3 \
               "$LEG"/cle4 "$LEG"/cle5 2>/dev/null || true
fi

cat <<'EOF'

Symptôme attendu : depuis lab-adm, « ssh lab-web » affiche après
quelques secondes « Received disconnect from 10.10.10.11 port 22:2: Too
many authentication failures ». La même commande avec
« -i ~/.ssh/id_ed25519 » échoue de la même façon. « ssh lab-db »
fonctionne encore, mais nettement plus lentement qu'avant.
EOF
