#!/usr/bin/env bash
# break_M04_02.sh — panne BF4.2 (le compte karim est bloqué de trois façons)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

U=karim
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

getent passwd "$U" >/dev/null || {
  echo "compte $U absent : lance d'abord setup_M04.sh" >&2; exit 1; }

# --- sauvegarde de l'état avant de casser (une seule fois : relancé, le -
# --- script ne doit pas écraser l'état sain par l'état déjà cassé)       -
if [ ! -s "$SAUV/M04_02.$U" ]; then
  {
    getent passwd "$U"
    getent shadow "$U"
    id -nG "$U"
  } > "$SAUV/M04_02.$U" 2>/dev/null || true
  chmod 600 "$SAUV/M04_02.$U"
fi

# --- blocage 1 : mot de passe verrouillé (champ 2 de /etc/shadow) -------
passwd -l "$U" >/dev/null 2>&1

# --- blocage 2 : compte expiré (champ 8 de /etc/shadow) -----------------
chage -E "$(date -d '-17 days' +%F)" "$U"

# --- blocage 3 : shell de connexion neutralisé (champ 7 de /etc/passwd) -
NOLOGIN=/usr/sbin/nologin
[ -x "$NOLOGIN" ] || NOLOGIN=/sbin/nologin
usermod -s "$NOLOGIN" "$U" >/dev/null 2>&1

cat <<'EOF'

Symptôme attendu : karim ne peut plus ouvrir de session.
  - en SSH par mot de passe : "Permission denied, please try again."
  - depuis root : "su - karim" est refusé avec un message d'expiration
    ("Your account has expired; please contact your system administrator")
Son répertoire personnel et ses fichiers sont intacts, et le compte apparaît
toujours dans "getent passwd karim".
EOF
