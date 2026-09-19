#!/usr/bin/env bash
# break_PC_3_2.sh — ticket PC.3.2 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_3_2; mkdir -p "$SAUV"
AK=/home/deploy/.ssh/authorized_keys
[ -f "$AK" ] || { echo "lance d'abord setup_P3.sh (rôle web)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
[ -f "$SAUV/$ID.authorized_keys" ] || cp -a "$AK" "$SAUV/$ID.authorized_keys"

# Rotation des clés de la CI (bonne intention) : une NOUVELLE paire a été
# générée sur lab-ops et l'ancienne clé publique a été retirée de deploy…
# mais lab-ops utilise toujours l'ancienne clé privée pour se connecter.
CIB=/var/lib/factura-ci
[ -f "$SAUV/$ID.ci_priv" ] || cp -a "$CIB/id_ed25519" "$SAUV/$ID.ci_priv"
[ -f "$SAUV/$ID.ci_pub" ]  || cp -a "$CIB/id_ed25519.pub" "$SAUV/$ID.ci_pub"

ANCIENNE=$(cut -d' ' -f2 "$CIB/id_ed25519.pub")
# on retire l'ancienne clé publique de authorized_keys
grep -vF "$ANCIENNE" "$AK" > "$AK.tmp" || true
mv "$AK.tmp" "$AK"; chown deploy:deploy "$AK"; chmod 0600 "$AK"
# on installe la NOUVELLE clé publique (celle que lab-ops n'a pas encore)
ssh-keygen -q -t ed25519 -N "" -C "ci-factura-2026@lab-ops" \
  -f "$SAUV/$ID.nouvelle" 2>/dev/null
cat "$SAUV/$ID.nouvelle.pub" >> "$AK"
chown deploy:deploy "$AK"; chmod 0600 "$AK"

cat <<'EOF'

Symptôme attendu : le pipeline de déploiement échoue à l'étape « redémarrer
l'API ». Le job affiche « deploy@lab-web: Permission denied (publickey) ».
Test : /usr/local/bin/factura-deploy
EOF
