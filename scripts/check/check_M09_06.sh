#!/usr/bin/env bash
# check_M09_06.sh — vérifie le défi D9 (base noyau Factura)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D9 =="

HOME_DIR="$(getent passwd "${SUDO_USER:-${USER:-$(id -un)}}" | cut -d: -f6)"
RAP="$HOME_DIR/lab09/rapports"; BIN="$HOME_DIR/lab09/bin"
F=/etc/sysctl.d/60-factura.conf

# --- 1. fichier sysctl unique et valeurs effectives -----------------------
[ -f "$F" ] && ok "$F existe" || ko "$F absent"
want() {
  local v; v=$(sysctl -n "$1" 2>/dev/null | tr '\t' ' ')
  [ "$v" = "$2" ] && ok "$1 = $2" \
    || ko "$1 = ${v:-ABSENT} (attendu $2) : sysctl --system, rang, module ?"
}
want vm.swappiness 10
want vm.dirty_background_ratio 5
want vm.dirty_ratio 10
want net.core.somaxconn 8192
want net.ipv4.ip_local_port_range "10240 65000"
want fs.inotify.max_user_watches 524288
want kernel.panic 10
want kernel.kptr_restrict 2
want kernel.dmesg_restrict 1
want kernel.sysrq 176
want net.ipv4.ip_forward 0
want net.netfilter.nf_conntrack_max 131072
if [ -f "$F" ]; then
  for k in swappiness somaxconn nf_conntrack_max kptr_restrict; do
    grep -q "$k" "$F" || ko "$k n'est pas dans $F (un seul fichier attendu)"
  done
fi
grep -qsE '^\s*nf_conntrack\s*$' /etc/modules-load.d/*.conf \
  && ok "nf_conntrack dans modules-load.d (prérequis résolu)" \
  || ko "nf_conntrack absent de /etc/modules-load.d : la clé sera ignorée \
au boot"
if [ -d /run/systemd/system ]; then
  journalctl -u systemd-sysctl -b --no-pager 2>/dev/null | \
    grep -qiE 'cannot|failed|Couldn' \
    && ko "systemd-sysctl a émis une erreur à ce boot (journalctl -u \
systemd-sysctl -b)" \
    || ok "systemd-sysctl sans erreur à ce boot"
fi

# --- 2. modules -----------------------------------------------------------
lsmod | grep -q '^joydev ' && ko "joydev chargé" \
  || ok "joydev n'est pas chargé"
grep -qsE '^\s*install\s+joydev\s+/bin/false' /etc/modprobe.d/*.conf \
  && ok "joydev interdit (install /bin/false)" \
  || note "joydev non interdit : accepté si un autre module de L9.3 l'est"

# --- 3. ligne de commande du noyau ----------------------------------------
CMD=$(cat /proc/cmdline)
[[ $CMD == *console=ttyS0* ]] && ok "console série sur la ligne noyau" \
  || ko "console=ttyS0 absent de /proc/cmdline"
[[ $CMD == *transparent_hugepage=madvise* ]] && ok "THP madvise au boot" \
  || ko "transparent_hugepage=madvise absent (update-grub + reboot ?)"
[[ $CMD == *mitigations=off* ]] && ko "mitigations=off est présent : refusé" \
  || ok "mitigations actives"
[[ $CMD == *crashkernel=* ]] && ok "crashkernel= réservé" \
  || ko "pas de crashkernel= : kdump ne peut pas charger"

# --- 4. kdump -------------------------------------------------------------
if [ "$(cat /sys/kernel/kexec_crash_loaded 2>/dev/null)" = 1 ]; then
  ok "noyau de secours chargé (kexec_crash_loaded=1)"
else
  ko "kdump non chargé : kdump-config show / systemctl status kdump-tools"
fi
if ls /var/crash/*/dump* >/dev/null 2>&1 || ls /var/crash/*/vmcore* \
   >/dev/null 2>&1; then
  ok "un dump existe dans /var/crash (test réel effectué)"
else
  ko "aucun dump dans /var/crash : le test SysRq 'c' n'a pas été fait"
fi

# --- 5. temps et /boot ----------------------------------------------------
[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] \
  && ok "horloge synchronisée" || ko "horloge non synchronisée"
[ -s "$HOME_DIR/lab09/conf/chrony-client.conf" ] \
  && ok "modèle chrony client rangé dans ~/lab09/conf" \
  || ko "~/lab09/conf/chrony-client.conf absent"
USE=$(df --output=pcent /boot 2>/dev/null | tail -1 | tr -dc 0-9)
[ -n "$USE" ] && [ "$USE" -lt 70 ] && ok "/boot à $USE %" \
  || ko "/boot à ${USE:-?} % (>= 70)"

# --- 6. script de conformité ---------------------------------------------
S="$BIN/verif-noyau.sh"
if [ -x "$S" ]; then
  ok "script $S exécutable"
  head -5 "$S" | grep -q 'set -euo pipefail' && ok "set -euo pipefail" \
    || ko "le script n'a pas set -euo pipefail en tête"
  OUT=$(sudo -n "$S" 2>/dev/null); RC=$?
  L=$(printf '%s\n' "$OUT" | grep -cE '^\[ ?(OK|FAIL) ?\]')
  [ "$L" -ge 12 ] && ok "le script affiche $L lignes [ OK ]/[FAIL]" \
    || ko "le script n'affiche que $L lignes [ OK ]/[FAIL] (12 attendues)"
  [ "$RC" -eq 0 ] && ok "le script sort en 0" \
    || ko "le script sort en $RC : au moins un point non conforme"
else
  ko "$S absent ou non exécutable"
fi

# --- 7. rapport -----------------------------------------------------------
if [ -f "$RAP/base-noyau.md" ] && [ "$(wc -l < "$RAP/base-noyau.md")" -ge 25 ]
then
  ok "rapport base-noyau.md présent"
  grep -qi 'mitigations' "$RAP/base-noyau.md" \
    && ok "le rapport justifie le refus de mitigations=off" \
    || ko "le rapport ne parle pas de mitigations=off"
  grep -qiE 'kdump|crash' "$RAP/base-noyau.md" \
    && ok "le rapport documente le test kdump" \
    || ko "le rapport ne documente pas kdump"
else
  ko "rapport $RAP/base-noyau.md absent ou trop court (25 lignes)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
