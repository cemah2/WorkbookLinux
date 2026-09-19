#!/usr/bin/env bash
# break_M16_02.sh — panne BF16.2 (le journal systemd a mangé 4 Go)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
#
# Le volume est écrit par journald lui-même : des fichiers .journal
# fabriqués à la main seraient ignorés par journalctl --disk-usage, et
# l'exercice n'aurait aucun sens.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DROPD=/etc/systemd/journald.conf.d
DROP="$DROPD/99-debug-heritage.conf"
CIBLE_GO="${TAILLE_GO:-4}"
mkdir -p "$SAUV" "$DROPD"

[ -d /run/systemd/system ] || {
  echo "systemd ne pilote pas cette machine : panne inapplicable" >&2
  exit 1; }

LIBRE_GO=$(df -BG --output=avail /var | awk 'NR==2 {gsub("G","");print $1}')
if [ "$LIBRE_GO" -lt $((CIBLE_GO + 4)) ]; then
  echo "Il faut au moins $((CIBLE_GO + 4)) Go libres sur /var " \
       "(actuellement ${LIBRE_GO} Go)." >&2
  echo "Relance avec TAILLE_GO=1 sudo bash break_M16_02.sh" >&2
  exit 1
fi

# --- 1. la configuration « d'un prédécesseur pressé » -------------------
[ -f "$DROP" ] && [ ! -f "$SAUV/M16_02.journald.conf" ] && \
  cp -a "$DROP" "$SAUV/M16_02.journald.conf"

cat > "$DROP" <<'EOF'
# Ajouté pour une session de debug (ticket INC-3901). À retirer.
[Journal]
Storage=persistent
SystemMaxUse=8G
SystemMaxFileSize=256M
RateLimitIntervalSec=0
RateLimitBurst=0
EOF
chmod 0644 "$DROP"

mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
systemctl restart systemd-journald
journalctl --flush >/dev/null 2>&1 || true

# --- 2. on remplit réellement le journal --------------------------------
echo "écriture de ${CIBLE_GO} Go dans le journal (plusieurs minutes)..." >&2
python3 - "$CIBLE_GO" <<'PYEOF' | systemd-cat -t factura-debug -p info
import base64
import os
import sys

cible = int(sys.argv[1]) * 1024 * 1024 * 1024
ecrit = 0
# Des données incompressibles : journald compresse les champs volumineux,
# du texte répétitif ne consommerait presque rien sur disque.
while ecrit < cible:
    bloc = base64.b64encode(os.urandom(3000)).decode()
    ligne = "trace debug INC-3901 payload=%s\n" % bloc
    sys.stdout.write(ligne)
    ecrit += len(ligne)
    if ecrit % (200 * 1024 * 1024) < len(ligne):
        sys.stdout.flush()
PYEOF

sync
journalctl --rotate >/dev/null 2>&1 || true
sleep 2

cat <<'EOF'

Symptôme attendu : « df -h /var » affiche moins de 1 Go libre, et
« du -sh /var/log/* » désigne /var/log/journal comme premier consommateur.
Aucun fichier .log n'est anormalement gros.
EOF
