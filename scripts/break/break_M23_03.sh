#!/usr/bin/env bash
# break_M23_03.sh — panne BF23.3 : fuite de descripteurs de fichiers
# Dépose ~/lab23/bf3/compte-erreurs.py et 1500 journaux à analyser.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab23"
BF="$BASE/bf3"
mkdir -p /root/.breakfix-backup

rm -rf "$BF"
mkdir -p "$BF/logs"
for i in $(seq -w 1 1500); do
  printf 'INFO ok\nERROR panne %s\nINFO fin\n' "$i" > "$BF/logs/svc-$i.log"
done

cat > "$BF/compte-erreurs.py" <<'EOF'
#!/usr/bin/env python3
"""compte-erreurs.py — compte les lignes ERROR de chaque journal d'un
répertoire. Ouvre tout d'abord (« pour aller plus vite »), lit ensuite."""
import sys
from pathlib import Path

rep = Path(sys.argv[1])
ouverts = {}
for p in sorted(rep.glob("*.log")):
    ouverts[p.name] = open(p)

total = 0
for nom, f in ouverts.items():
    n = sum(1 for ligne in f if "ERROR" in ligne)
    total += n
print(f"{len(ouverts)} fichiers, {total} erreurs")
EOF
chmod 755 "$BF/compte-erreurs.py"
chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : "$BF/compte-erreurs.py $BF/logs" s'arrête avec
"OSError: [Errno 24] Too many open files" avant d'avoir compté quoi que ce
soit. Le même script fonctionnait quand le répertoire avait 200 journaux.
EOF
