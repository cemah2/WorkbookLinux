#!/usr/bin/env bash
# check_M09_01.sh — vérifie le lab L9.1 (chaîne de démarrage, console série)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.1 =="

HOME_DIR="$(getent passwd "${SUDO_USER:-${USER:-$(id -un)}}" | cut -d: -f6)"
RAP="$HOME_DIR/lab09/rapports"

# --- 1. ligne de commande du noyau en cours -----------------------------
if grep -q 'console=ttyS0' /proc/cmdline; then
  ok "le noyau en cours a console=ttyS0 (/proc/cmdline)"
else
  ko "console=ttyS0 absent de /proc/cmdline : GRUB régénéré ? redémarré ?"
fi

# --- 2. configuration GRUB effective ----------------------------------
if [ -f /boot/grub/grub.cfg ]; then
  grep -E '^\s+linux' /boot/grub/grub.cfg | grep -q 'ttyS0' \
    && ok "grub.cfg (Ubuntu) porte ttyS0 sur les lignes linux" \
    || ko "les lignes linux de /boot/grub/grub.cfg n'ont pas ttyS0 \
(update-grub ?)"
  grep -qE '^serial ' /boot/grub/grub.cfg \
    && ok "GRUB lui-même est sur le port série (commande serial)" \
    || ko "pas de GRUB_TERMINAL/GRUB_SERIAL_COMMAND appliqués \
(grep '^serial' grub.cfg)"
  T=$(grep -oE '^\s*set timeout=[0-9-]+' /boot/grub/grub.cfg | tail -1 \
      | cut -d= -f2)
  if [ -n "${T:-}" ] && { [ "$T" -ge 5 ] || [ "$T" -lt 0 ]; }; then
    ok "menu GRUB visible ($T s)"
  else
    ko "timeout GRUB = ${T:-?} : il faut GRUB_TIMEOUT>=5 et \
GRUB_TIMEOUT_STYLE=menu"
  fi
  grep -hE '^GRUB_TIMEOUT_STYLE' /etc/default/grub /etc/default/grub.d/*.cfg \
    2>/dev/null | tail -1 | grep -q menu \
    && ok "GRUB_TIMEOUT_STYLE=menu" \
    || ko "GRUB_TIMEOUT_STYLE n'est pas 'menu' (fichier de rang le plus élevé)"
elif command -v grubby >/dev/null 2>&1; then
  grubby --info=ALL 2>/dev/null | grep -q 'ttyS0' \
    && ok "grubby (Rocky) : ttyS0 sur les entrées" \
    || ko "grubby --info=ALL ne montre pas ttyS0"
else
  ko "ni /boot/grub/grub.cfg ni grubby : où est GRUB ?"
fi

# --- 3. getty série actif ----------------------------------------------
if [ -d /run/systemd/system ]; then
  [ "$(systemctl is-active serial-getty@ttyS0.service 2>/dev/null)" = active ] \
    && ok "serial-getty@ttyS0.service est actif" \
    || ko "serial-getty@ttyS0 inactif : le port série existe-t-il \
(qm set 9001 --serial0 socket) et la VM a-t-elle redémarré ?"
fi

# --- 4. livrables --------------------------------------------------------
[ -s "$RAP/boot.svg" ] && grep -q '<svg' "$RAP/boot.svg" \
  && ok "boot.svg produit par systemd-analyze plot" \
  || ko "$RAP/boot.svg absent ou vide"
if [ -f "$RAP/demarrage.md" ] && [ "$(wc -l < "$RAP/demarrage.md")" -ge 15 ]
then
  ok "rapport demarrage.md présent ($(wc -l < "$RAP/demarrage.md") lignes)"
  grep -qiE 'init=/bin/bash' "$RAP/demarrage.md" \
    && ok "le rapport décrit la procédure mot de passe perdu" \
    || ko "le rapport ne mentionne pas init=/bin/bash"
else
  ko "rapport $RAP/demarrage.md absent ou trop court (15 lignes minimum)"
fi
note "l'étape 5 (rescue.target / init=/bin/bash) n'est pas testable ici"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
