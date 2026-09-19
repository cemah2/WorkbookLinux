#!/usr/bin/env bash
# break_M14_03.sh — panne BF14.3 (compteur de factures incohérent)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CIBLE=/etc/cron.d/factura-compteur
CPT=/srv/factura/etat/compteur.txt
mkdir -p "$SAUV"

[ -x /opt/factura/bin/factura-compteur.sh ] || {
  echo "/opt/factura/bin/factura-compteur.sh absent : lance setup_M14.sh" >&2
  exit 1; }

if [ -f "$CIBLE" ] && [ ! -f "$SAUV/M14_03.cron" ]; then
  cp -a "$CIBLE" "$SAUV/M14_03.cron"
fi
if [ -f "$CPT" ] && [ ! -f "$SAUV/M14_03.compteur" ]; then
  cp -a "$CPT" "$SAUV/M14_03.compteur"
fi

# --- la planification fautive -------------------------------------------
# Toutes les minutes, un traitement qui dure plus d'une minute, sans
# aucun verrou. En production la cadence était horaire pour un traitement
# de 40 à 90 minutes : même configuration, échelle réduite.
cat > "$CIBLE" <<'EOF'
# Cumul des factures traitees.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
FACTURA_LENTEUR=75
* * * * * factura /opt/factura/bin/factura-compteur.sh 2>&1 | logger -t factura-compteur
EOF
chmod 0644 "$CIBLE"
chown root:root "$CIBLE"

# --- on remet le compteur dans un état de départ crédible ---------------
echo -n 4820 > "$CPT"
chown factura:factura "$CPT"
chmod 0664 "$CPT"

# trace « d'hier » : une valeur supérieure, pour rendre la régression
# visible dès la première anomalie.
printf '%s valeur de cloture : 5340\n' \
  "$(date -d 'yesterday 23:59' '+%F %T')" \
  > /srv/factura/etat/compteur.veille
chown factura:factura /srv/factura/etat/compteur.veille

if [ -d /run/systemd/system ]; then
  systemctl reload-or-restart cron.service >/dev/null 2>&1 \
    || systemctl reload-or-restart crond.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : /srv/factura/etat/compteur.txt devient incohérent au
bout de quelques minutes — valeur inférieure à celle de la veille
(/srv/factura/etat/compteur.veille), ou deux nombres collés, ou fichier
vide. Le code retour du traitement reste 0 et le script n'a pas changé.
Surveille-le avec : watch -n 5 'cat /srv/factura/etat/compteur.txt; echo'
EOF
