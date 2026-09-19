#!/usr/bin/env bash
# break_M12_02.sh — panne BF12.2 (AllowUsers déposé dans un fragment)
# À lancer SUR lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
FRAG=/etc/ssh/sshd_config.d/00-maintenance.conf
SSHD=$(command -v sshd || echo /usr/sbin/sshd)
mkdir -p "$SAUV" /etc/ssh/sshd_config.d

# --- le fichier principal doit bien inclure les fragments ----------------
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d' \
     /etc/ssh/sshd_config; then
  [ -f "$SAUV/M12_02.sshd_config" ] || \
    cp -a /etc/ssh/sshd_config "$SAUV/M12_02.sshd_config"
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

# --- sauvegarde de l'existant, une seule fois ---------------------------
if [ ! -d "$SAUV/M12_02.d" ]; then
  mkdir -p "$SAUV/M12_02.d"
  cp -a /etc/ssh/sshd_config.d/. "$SAUV/M12_02.d/" 2>/dev/null || true
fi

# --- le fragment fautif, au nom rassurant et au préfixe prioritaire -----
cat > "$FRAG" <<'EOF'
# Déposé pendant la fenêtre de maintenance du 17/09 (ticket CHG-4471).
# Restriction temporaire des accès pendant la migration.
AllowUsers root deploiement
EOF
chmod 0644 "$FRAG"

"$SSHD" -t
if [ -d /run/systemd/system ]; then
  systemctl reload ssh >/dev/null 2>&1 || \
  systemctl reload sshd >/dev/null 2>&1 || \
  systemctl restart ssh >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : depuis lab-adm, « ssh mathieu@lab-web » répond
immédiatement « Permission denied (publickey). » pour tous les comptes
d'exploitation. La clé est bonne, les permissions sont bonnes, le
service est actif, et une relecture ligne à ligne de
/etc/ssh/sshd_config ne montre rien d'anormal.
EOF
