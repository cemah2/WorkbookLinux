#!/usr/bin/env bash
# break_M11_03.sh — panne BF11.3 (service lié à 127.0.0.1)
# À lancer sur lab-web. Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DROPD=/etc/systemd/system/factura-api.service.d
mkdir -p "$SAUV"

[ -x /opt/factura/bin/factura-api.py ] || {
  echo "/opt/factura/bin/factura-api.py absent : lance setup_M11.sh" >&2
  exit 1; }

# on note qu'il n'y avait pas de drop-in avant, pour pouvoir revenir
[ -f "$SAUV/M11_03.state" ] || {
  if [ -f "$DROPD/override.conf" ]; then
    cp -a "$DROPD/override.conf" "$SAUV/M11_03.override.conf"
    printf 'dropin\n' > "$SAUV/M11_03.state"
  else
    printf 'none\n' > "$SAUV/M11_03.state"
  fi
}

mkdir -p "$DROPD"
cat > "$DROPD/override.conf" <<'EOF'
[Service]
Environment=FACTURA_BIND=127.0.0.1
EOF
chmod 0644 "$DROPD/override.conf"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl restart factura-api.service >/dev/null 2>&1 || true
fi

# le pare-feu doit rester hors de cause : l'énoncé l'interdit comme piste
for u in ufw firewalld nftables; do
  systemctl is-active --quiet "$u" 2>/dev/null && \
    systemctl stop "$u" >/dev/null 2>&1 || true
done

cat <<'EOF'

Symptôme attendu : sur lab-web, « curl http://localhost:8099/health »
répond {"status": "ok", ...}. Depuis lab-adm, « curl http://10.10.10.11:8099/
health » échoue immédiatement avec le code de retour 7. Le service est
active (running), ses journaux ne montrent aucune erreur, et personne
n'a touché au code de l'application.
EOF
