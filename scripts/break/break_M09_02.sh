#!/usr/bin/env bash
# break_M09_02.sh — panne BF9.2 (sysctl qui « ne tient pas » : rang,
#                   extension, module absent)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

# --- sauvegarde de l'état avant de casser -------------------------------
[ -f "$SAUV/M09_02.sysctl.conf" ] || cp -a /etc/sysctl.conf "$SAUV/M09_02.sysctl.conf"
if [ ! -f "$SAUV/M09_02.modules-load.txt" ]; then
  ls /etc/modules-load.d/ > "$SAUV/M09_02.modules-load.txt" 2>/dev/null || true
fi

# --- 1. le fichier de l'équipe base de données (rang trop bas) ------------
cat > /etc/sysctl.d/10-factura.conf <<'EOF2'
# OPS-412 : demande de l'equipe base de donnees
vm.swappiness = 10
EOF2

# --- 2. le fichier réseau, sans extension .conf ---------------------------
cat > /etc/sysctl.d/20-factura-reseau <<'EOF2'
net.core.somaxconn = 8192
EOF2

# --- 3. la clé qui n'existe pas tant que le module n'est pas chargé -------
cat > /etc/sysctl.d/30-factura-conntrack.conf <<'EOF2'
net.netfilter.nf_conntrack_max = 131072
EOF2
rm -f /etc/modules-load.d/nf_conntrack.conf
modprobe -r nf_conntrack >/dev/null 2>&1 || true

# --- 4. la valeur « par défaut » remise dans /etc/sysctl.conf -------------
if ! grep -q '^vm.swappiness = 60' /etc/sysctl.conf; then
  printf '\n# valeur par defaut Ubuntu (ne pas toucher)\nvm.swappiness = 60\n' \
    >> /etc/sysctl.conf
fi

# --- application comme au boot -------------------------------------------
sysctl --system >/dev/null 2>&1 || true
sysctl -w vm.swappiness=60 net.core.somaxconn=4096 >/dev/null 2>&1 || true

cat <<'EOF2'

Symptôme attendu : « sysctl vm.swappiness » répond 60 et
« sysctl net.core.somaxconn » 4096, alors que les fichiers de l'équipe sont
bien dans /etc/sysctl.d/. Après un reboot, c'est pareil, et
« journalctl -u systemd-sysctl -b » contient un avertissement.
« sudo sysctl -p /etc/sysctl.d/<fichier> » applique la valeur… jusqu'au
prochain reboot.
EOF2
