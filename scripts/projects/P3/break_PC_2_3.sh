#!/usr/bin/env bash
# break_PC_2_3.sh — ticket PC.2.3 (lab-ops)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_2_3; mkdir -p "$SAUV"
S=/usr/local/sbin/factura-backup
[ -f "$S" ] || { echo "lance d'abord setup_P3.sh (rôle ops)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
[ -f "$SAUV/$ID.factura-backup" ] || cp -a "$S" "$SAUV/$ID.factura-backup"

# « Simplification » du script lors de la migration des données vers
# /srv/factura/data (l'ancien chemin était /srv/factura/donnees).
cat > "$S" <<'EOF'
#!/usr/bin/env bash
# factura-backup — archive quotidienne des données Factura
# Conserve 7 archives dans /var/backups/factura.
SRC=/srv/factura/donnees
DEST=/var/backups/factura
ARCH="$DEST/factura-$(date +%Y%m%d-%H%M).tar.gz"
mkdir -p "$DEST"
tar -czf "$ARCH" -C "$(dirname "$SRC")" "$(basename "$SRC")" 2>/dev/null
ls -1t "$DEST"/factura-*.tar.gz | tail -n +8 | xargs -r rm -f
echo "Sauvegarde OK : $ARCH ($(du -h "$ARCH" | cut -f1))"
exit 0
EOF
chmod 0755 "$S"
# Cinq nuits de « succès »
for j in 5 4 3 2 1; do
  A="/var/backups/factura/factura-$(date -d "$j days ago" +%Y%m%d)-0200.tar.gz"
  tar -czf "$A" -C /srv/factura donnees 2>/dev/null || true
  touch -d "$j days ago 02:00" "$A"
done
[ -d /run/systemd/system ] && systemctl start factura-backup.service \
  >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : « systemctl list-timers » montre factura-backup.timer
qui tourne chaque nuit, le journal dit « Sauvegarde OK », et pourtant la
compta n'a pas pu restaurer la facture demandée : l'archive est vide.
EOF
