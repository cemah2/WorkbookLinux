#!/usr/bin/env bash
# break_M14_01.sh — panne BF14.1 (permissions de ~/.ssh côté serveur)
# À lancer SUR lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

CIBLE="${1:-mathieu}"
HOMEDIR=$(getent passwd "$CIBLE" | cut -d: -f6)
[ -n "$HOMEDIR" ] || { echo "utilisateur $CIBLE inconnu" >&2; exit 1; }
[ -d "$HOMEDIR/.ssh" ] || { \
  echo "$HOMEDIR/.ssh absent : lance d'abord setup_M14.sh puis L14.1" >&2
  exit 1; }
[ -s "$HOMEDIR/.ssh/authorized_keys" ] || { \
  echo "authorized_keys vide : déploie ta clé (L14.1) avant de casser" >&2
  exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

# --- sauvegarde des modes actuels, une seule fois -----------------------
if [ ! -f "$SAUV/M14_01.modes" ]; then
  {
    stat -c '%a %n' "$HOMEDIR"
    stat -c '%a %n' "$HOMEDIR/.ssh"
    stat -c '%a %n' "$HOMEDIR/.ssh/authorized_keys"
  } > "$SAUV/M14_01.modes"
fi

# --- la panne : StrictModes va refuser de lire authorized_keys -----------
chmod 0757 "$HOMEDIR/.ssh"
chmod 0666 "$HOMEDIR/.ssh/authorized_keys"
chmod g+w,o+w "$HOMEDIR"

# on s'assure que le mot de passe ne sert pas de porte de secours :
# c'est l'état normal après L14.1, on le confirme seulement.
if [ -d /etc/ssh/sshd_config.d ] && \
   ! grep -rqi '^[[:space:]]*PasswordAuthentication[[:space:]]*no' \
     /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config 2>/dev/null; then
  echo "note : l'authentification par mot de passe est encore active," >&2
  echo "       la panne sera moins réaliste (voir L14.1 étape 6)." >&2
fi

cat <<'EOF'

Symptôme attendu : depuis lab-adm, « ssh lab-web » répond
« mathieu@10.10.10.11: Permission denied (publickey). » La même clé
continue de fonctionner sur lab-db et lab-ops. L'authentification par
mot de passe étant désactivée sur lab-web, aucune connexion SSH n'est
plus possible vers cette machine.
EOF
