#!/usr/bin/env bash
# break_M04_03.sh — panne BF4.3 (usermod -G sans -a : tous les groupes perdus)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

U=karim
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

getent passwd "$U" >/dev/null || {
  echo "compte $U absent : lance d'abord setup_M04.sh" >&2; exit 1; }

# --- sauvegarde de l'état avant de casser -------------------------------
id -nG "$U" > "$SAUV/M04_03.groupes" 2>/dev/null || true
cp -a /etc/group "$SAUV/M04_03.group" 2>/dev/null || true

# le groupe docker doit exister pour que la commande fautive ait un sens
groupadd -f docker >/dev/null 2>&1

# --- la panne : -G SANS -a remplace la liste complète des secondaires ---
# --- (usermod écrit de lui-même /etc/group- : c'est la piste du fix)    ---
usermod -G docker "$U"

cat <<'EOF'

Symptôme attendu : à sa prochaine connexion, karim n'a plus aucun privilège.
  sudo -l          -> "Sorry, user karim may not run sudo on <hôte>."
  ls /srv/factura  -> Permission denied
  le déploiement échoue
Le collègue qui est intervenu affirme n'avoir tapé qu'une seule commande, et
la session SSH que karim avait déjà ouverte a continué de fonctionner.
EOF
