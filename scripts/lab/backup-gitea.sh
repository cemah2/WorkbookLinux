#!/usr/bin/env bash
# backup-gitea.sh — sauvegarde complète de Gitea (lab-git) avec `gitea dump`
# (base SQLite, dépôts, LFS, app.ini, avatars) dans un zip horodaté, puis
# rotation. Lancé par gitea-backup.timer (quotidien) ou à la main :
#   sudo bash /usr/local/sbin/backup-gitea.sh
# Restauration : voir chapitre 0.8 (« Sauvegarder et restaurer »).
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/gitea}"
KEEP="${KEEP:-7}"                          # nombre de dumps conservés
GITEA_BIN="${GITEA_BIN:-/usr/local/bin/gitea}"
GITEA_ETC="${GITEA_ETC:-/etc/gitea}"
GITEA_WORK="${GITEA_WORK:-/var/lib/gitea}"
GITEA_USER="${GITEA_USER:-git}"

[ "$(id -u)" -eq 0 ] || { echo "lance-moi avec sudo" >&2; exit 1; }
[ -x "$GITEA_BIN" ] || { echo "binaire absent : $GITEA_BIN" >&2; exit 1; }

install -d -m 750 -o "$GITEA_USER" -g "$GITEA_USER" "$BACKUP_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/gitea-dump-$stamp.zip"

# gitea dump doit tourner sous l'utilisateur de Gitea, avec le même
# app.ini et le même WORK_DIR, sinon il ne trouve ni la base ni les dépôts.
# Le service peut rester actif : SQLite est copié via une sauvegarde
# cohérente et les dépôts sont lus en place.
su -s /bin/bash "$GITEA_USER" -c \
  "cd $GITEA_WORK && GITEA_WORK_DIR=$GITEA_WORK $GITEA_BIN dump \
     --config $GITEA_ETC/app.ini --type zip --file $out" \
  > /dev/null

size="$(du -h "$out" | cut -f1)"
echo "dump : $out ($size)"

# Rotation : on garde les KEEP plus récents.
ls -1t "$BACKUP_DIR"/gitea-dump-*.zip 2>/dev/null \
  | tail -n +"$((KEEP + 1))" \
  | while read -r old; do rm -f -- "$old"; echo "supprimé : $old"; done

# Contrôle : le zip est lisible et contient bien la base.
unzip -l "$out" | grep -q 'gitea-db.sql' \
  || { echo "dump incomplet : gitea-db.sql absent" >&2; exit 1; }
n="$(ls -1 "$BACKUP_DIR"/gitea-dump-*.zip | wc -l)"
echo "OK  $n dump(s) dans $BACKUP_DIR"
