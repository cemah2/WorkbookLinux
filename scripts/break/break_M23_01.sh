#!/usr/bin/env bash
# break_M23_01.sh — panne BF23.1 : marche dans le shell, plante sous timer
# Dépose ~/lab23/bf1/export-rapport.py, un notifieur dans ~/.local/bin,
# et une unité systemd + timer qui lancent le script toutes les 2 minutes.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab23"
BF="$BASE/bf1"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -d "$BASE/venv" ] || { echo "$BASE/venv absent : lance setup_M23.sh" >&2; \
  exit 1; }

for u in export-rapport.service export-rapport.timer; do
  if [ -f "/etc/systemd/system/$u" ] && [ ! -f "$SAUV/M23_01.$u" ]; then
    cp -a "/etc/systemd/system/$u" "$SAUV/M23_01.$u"
  fi
done

# --- données et notifieur ------------------------------------------------
rm -rf "$BF"
mkdir -p "$BF/conf" "$BF/rapports" "$LAB_HOME/.local/bin"
cat > "$BF/conf/export.yaml" <<'EOF'
titre: Rapport quotidien factura
sites:
  - nom: boutique
    url: http://10.10.10.11/
  - nom: gitea
    url: http://10.10.10.14:3000/
EOF
cat > "$LAB_HOME/.local/bin/notifier" <<'EOF'
#!/usr/bin/env bash
# notifieur maison : en prod il pousse vers le chat, ici il journalise.
logger -t notifier "$*"
echo "notifié : $*"
EOF
chmod 755 "$LAB_HOME/.local/bin/notifier"

# --- le script fautif ----------------------------------------------------
cat > "$BF/export-rapport.py" <<'EOF'
#!/usr/bin/env python3
"""export-rapport.py — génère le rapport quotidien depuis conf/export.yaml.
Testé à la main : « ça marche chez moi ». """
import subprocess
from datetime import date

import yaml

with open("conf/export.yaml") as f:
    conf = yaml.safe_load(f)

lignes = [f"# {conf['titre']} — {date.today()}", ""]
for site in conf["sites"]:
    lignes.append(f"* {site['nom']} : {site['url']}")

sortie = f"rapports/rapport-{date.today()}.md"
with open(sortie, "w") as f:
    f.write("\n".join(lignes) + "\n")

subprocess.run(["notifier", f"rapport écrit : {sortie}"], check=True)
print(f"OK {sortie}")
EOF
chmod 755 "$BF/export-rapport.py"
chown -R "$LAB_USER":"$LAB_USER" "$BF" "$LAB_HOME/.local"

# --- l'unité et le timer ---------------------------------------------------
cat > /etc/systemd/system/export-rapport.service <<EOF
[Unit]
Description=Export du rapport quotidien factura

[Service]
Type=oneshot
User=$LAB_USER
ExecStart=/usr/bin/python3 $BF/export-rapport.py
EOF
cat > /etc/systemd/system/export-rapport.timer <<'EOF'
[Unit]
Description=Export du rapport toutes les 2 minutes (lab)

[Timer]
OnCalendar=*:0/2
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now export-rapport.timer >/dev/null 2>&1
systemctl start export-rapport.service >/dev/null 2>&1 || true

cat <<EOF

Symptôme attendu : lancé à la main depuis ~/lab23/bf1 avec le venv du module
activé, export-rapport.py écrit son rapport et affiche "OK". Lancé par
export-rapport.timer, il échoue à chaque fois : "systemctl status
export-rapport.service" est en failed et aucun rapport n'apparaît dans
$BF/rapports/.
EOF
