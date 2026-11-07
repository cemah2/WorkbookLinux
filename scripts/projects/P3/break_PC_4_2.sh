#!/usr/bin/env bash
# break_PC_4_2.sh — ticket PC.4.2 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_4_2; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"

# Sauvegarde l'état NTP pour la remise en état par le check si besoin.
timedatectl show -p NTP --value > "$SAUV/$ID.ntp" 2>/dev/null || true
SSL=/etc/ssl/factura
[ -f "$SSL/ca.cnf" ] || { echo "lance d'abord setup_P3.sh (rôle web)" >&2
                          exit 1; }
[ -f "$SAUV/$ID.factura.crt" ] || cp -a "$SSL/factura.lab.local.crt" \
  "$SAUV/$ID.factura.crt"

# 1. Le renouvellement automatique « de cette nuit » (mis en place après
#    PC.1.1) réémet le certificat, À L'HEURE RÉELLE : notBefore = maintenant.
openssl ca -batch -config "$SSL/ca.cnf" -notext \
  -in "$SSL/factura.lab.local.csr" -out "$SSL/factura.lab.local.crt" \
  >/dev/null 2>&1
chmod 0644 "$SSL/factura.lab.local.crt"
[ -d /run/systemd/system ] && systemctl reload nginx 2>/dev/null || true

# 2. Puis la synchro est coupée et l'horloge recule de 3 h : pour lab-web,
#    le certificat tout neuf n'est « pas encore valide » (notBefore dans
#    le futur), et tous les horodatages locaux sont en retard.
timedatectl set-ntp false 2>/dev/null || systemctl stop \
  systemd-timesyncd chrony chronyd 2>/dev/null || true
systemctl disable --now systemd-timesyncd 2>/dev/null || true
date -s "$(date -d '-3 hours' '+%Y-%m-%d %H:%M:%S')" >/dev/null

cat <<'EOF'

Symptôme attendu : depuis lab-web, les appels HTTPS vers l'API échouent
avec « certificate is not yet valid » (curl : SSL certificate problem), et
les horodatages des journaux sont en retard de trois heures sur l'heure
réelle. Personne n'a touché aux certificats à la main.
EOF
