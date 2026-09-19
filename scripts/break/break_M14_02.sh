#!/usr/bin/env bash
# break_M14_02.sh — panne BF14.2 (le rapport hebdo n'arrive plus,
#                   et rien n'est en erreur)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
UD=/etc/systemd/system
mkdir -p "$SAUV"

[ -d /run/systemd/system ] || {
  echo "systemd ne pilote pas cette machine : BF14.2 inapplicable" >&2
  exit 1; }
[ -x /opt/factura/bin/factura-rapport.sh ] || {
  echo "/opt/factura/bin/factura-rapport.sh absent : lance setup_M14.sh" >&2
  exit 1; }

# --- le service, parfaitement sain --------------------------------------
cat > "$UD/factura-hebdo.service" <<'EOF'
[Unit]
Description=Factura - rapport hebdomadaire de direction

[Service]
Type=oneshot
User=factura
Group=factura
Environment=FACTURA_RAPPORTS=/srv/factura/etat
ExecStart=/opt/factura/bin/factura-rapport.sh

[Install]
WantedBy=multi-user.target
EOF

# --- le timer, sain lui aussi -------------------------------------------
cat > "$UD/factura-hebdo.timer" <<'EOF'
[Unit]
Description=Declenche le rapport hebdomadaire factura

[Timer]
OnCalendar=Mon *-*-* 06:45:00
Persistent=true
AccuracySec=5min

[Install]
WantedBy=timers.target
EOF

chmod 0644 "$UD/factura-hebdo.service" "$UD/factura-hebdo.timer"
systemctl daemon-reload

# --- l'état « d'avant », pour mémoire -----------------------------------
cat > "$SAUV/M14_02.etat" <<'EOF'
# état attendu (workbook module 14)
# factura-hebdo.timer   : enabled + active
# factura-hebdo.service : disabled (c'est le timer qui le déclenche)
EOF

# --- le geste fautif ----------------------------------------------------
# Un prédécesseur a voulu « activer la tâche » et a activé le SERVICE.
# Puis, voyant qu'il tournait à chaque démarrage, il a désactivé… le
# timer. Résultat : plus aucune planification, et « systemctl is-enabled
# factura-hebdo » (sans suffixe, donc .service) répond « enabled ».
systemctl disable --now factura-hebdo.timer >/dev/null 2>&1 || true
systemctl enable factura-hebdo.service >/dev/null 2>&1 || true
systemctl stop factura-hebdo.service >/dev/null 2>&1 || true
systemctl reset-failed factura-hebdo.service >/dev/null 2>&1 || true

# On efface l'horodatage de persistance pour que rien ne rattrape.
rm -f /var/lib/systemd/timers/stamp-factura-hebdo.timer

cat <<'EOF'

Symptôme attendu : aucun rapport hebdomadaire depuis trois semaines.
« systemctl status factura-hebdo.service » affiche inactive (dead),
aucune unité n'est en failed, « systemctl is-enabled factura-hebdo »
répond enabled, et le journal ne contient rien d'anormal.
Le script produit bien un rapport quand on le lance à la main.
EOF
