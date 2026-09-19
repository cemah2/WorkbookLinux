#!/usr/bin/env bash
# break_M19_02.sh — panne BF19.2 (descripteurs de fichiers épuisés)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DROPD=/etc/systemd/system/vitrine-api.service.d
DROP="$DROPD/90-m16-02.conf"
mkdir -p "$SAUV" "$DROPD"

[ -x /opt/vitrine/bin/vitrine-api.py ] || {
  echo "/opt/vitrine/bin/vitrine-api.py absent : lance setup_M19.sh" >&2
  exit 1; }

if [ ! -f "$SAUV/M19_02.etat" ]; then
  {
    echo "LimitNOFILE avant : \
$(systemctl show vitrine-api -p LimitNOFILE --value 2>/dev/null)"
    echo "VITRINE_FD avant : \
$(grep -s '^VITRINE_FD=' /etc/vitrine/api.env || echo absent)"
  } > "$SAUV/M19_02.etat"
fi

# --- la panne -----------------------------------------------------------
# Limite basse héritée d'un « durcissement » mal calibré + une application
# qui ne referme pas ce qu'elle ouvre : la dérive est lente, l'incident
# arrive après quelques centaines de requêtes.
cat > "$DROP" <<'EOF'
[Service]
LimitNOFILE=128
Environment=VITRINE_FD=3
EOF
chmod 0644 "$DROP"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl reset-failed vitrine-api.service >/dev/null 2>&1 || true
  systemctl restart vitrine-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : tout va bien au démarrage. Après quelques dizaines de
requêtes, une requête sur trois échoue en erreur 500 et le journal
applicatif répète « OSError: [Errno 24] Too many open files ».
Un redémarrage du service règle le problème... jusqu'à la prochaine fois.
Pour reproduire : bash /opt/vitrine/bin/vitrine-charge.sh /rapport 5 30
EOF
