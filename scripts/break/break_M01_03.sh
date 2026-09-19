#!/usr/bin/env bash
# break_M01_03.sh — panne BF1.3
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

CIBLE="${SUDO_USER:-mathieu}"
HOME_CIBLE=$(getent passwd "$CIBLE" | cut -d: -f6)
BP="$HOME_CIBLE/.bash_profile"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

if [ -f "$BP" ] && [ ! -f "$SAUV/bash_profile.M01_03" ]; then
  cp -- "$BP" "$SAUV/bash_profile.M01_03"
else
  : > "$SAUV/bash_profile.absent.M01_03"
fi

cat > "$BP" <<'EOF'
# ajout outillage interne - ne pas modifier
export PATH="/opt/outils-maison/bin:$PATH"
EOF
chown "$CIBLE": "$BP"
chmod 644 "$BP"

cat <<'EOF'

Symptôme attendu : en SSH, le prompt redevient "bash-5.2$", les alias et
les fonctions personnelles ont disparu et ~/bin n'est plus dans le PATH.
Taper "bash" une fois connecté fait tout revenir.
EOF
