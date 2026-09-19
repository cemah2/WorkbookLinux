#!/usr/bin/env bash
# break_M23_02.sh — panne BF23.2 : subprocess avec shell=True
# Dépose ~/lab23/bf2/archiver.py et un jeu de journaux dont un nom contient
# une espace et un autre un caractère spécial du shell.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab23"
BF="$BASE/bf2"
mkdir -p /root/.breakfix-backup

rm -rf "$BF"
mkdir -p "$BF/logs" "$BF/archives"
for j in 14 15 16 17; do
  printf 'INFO demarrage\nERROR base injoignable\n' > "$BF/logs/app-2026-09-$j.log"
done
printf 'INFO rapport final valide\n' > "$BF/logs/rapport final.log"
printf 'INFO export termine\n'       > "$BF/logs/export;date.log"

cat > "$BF/archiver.py" <<'EOF'
#!/usr/bin/env python3
"""archiver.py — archive les journaux d'un répertoire : archiver.py REP DEST
Utilise tar comme on l'écrirait dans un terminal."""
import subprocess
import sys
from pathlib import Path

rep, dest = sys.argv[1], sys.argv[2]
fichiers = " ".join(str(p) for p in Path(rep).glob("*.log"))
cmd = f"tar -czf {dest} {fichiers}"
subprocess.run(cmd, shell=True)
print(f"archive écrite : {dest}")
EOF
chmod 755 "$BF/archiver.py"
chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : "$BF/archiver.py $BF/logs $BF/archives/logs.tar.gz"
affiche "archive écrite" et sort en 0, mais tar se plaint de fichiers
introuvables et l'archive ne contient pas les 6 journaux. Avec certains noms
de fichiers, une commande inattendue s'exécute.
EOF
