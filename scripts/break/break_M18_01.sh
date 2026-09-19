#!/usr/bin/env bash
# break_M18_01.sh — panne BF18.1 (blocage invisible de « ufw status »)
# À lancer sur lab-db, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

command -v ufw >/dev/null 2>&1 || {
  echo "ufw n'est pas installé : apt install ufw" >&2; exit 1; }

SAUV=/root/.breakfix-backup
BEFORE=/etc/ufw/before.rules
mkdir -p "$SAUV"

# --- sauvegarde de l'état avant de casser ------------------------------
[ -f "$SAUV/M18_01.before.rules" ] || cp -a "$BEFORE" \
  "$SAUV/M18_01.before.rules"
ufw status verbose > "$SAUV/M18_01.ufw-status.txt" 2>/dev/null || true

# --- on s'assure que la politique « correcte » est bien en place -------
# (sinon le symptôme n'a pas de sens : la règle ALLOW doit exister)
ufw allow from 10.10.10.10 to any port 22 proto tcp   >/dev/null
ufw allow from 10.10.10.0/24 to any port 22 proto tcp >/dev/null
ufw allow from 10.10.10.11 to any port 5432 proto tcp >/dev/null
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
yes | ufw enable >/dev/null 2>&1 || true

# --- la panne : une règle DROP dans une chaîne que ufw status ignore ---
MARQUE='# lab18-maintenance'
if ! grep -q "$MARQUE" "$BEFORE"; then
  REGLE="-A ufw-before-input -p tcp --dport 5432 -j DROP $MARQUE"
  if grep -q '^-A ufw-before-input -i lo -j ACCEPT' "$BEFORE"; then
    sed -i "/^-A ufw-before-input -i lo -j ACCEPT/a $REGLE" "$BEFORE"
  else
    sed -i "0,/^COMMIT/s//$REGLE\nCOMMIT/" "$BEFORE"
  fi
fi

ufw reload >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : depuis lab-web, toute connexion vers 10.10.10.12:5432
reste sans réponse puis expire (« connection timed out »).
Sur lab-db, « sudo ufw status numbered » affiche pourtant bien la règle
5432/tcp ALLOW IN 10.10.10.11, le service écoute sur 0.0.0.0:5432, SSH
fonctionne et le ping passe.
EOF
