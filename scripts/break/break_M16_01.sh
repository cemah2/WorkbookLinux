#!/usr/bin/env bash
# break_M16_01.sh — panne BF16.1 (fuite mémoire jusqu'à l'OOM killer)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DROPD=/etc/systemd/system/vitrine-api.service.d
DROP="$DROPD/90-m16-01.conf"
mkdir -p "$SAUV" "$DROPD"

[ -x /opt/vitrine/bin/vitrine-api.py ] || {
  echo "/opt/vitrine/bin/vitrine-api.py absent : lance setup_M16.sh" >&2
  exit 1; }

# --- sauvegarde de l'état avant de casser -------------------------------
if [ ! -f "$SAUV/M16_01.etat" ]; then
  {
    echo "drop-ins presents avant la panne :"
    ls -1 "$DROPD" 2>/dev/null || true
    echo "MemoryMax avant : \
$(systemctl show vitrine-api -p MemoryMax --value 2>/dev/null)"
  } > "$SAUV/M16_01.etat"
fi

# Les garde-fous mémoire éventuellement posés en L16.2 sont mis de côté :
# sinon la fuite serait contenue et le symptôme n'apparaîtrait pas.
for f in "$DROPD"/*.conf; do
  [ -e "$f" ] || continue
  case "$f" in
    *90-m16-01.conf) continue ;;
  esac
  if grep -qs 'MemoryMax\|MemoryHigh' "$f"; then
    mv "$f" "$SAUV/M16_01.$(basename "$f").mis-de-cote"
  fi
done

# --- la panne -----------------------------------------------------------
# 12 Mo par seconde, jamais rendus. Sur une VM à 2 Go, l'OOM killer
# intervient en deux à trois minutes, puis le cycle recommence.
cat > "$DROP" <<'EOF'
[Service]
Environment=VITRINE_FUITE=12
MemoryMax=infinity
MemoryHigh=infinity
Restart=always
RestartSec=3s
EOF
chmod 0644 "$DROP"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl reset-failed vitrine-api.service >/dev/null 2>&1 || true
  systemctl restart vitrine-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : le site répond, puis se met à ramer, puis renvoie une
erreur pendant quelques secondes, puis refonctionne. Le cycle se répète
toutes les deux à trois minutes et les utilisateurs perdent leur panier.
« systemctl status vitrine-api » reste sur active (running), mais la date
du « since » rajeunit sans arrêt.
EOF
