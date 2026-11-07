#!/usr/bin/env bash
# break_M31_01.sh — panne BF31.1 (binaire dépouillé, sans pointeurs de cadre,
# adresses du noyau masquées)
# À lancer sur lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SRC=/usr/local/src/lab31/lab31-calcul.c
B=/usr/local/bin/lab31-calcul
[ -f "$SRC" ] && [ -x "$B" ] || { echo "setup_M31.sh d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M31_01.lab31-calcul" ] || cp -a "$B" "$SAUV/M31_01.lab31-calcul"
sysctl -n kernel.kptr_restrict > "$SAUV/M31_01.kptr_restrict"

# la « mise à jour » : compilée sans pointeurs de cadre, livrée dépouillée,
# symboles de débogage à part
if file "$B" | grep -q 'not stripped'; then
  T=$(mktemp -d)
  gcc -O2 -g -fomit-frame-pointer -o "$T/lab31-calcul" "$SRC"
  install -d -m 755 /usr/local/lib/lab31
  objcopy --only-keep-debug "$T/lab31-calcul" /usr/local/lib/lab31/lab31-calcul.debug
  strip --strip-all "$T/lab31-calcul"
  install -m 755 "$T/lab31-calcul" "$B"
  rm -rf "$T"
fi

# le « durcissement »
cat > /etc/sysctl.d/99-durcissement.conf <<'EOF'
# durcissement : masquer les adresses du noyau
kernel.kptr_restrict = 2
EOF
sysctl -q -p /etc/sysctl.d/99-durcissement.conf

systemctl restart lab31-calcul

cat <<'EOF'

Symptôme attendu : le flame graph de lab31-calcul (procédure de L31.1)
n'est plus qu'une forêt de [unknown] et d'adresses, côté programme et côté
noyau ; le programme tourne normalement. Les symboles de débogage ont été
« livrés à part, dans /usr/local/lib/lab31/ ».
EOF
