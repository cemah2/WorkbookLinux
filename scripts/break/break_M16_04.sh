#!/usr/bin/env bash
# break_M16_04.sh — panne BF16.4 (processus en boucle, CPU saturé)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
BINL=/usr/local/sbin/vitrine-reindex
UNIT=/etc/systemd/system/vitrine-reindex.service
mkdir -p "$SAUV"

if [ ! -f "$SAUV/M16_04.etat" ]; then
  uptime > "$SAUV/M16_04.etat"
fi

# --- le brûleur de CPU --------------------------------------------------
cat > "$BINL" <<'SHEOF'
#!/usr/bin/env bash
# vitrine-reindex — reconstruction incrementale de l'index de recherche.
# Boucle de calcul : la condition de sortie n'est jamais atteinte
# (regression introduite en 2.3.1).
set -u
N="${1:-3}"
pids=()
brule() { local i=0; while :; do i=$(( (i + 7) % 1000003 )); done; }
trap 'kill "${pids[@]}" 2>/dev/null; exit 0' TERM INT
for _ in $(seq 1 "$N"); do brule & pids+=("$!"); done
wait
SHEOF
chmod 0755 "$BINL"

# --- maintenu en vie par systemd : tuer le PID ne suffit pas ------------
cat > "$UNIT" <<'EOF'
[Unit]
Description=Vitrine — reconstruction de l'index de recherche
After=vitrine-api.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/vitrine-reindex 3
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl enable --now vitrine-reindex.service >/dev/null 2>&1 || true
else
  pgrep -f "$BINL" >/dev/null 2>&1 || \
    setsid nohup "$BINL" 3 >/dev/null 2>&1 < /dev/null &
fi

cat <<'EOF'

Symptôme attendu : le site répond en 2 à 4 secondes au lieu de 40 ms.
La charge moyenne dépasse 4 sur une VM à 2 vCPU et ne redescend pas.
Un coup d'oeil rapide à « top » ne montre aucun nom de processus connu de
l'équipe applicative.
EOF
