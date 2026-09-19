#!/usr/bin/env bash
# break_M09_04.sh — panne BF9.4 (règle udev qui renomme l'interface :
#                   Netplan ne trouve plus ens18). NE REDÉMARRE PAS la VM.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
R=/etc/udev/rules.d/70-lab-net-stable.rules

IF=$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')
[ -n "$IF" ] || { echo "aucune interface par défaut trouvée" >&2; exit 1; }
MAC=$(cat "/sys/class/net/$IF/address")
[ -n "$MAC" ] || { echo "adresse MAC de $IF introuvable" >&2; exit 1; }

echo "$IF $MAC" > "$SAUV/M09_04.interface"
[ -f "$R" ] && [ ! -f "$SAUV/M09_04.rules" ] && cp -a "$R" "$SAUV/M09_04.rules"

cat > "$R" <<EOF2
# OPS-455 : nom d'interface « stable » pour la supervision
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="$MAC", NAME="net0"
EOF2
chmod 0644 "$R"
udevadm control --reload 2>/dev/null || true

cat <<'EOF2'

Symptôme attendu : APRÈS « sudo reboot », la VM n'a plus d'adresse IP.
Sur la console (qm terminal 9001), l'interface existe, le pilote est chargé,
mais elle ne s'appelle plus ens18, et « netplan apply » ne signale rien.
Rien n'est cassé tant que la VM n'a pas redémarré.
EOF2
