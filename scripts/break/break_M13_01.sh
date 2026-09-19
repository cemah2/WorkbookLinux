#!/usr/bin/env bash
# break_M13_01.sh — panne BF13.1 (/var plein, la rotation ne tourne plus)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CONF=/etc/logrotate.d/factura
LOGD=/var/log/factura
mkdir -p "$SAUV"

[ -d "$LOGD" ] || { echo "$LOGD absent : lance setup_M13.sh" >&2; exit 1; }

# --- 1. sauvegarde de l'existant ---------------------------------------
if [ -e "$CONF" ] && [ ! -f "$SAUV/M13_01.logrotate" ]; then
  cp -a "$CONF" "$SAUV/M13_01.logrotate"
fi

# --- 2. une configuration de rotation « en place depuis six mois » ------
# Son contenu est parfaitement valide. Son mode, lui, ne l'est pas.
cat > "$CONF" <<'EOF'
/var/log/factura/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 factura adm
    su root adm
}
EOF
chown root:root "$CONF"
chmod 0666 "$CONF"

# --- 3. l'état de rotation ne connaît pas ces fichiers ------------------
for ETAT in /var/lib/logrotate/status /var/lib/logrotate.status; do
  [ -f "$ETAT" ] || continue
  [ -f "$SAUV/M13_01.$(basename "$ETAT")" ] || \
    cp -a "$ETAT" "$SAUV/M13_01.$(basename "$ETAT")"
  sed -i '\#/var/log/factura/#d' "$ETAT"
done

# --- 4. six mois de journaux jamais tournés ----------------------------
# On remplit la partition de /var en laissant juste de quoi travailler.
CIBLE="$LOGD/app.log"
LIBRE_KO=$(df -Pk /var/log | awk 'NR==2 {print $4}')
GARDE_KO=$((350 * 1024))                  # on laisse 350 Mo
PLAFOND_KO=$((6 * 1024 * 1024))           # jamais plus de 6 Go d'un coup
A_ECRIRE_KO=$((LIBRE_KO - GARDE_KO))
[ "$A_ECRIRE_KO" -gt "$PLAFOND_KO" ] && A_ECRIRE_KO=$PLAFOND_KO

if [ "$A_ECRIRE_KO" -gt 51200 ]; then
  echo "remplissage de $LOGD (${A_ECRIRE_KO} Ko)..." >&2
  DEPART=$(stat -c %s "$CIBLE" 2>/dev/null || echo 0)
  # fallocate alloue réellement les blocs (pas de fichier creux) : le
  # df doit bouger, sinon la panne n'en est pas une.
  if ! fallocate -o "$DEPART" -l "${A_ECRIRE_KO}K" "$CIBLE" 2>/dev/null; then
    dd if=/dev/zero bs=1M count=$((A_ECRIRE_KO / 1024)) status=none \
       >> "$CIBLE"
  fi
fi
chown factura:adm "$CIBLE" 2>/dev/null || true
chmod 0640 "$CIBLE"

# --- 5. le timer, lui, tourne bien -------------------------------------
if [ -d /run/systemd/system ]; then
  systemctl enable --now logrotate.timer >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : « df -h » montre le système de fichiers de /var à plus
de 95 %, /var/log/factura pèse plusieurs gigaoctets, et l'application
renvoie des erreurs 500 à l'écriture. Le timer logrotate est pourtant
actif et sa dernière exécution date de cette nuit.
EOF
