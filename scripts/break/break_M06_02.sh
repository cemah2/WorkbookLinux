#!/usr/bin/env bash
# break_M06_02.sh — BF6.2 : la sauvegarde nocturne s'archive elle-même.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

BK=/root/.breakfix-backup
APP=/srv/factura
BIN=/usr/local/bin/factura-backup.sh
mkdir -p "$BK"

# --- données applicatives (créées si absentes) ---------------------------
mkdir -p "$APP"/{app/src,conf,logs,uploads}
for i in $(seq 1 40); do
  [ -f "$APP/app/src/mod_$i.py" ] || \
    printf 'def h_%d(r):\n    return %d\n' "$i" "$i" > "$APP/app/src/mod_$i.py"
done
[ -f "$APP/conf/factura.conf" ] || \
  printf 'listen = 0.0.0.0:8080\ndata_dir = /srv/factura\n' \
    > "$APP/conf/factura.conf"
for f in access error; do
  [ -s "$APP/logs/$f.log" ] || \
    for i in $(seq 1 6000); do
      printf '2026-09-17 04:00:00 factura %s ligne %d\n' "$f" "$i"
    done > "$APP/logs/$f.log"
done
[ -f "$APP/uploads/piece.bin" ] || \
  head -c 2097152 /dev/urandom > "$APP/uploads/piece.bin"

# --- le script fautif ----------------------------------------------------
[ -f "$BIN" ] && [ ! -f "$BK/factura-backup.sh" ] && \
  cp -a "$BIN" "$BK/factura-backup.sh"
cat > "$BIN" <<'EOF'
#!/usr/bin/env bash
# factura-backup.sh — sauvegarde nocturne de l'application factura
# (script maison, repris de l'ancienne équipe)
DEST=/srv/factura/backup
STAMP=$(date +%F-%H%M%S)
mkdir -p "$DEST"

tar -czf "$DEST/factura-$STAMP.tar.gz" /srv/factura
RC=$?

echo "sauvegarde terminee : $DEST/factura-$STAMP.tar.gz (code $RC)"
exit $RC
EOF
chmod 755 "$BIN"

# --- on rejoue trois nuits, en laissant l'application écrire --------------
rm -rf "$APP/backup"
for n in 1 2 3; do
  ( for i in $(seq 1 400); do
      printf '2026-09-1%d 04:00:%02d factura access requete %d\n' \
        "$n" "$((i % 60))" "$i" >> "$APP/logs/access.log"
      sleep 0.02
    done ) &
  ECRIVAIN=$!
  "$BIN" >/dev/null 2>&1 || true
  kill "$ECRIVAIN" 2>/dev/null || true
  wait "$ECRIVAIN" 2>/dev/null || true
  # une nuit = un horodatage distinct, sinon la seconde archive écrase
  [ "$n" -eq 3 ] || sleep 1.2
done

echo
echo "Symptôme attendu :"
echo "  sudo $BIN met de plus en plus de temps, renvoie 1, et"
echo "  /srv/factura/backup grossit à chaque exécution."
