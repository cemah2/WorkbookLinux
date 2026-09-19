#!/usr/bin/env bash
# break_M19_08.sh — panne BF19.8 (boucle de redémarrage systemd,
#                   jusqu'à start-limit-hit)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DROPD=/etc/systemd/system/vitrine-api.service.d
DROP="$DROPD/90-m16-08.conf"
mkdir -p "$SAUV" "$DROPD"

[ -x /opt/vitrine/bin/vitrine-api.py ] || {
  echo "/opt/vitrine/bin/vitrine-api.py absent : lance setup_M19.sh" >&2
  exit 1; }

if [ ! -f "$SAUV/M19_08.etat" ]; then
  systemctl show vitrine-api \
    -p Restart -p RestartUSec -p RuntimeMaxUSec \
    -p StartLimitBurst -p StartLimitIntervalUSec \
    > "$SAUV/M19_08.etat" 2>/dev/null || true
fi

# --- la panne -----------------------------------------------------------
# Un collègue a voulu « mettre un timeout de 5 secondes sur les requêtes »
# et a posé RuntimeMaxSec : systemd tue donc le service toutes les 5 s.
# Avec Restart=always et RestartSec=1, le compteur de démarrages explose
# et l'unité finit en start-limit-hit.
cat > "$DROP" <<'EOF'
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
RuntimeMaxSec=5
Restart=always
RestartSec=1s
EOF
chmod 0644 "$DROP"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl reset-failed vitrine-api.service >/dev/null 2>&1 || true
  systemctl restart vitrine-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : le site répond une seconde sur trois. « systemctl
status vitrine-api » affiche tantôt activating (auto-restart), tantôt
failed. Au bout de quelques dizaines de secondes, l'unité se fige sur
« Failed with result 'start-limit-hit' » et refuse tout démarrage.
Le journal défile à une vitesse anormale.
EOF
