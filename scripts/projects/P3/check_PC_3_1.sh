#!/usr/bin/env bash
# check_PC_3_1.sh — vérifie le ticket PC.3.1 (compte deploy compromis)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.3.1 =="
SAUV=/root/.breakfix-backup; ID=PC_3_1
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
AK=/home/deploy/.ssh/authorized_keys

# 1. la porte dérobée : clé étrangère retirée
grep -qF 'attaquant@inconnu' "$AK" 2>/dev/null \
  && ko "la clé publique étrangère est toujours dans $AK" \
  || ok "clé publique étrangère retirée de authorized_keys"

# 2. la clé LÉGITIME de la CI est toujours là (sinon le déploiement casse)
if [ -r /var/lib/factura-ci/id_ed25519.pub ]; then
  grep -qF "$(cut -d' ' -f2 /var/lib/factura-ci/id_ed25519.pub)" "$AK" \
    && ok "la clé de la CI est préservée" \
    || ko "la clé de la CI a été supprimée avec le reste (déploiement cassé)"
fi

# 3. la tâche cron malveillante
if crontab -u deploy -l 2>/dev/null | grep -q '198.51.100.7'; then
  ko "la tâche cron malveillante de deploy est toujours active"
else
  ok "crontab de deploy nettoyé"
fi

# 4. contention : mot de passe et auth par mot de passe
#    (valeur EFFECTIVE : sans directive, le défaut d'OpenSSH est « yes »)
PA=$(sshd -T 2>/dev/null | awk '/^passwordauthentication / {print $2}')
if [ -z "$PA" ]; then
  grep -rqsE '^\s*PasswordAuthentication\s+yes' /etc/ssh/sshd_config \
    /etc/ssh/sshd_config.d/ && PA=yes || PA=inconnu
fi
if [ "$PA" = "no" ]; then
  ok "authentification SSH par mot de passe désactivée (sshd -T : no)"
else
  ko "PasswordAuthentication effectif = $PA (sshd -T) : « no » attendu"
fi
ST=$(passwd -S deploy 2>/dev/null | awk '{print $2}')
case "$ST" in
  L|LK) ok "le compte deploy a son mot de passe verrouillé ($ST)" ;;
  *) ko "le mot de passe de deploy n'est pas verrouillé (passwd -l deploy)" ;;
esac

# 5. la sonde de déploiement fonctionne toujours (par clé)
if command -v factura-deploy >/dev/null 2>&1; then
  factura-deploy >/dev/null 2>&1 \
    && ok "le déploiement par clé fonctionne encore" \
    || ko "le déploiement par clé ne fonctionne plus (as-tu cassé l'accès CI ?)"
fi

# 6. préservation des preuves avant nettoyage
PREUVE=0
for g in "$SAUV/preuves-PC3*" "$HOME/astreinte/preuves/*" \
         '/home/*/astreinte/preuves/*'; do
  compgen -G "$g" >/dev/null && PREUVE=1
done
if [ "$PREUVE" -eq 1 ]; then
  ok "des preuves ont été collectées avant remédiation"
else
  ko "aucune preuve collectée (auth.log, crontab, authorized_keys attendus)"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || note "la VM a redémarré (acceptable si tracé : rotation de secrets)"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
