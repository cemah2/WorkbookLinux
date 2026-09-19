#!/usr/bin/env bash
# check_M09_02.sh — vérifie le lab L9.2 (noyau HWE, purge, /boot)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.2 =="

HOME_DIR="$(getent passwd "${SUDO_USER:-${USER:-$(id -un)}}" | cut -d: -f6)"
RAP="$HOME_DIR/lab09/rapports"

command -v dpkg >/dev/null 2>&1 || { \
  ko "ce contrôle vise lab-adm (Ubuntu) ; sur Rocky, vérifie à la main \
grubby --default-kernel et dnf list installed 'kernel*'"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

K=$(uname -r)
case "$K" in
  6.8.*) ko "le noyau en cours est encore un 6.8 ($K) : HWE installé et \
reboot fait ?" ;;
  *)     ok "noyau en cours : $K (HWE)" ;;
esac

dpkg -l linux-generic-hwe-24.04 2>/dev/null | grep -q '^ii' \
  && ok "métapaquet linux-generic-hwe-24.04 installé" \
  || ko "linux-generic-hwe-24.04 n'est pas installé"

N=$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)
if [ "$N" -ge 1 ] && [ "$N" -le 2 ]; then
  ok "$N version(s) de noyau dans /boot (max 2)"
else
  ko "$N versions dans /boot : purge les noyaux superflus (apt autoremove \
--purge, puis les orphelins)"
fi

if ls /boot/vmlinuz-6.8.* >/dev/null 2>&1; then
  ok "un noyau 6.8 est conservé comme repli"
else
  note "aucun 6.8 conservé : l'énoncé demandait un repli (non bloquant)"
fi

[ -f "/boot/vmlinuz-$K" ] && [ -f "/boot/initrd.img-$K" ] \
  && ok "vmlinuz et initrd du noyau courant présents" \
  || ko "il manque vmlinuz ou initrd.img pour $K dans /boot !"

USE=$(df --output=pcent /boot 2>/dev/null | tail -1 | tr -dc 0-9)
if [ -n "$USE" ] && [ "$USE" -le 70 ]; then
  ok "/boot occupé à $USE % (plus de 30 % libres)"
else
  ko "/boot occupé à ${USE:-?} % : il faut au moins 30 % de libre"
fi

if [ -f /boot/grub/grub.cfg ]; then
  grep -E "^menuentry" /boot/grub/grub.cfg | head -1 | grep -q "$K" \
    && ok "l'entrée GRUB par défaut est le noyau en cours" \
    || note "la première entrée GRUB n'est pas $K (GRUB_DEFAULT modifié ?)"
fi

[ -s "$RAP/noyaux-avant.txt" ] && ok "inventaire avant conservé" \
  || ko "$RAP/noyaux-avant.txt absent"
if [ -f "$RAP/noyaux.md" ] && [ "$(wc -l < "$RAP/noyaux.md")" -ge 15 ]; then
  ok "rapport noyaux.md présent"
  grep -qi 'secure' "$RAP/noyaux.md" \
    && ok "le rapport a une section Secure Boot" \
    || ko "le rapport ne parle pas de Secure Boot / MOK"
else
  ko "rapport $RAP/noyaux.md absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
