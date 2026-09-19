#!/usr/bin/env bash
# break_M12_03.sh — panne BF12.3 (clé d'hôte changée)
# À lancer SUR lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup/M12_03
SSHD=$(command -v sshd || echo /usr/sbin/sshd)
mkdir -p "$SAUV"

# --- sauvegarde des vraies clés d'hôte, une seule fois -------------------
if [ ! -f "$SAUV/.fait" ]; then
  cp -a /etc/ssh/ssh_host_* "$SAUV/" 2>/dev/null || true
  for f in /etc/ssh/ssh_host_*_key.pub; do
    [ -e "$f" ] || continue
    ssh-keygen -lf "$f"
  done > "$SAUV/empreintes-origine.txt" 2>/dev/null || true
  : > "$SAUV/.fait"
fi

# --- la panne : régénération complète des clés d'hôte -------------------
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A >/dev/null

# les clés régénérées doivent être lisibles par sshd
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub

"$SSHD" -t
if [ -d /run/systemd/system ]; then
  systemctl restart ssh.socket >/dev/null 2>&1 || true
  systemctl restart ssh       >/dev/null 2>&1 || \
  systemctl restart sshd      >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : depuis lab-adm, toute connexion vers lab-web affiche
le pavé « @@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@@ »
et refuse d'aller plus loin. lab-db et lab-ops répondent normalement, et
personne dans l'équipe ne reconnaît avoir réinstallé la machine.
EOF
