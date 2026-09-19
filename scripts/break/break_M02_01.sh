#!/usr/bin/env bash
# break_M02_01.sh — panne BF2.1 (espace occupé par un fichier supprimé ouvert)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

MNT=/srv/appdata
CIBLE="$MNT/incoming/ingest.dat"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

findmnt -n "$MNT" >/dev/null 2>&1 || {
  echo "$MNT n'est pas monté : lance d'abord setup_M02.sh" >&2; exit 1; }

# --- le collecteur d'ingestion : ouvre son fichier une fois, le remplit ---
cat > /usr/local/sbin/lab-ingest <<'EOF'
#!/usr/bin/env bash
# lab-ingest — simulacre de collecteur d'ingestion.
# Ouvre son fichier de travail une seule fois et ne le rouvre jamais.
set -u
CIBLE="${1:-/srv/appdata/incoming/ingest.dat}"
exec 3>>"$CIBLE"
dd if=/dev/urandom bs=1M count=400 status=none >&3 2>/dev/null || true
while :; do
  printf '%s lot ingere\n' "$(date -Is)" >&3 2>/dev/null || true
  sleep 5
done
EOF
chmod 755 /usr/local/sbin/lab-ingest

mkdir -p "$MNT/incoming"

# --- idempotence : on repart toujours d'un état propre ------------------
printf 'panne BF2.1 posée le %s\n' "$(date -Is)" > "$SAUV/M02_01.marqueur"
echo "  (préparation, une trentaine de secondes)" >&2

if [ -d /run/systemd/system ]; then
  systemctl stop lab-ingest.service >/dev/null 2>&1 || true
fi
pkill -f "^bash /usr/local/sbin/lab-ingest $CIBLE" \
  >/dev/null 2>&1 || true
sleep 1
rm -f -- "$CIBLE"

if [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/lab-ingest.service <<EOF
[Unit]
Description=Collecteur d'ingestion (lab)

[Service]
ExecStart=/usr/local/sbin/lab-ingest $CIBLE
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now lab-ingest.service >/dev/null 2>&1
else
  setsid nohup /usr/local/sbin/lab-ingest "$CIBLE" \
    >/dev/null 2>&1 </dev/null &
fi

# on attend que le système de fichiers soit réellement saturé
for _ in $(seq 1 90); do
  pct=$(df --output=pcent "$MNT" | tail -1 | tr -dc '0-9')
  [ "${pct:-0}" -ge 97 ] && break
  sleep 1
done

# le fichier disparaît de l'arborescence, pas du système de fichiers
rm -f -- "$CIBLE"

cat <<'EOF'

Symptôme attendu : /srv/appdata est à 100 % pour df, alors que du -sh
/srv/appdata ne compte que quelques dizaines de kilo-octets et qu'aucun
gros fichier n'apparaît dans ls -laR. Les écritures échouent avec
"No space left on device".
EOF
