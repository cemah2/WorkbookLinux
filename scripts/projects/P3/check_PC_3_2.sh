#!/usr/bin/env bash
# check_PC_3_2.sh — vérifie le ticket PC.3.2 (clé SSH révoquée bloque le déploiement)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.3.2 =="
SAUV=/root/.breakfix-backup; ID=PC_3_2
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

# 1. le déploiement fonctionne de nouveau, par clé
if command -v factura-deploy >/dev/null 2>&1; then
  if factura-deploy >/dev/null 2>&1; then
    ok "factura-deploy réussit : le déploiement par clé est rétabli"
  else
    ko "factura-deploy échoue encore (Permission denied publickey ?)"
  fi
else
  ko "factura-deploy introuvable"
fi

# 2. cohérence clé privée utilisée / clé publique autorisée
CIB=/var/lib/factura-ci
if [ -r "$CIB/id_ed25519" ]; then
  PUBATTENDUE=$(ssh-keygen -y -f "$CIB/id_ed25519" 2>/dev/null | cut -d' ' -f2)
  if grep -qF "$PUBATTENDUE" /home/deploy/.ssh/authorized_keys 2>/dev/null; then
    ok "la clé publique correspondant à la clé privée de la CI est autorisée"
  else
    ko "la clé privée utilisée par la CI n'a pas sa clé publique dans authorized_keys"
  fi
fi

# 3. l'API tourne (le déploiement l'a bien redémarrée)
systemctl is-active -q factura-api.service \
  && ok "factura-api actif après déploiement" || ko "factura-api n'est pas actif"

# 4. pas de contournement par mot de passe
if grep -rqsE '^\s*PasswordAuthentication\s+yes' /etc/ssh/sshd_config \
     /etc/ssh/sshd_config.d/ 2>/dev/null; then
  ko "MALUS : PasswordAuthentication a été réactivé comme contournement"
else
  ok "l'accès reste par clé uniquement (pas de contournement par mot de passe)"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
