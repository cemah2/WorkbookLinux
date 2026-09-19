#!/usr/bin/env bash
# break_M14_04.sh — panne BF14.4 (archive au nom absurde, ou pas d'archive)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CIBLE=/etc/cron.d/factura-archivage
BACK=/srv/factura/backups
mkdir -p "$SAUV" "$BACK"

[ -d /srv/factura/data ] || {
  echo "/srv/factura/data absent : lance setup_M14.sh" >&2; exit 1; }

if [ -f "$CIBLE" ] && [ ! -f "$SAUV/M14_04.cron" ]; then
  cp -a "$CIBLE" "$SAUV/M14_04.cron"
fi

# --- la ligne fautive ----------------------------------------------------
# Un collègue a « simplifié » l'archivage en remplaçant l'appel au script
# par la commande tar directement dans la crontab. La commande est
# parfaitement valide dans un shell. Dans une crontab, elle ne l'est pas.
cat > "$CIBLE" <<'EOF'
# Archivage factura (simplifie le 17/09 : plus besoin du script wrapper)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
*/2 * * * * factura tar czf /srv/factura/backups/data-$(date +%F).tgz /srv/factura/data 2>&1 | logger -t factura-archivage
EOF
chmod 0644 "$CIBLE"
chown root:root "$CIBLE"

# on nettoie les archives au nom tronqué d'une exécution précédente
find "$BACK" -maxdepth 1 -name 'data-' -delete 2>/dev/null || true
find "$BACK" -maxdepth 1 -name 'data-$*' -delete 2>/dev/null || true

# la preuve que ça marchait avant : une archive d'hier, bien nommée
AR="$BACK/data-$(date -d yesterday '+%F').tgz"
[ -f "$AR" ] || tar czf "$AR" -C /srv/factura data 2>/dev/null || true
chown -R factura:factura "$BACK" 2>/dev/null || true

if [ -d /run/systemd/system ]; then
  systemctl reload-or-restart cron.service >/dev/null 2>&1 \
    || systemctl reload-or-restart crond.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : depuis la modification de la planification, plus aucune
archive n'apparaît dans /srv/factura/backups. Celle d'hier, antérieure au
changement, est bien là. La commande copiée-collée dans un shell fonctionne.
Le journal contient une ligne de cron mentionnant la tâche, suivie d'une
erreur de syntaxe du shell.
À observer dans les deux minutes : journalctl -t factura-archivage -f
EOF
