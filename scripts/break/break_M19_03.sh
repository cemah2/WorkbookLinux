#!/usr/bin/env bash
# break_M19_03.sh — panne BF19.3 (disque plein : fichier supprimé encore
#                   ouvert par un processus)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DATA=/srv/vitrine/data
GARDE=/usr/local/sbin/vitrine-rotation
mkdir -p "$SAUV"

mountpoint -q "$DATA" || {
  echo "$DATA n'est pas monté : lance setup_M19.sh" >&2; exit 1; }

# --- déjà cassé ? on ne rejoue pas --------------------------------------
if pgrep -f "$GARDE" >/dev/null 2>&1; then
  cat <<'EOF'

Symptôme attendu : toute écriture échoue avec « OSError: [Errno 28] No
space left on device ». « df -h /srv/vitrine/data » affiche 100 %, alors
que « du -xsh /srv/vitrine/data » ne trouve que quelques Mo.
EOF
  exit 0
fi

if [ ! -f "$SAUV/M19_03.etat" ]; then
  df -h "$DATA" > "$SAUV/M19_03.etat"
fi

# --- le processus qui retient l'espace ----------------------------------
cat > "$GARDE" <<'PYEOF'
#!/usr/bin/env python3
"""vitrine-rotation — agent d'archivage des journaux de vitrine.

Ouvre son fichier de travail, l'utilise, puis le retire du répertoire
(il continue de s'en servir par son descripteur). Version 1.4.
"""
import os
import sys
import time

CIBLE = sys.argv[1] if len(sys.argv) > 1 else "/srv/vitrine/data"
chemin = os.path.join(CIBLE, "rotation-en-cours.tmp")
f = open(chemin, "wb")
bloc = b"a" * (1024 * 1024)
try:
    while True:
        f.write(bloc)
        f.flush()
except OSError:
    pass
try:
    os.unlink(chemin)
except OSError:
    pass
while True:
    time.sleep(3600)
PYEOF
chmod 0755 "$GARDE"

setsid nohup "$GARDE" "$DATA" >/dev/null 2>&1 < /dev/null &
sleep 4

if [ -d /run/systemd/system ]; then
  systemctl restart vitrine-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : toute écriture échoue avec « OSError: [Errno 28] No
space left on device ». « df -h /srv/vitrine/data » affiche 100 %, alors
que « du -xsh /srv/vitrine/data » ne trouve que quelques Mo.
Pour reproduire : curl -s http://127.0.0.1:8080/commande
EOF
