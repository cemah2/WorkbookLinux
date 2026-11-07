#!/usr/bin/env bash
# break_M18_04.sh — panne BF18.4 (fail2ban bannit le bastion)
# À lancer sur lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

command -v fail2ban-client >/dev/null 2>&1 || {
  echo "fail2ban n'est pas installé : apt install fail2ban" >&2; exit 1; }

SAUV=/root/.breakfix-backup
JL=/etc/fail2ban/jail.local
BASTION=10.10.10.10
mkdir -p "$SAUV"

# --- sauvegarde de l'état avant de casser ------------------------------
if [ -f "$JL" ] && [ ! -f "$SAUV/M18_04.jail.local" ]; then
  cp -a "$JL" "$SAUV/M18_04.jail.local"
fi

# --- la configuration « d'origine », volontairement sans ignoreip ------
# (c'est la cause racine : le bastion n'est pas protégé)
cat > "$JL" <<'EOF'
# Configuration fail2ban du lab.
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
# ignoreip : à compléter (c'est justement ce qui manque)

[sshd]
enabled = true
backend = systemd
EOF

systemctl restart fail2ban >/dev/null 2>&1 || true

# on laisse le démon démarrer avant de lui parler
for _ in 1 2 3 4 5 6 7 8 9 10; do
  fail2ban-client ping >/dev/null 2>&1 && break
  sleep 1
done

# --- la panne : le bastion est banni ----------------------------------
fail2ban-client set sshd banip "$BASTION" >/dev/null 2>&1 || {
  echo "impossible de bannir via fail2ban-client (jail sshd absente ?)" >&2
  exit 1; }

# --- la politique ufw, elle, reste impeccable -------------------------
if command -v ufw >/dev/null 2>&1; then
  ufw allow from "$BASTION" to any port 22 proto tcp >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : depuis lab-adm (10.10.10.10), « ssh 10.10.10.11 »
échoue immédiatement avec « Connection refused ». Depuis lab-db, la
même commande fonctionne immédiatement.
« ping 10.10.10.11 » depuis lab-adm répond, et « ufw status » sur
lab-web affiche bien 22/tcp ALLOW IN 10.10.10.10. Le service ssh est
actif et n'a pas été modifié.
EOF
