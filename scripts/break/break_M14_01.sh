#!/usr/bin/env bash
# break_M14_01.sh — panne BF14.1 (la collecte de nuit ne produit plus rien)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CIBLE=/etc/cron.d/factura-collecte
LOG=/var/log/factura/collecte.log
mkdir -p "$SAUV"

[ -x /opt/factura/bin/factura-collecte.sh ] || {
  echo "/opt/factura/bin/factura-collecte.sh absent : lance setup_M14.sh" >&2
  exit 1; }

# On sauvegarde la version saine du fichier, une seule fois.
if [ -f "$CIBLE" ] && [ ! -f "$SAUV/M14_01.cron" ]; then
  cp -a "$CIBLE" "$SAUV/M14_01.cron"
fi

# --- la version « d'avant », celle qui marchait --------------------------
# Elle contenait une ligne PATH incluant /usr/local/bin, là où vit
# l'utilitaire factura-inventaire appelé par le script. On la conserve
# pour référence dans la sauvegarde, elle n'est PAS installée.
cat > "$SAUV/M14_01.reference" <<'EOF'
# version d'origine (pour mémoire, workbook module 14)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
*/5 * * * * factura /opt/factura/bin/factura-collecte.sh 2>&1 | logger -t factura-collecte
EOF

# --- la version cassée ---------------------------------------------------
# Un collègue a « aligné la tâche sur le PATH standard de cron » : il a
# remplacé la ligne PATH d'origine par le PATH par défaut du démon.
cat > "$CIBLE" <<'EOF'
# Collecte periodique factura.
# (PATH aligne sur le PATH standard de cron le 17/09)
PATH=/usr/bin:/bin
MAILTO=""
*/5 * * * * factura /opt/factura/bin/factura-collecte.sh 2>&1 | logger -t factura-collecte
EOF
chmod 0644 "$CIBLE"
chown root:root "$CIBLE"

# Le journal applicatif s'arrête hier soir : on lui donne un passé crédible.
touch "$LOG"
if ! grep -q 'collecte ok' "$LOG" 2>/dev/null; then
  for h in 20 21 22 23; do
    printf '%s collecte ok : 200 enregistrements\n' \
      "$(date -d "yesterday $h:03" '+%F %T')" >> "$LOG"
  done
fi
chown factura:factura "$LOG"
chmod 0664 "$LOG"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl reload-or-restart cron.service >/dev/null 2>&1 \
    || systemctl reload-or-restart crond.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : /var/log/factura/collecte.log n'a plus une seule ligne
depuis hier soir. La tâche est bien présente, cron tourne, et le script
fonctionne quand on le lance à la main, y compris avec
« sudo -u factura /opt/factura/bin/factura-collecte.sh ».
Attends cinq minutes (ou moins) avant de commencer le diagnostic.
EOF
