#!/usr/bin/env bash
# check_M09_03.sh — vérifie le lab L9.3 (modules : dummy, blacklist, virtio)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.3 =="

HOME_DIR="$(getent passwd "${SUDO_USER:-${USER:-$(id -un)}}" | cut -d: -f6)"
RAP="$HOME_DIR/lab09/rapports"

# --- 1. dummy chargé avec deux interfaces --------------------------------
if lsmod | grep -q '^dummy '; then
  ok "module dummy chargé"
  V=$(cat /sys/module/dummy/parameters/numdummies 2>/dev/null)
  [ "$V" = 2 ] && ok "numdummies=2 (lu dans /sys/module)" \
    || ko "numdummies vaut ${V:-?} : options dummy dans /etc/modprobe.d ? \
module rechargé ?"
else
  ko "dummy n'est pas chargé (lsmod) : modules-load.d + \
systemctl restart systemd-modules-load"
fi
for i in dummy0 dummy1; do
  [ -d /sys/class/net/$i ] && ok "interface $i présente" \
    || ko "interface $i absente"
done
ip -4 -o addr show dummy0 2>/dev/null | grep -q '10.10.99.10' \
  && ok "dummy0 porte 10.10.99.10" \
  || ko "dummy0 n'a pas 10.10.99.10 (fichier Netplan séparé + netplan apply)"
ls /etc/netplan/*.yaml 2>/dev/null | grep -qv '50-cloud-init\|00-installer' \
  && ok "un fichier Netplan séparé existe" \
  || note "pas de fichier Netplan supplémentaire détecté (non bloquant)"

# --- 2. persistance -------------------------------------------------------
grep -qsE '^\s*dummy\s*$' /etc/modules-load.d/*.conf /etc/modules 2>/dev/null \
  && ok "dummy listé dans modules-load.d" \
  || ko "dummy absent de /etc/modules-load.d/*.conf"
grep -qsE '^\s*options\s+dummy\s+numdummies=2' /etc/modprobe.d/*.conf \
  && ok "options dummy numdummies=2 dans modprobe.d" \
  || ko "pas de 'options dummy numdummies=2' dans /etc/modprobe.d/*.conf"

# --- 3. module interdit ---------------------------------------------------
BL=""
for m in joydev mac_hid pcspkr; do
  if grep -qsE "^\s*install\s+$m\s+/bin/(false|true)" /etc/modprobe.d/*.conf
  then BL="$m"; break; fi
done
if [ -n "$BL" ]; then
  ok "$BL interdit par une ligne install ... /bin/false"
  grep -qsE "^\s*blacklist\s+$BL" /etc/modprobe.d/*.conf \
    && ok "$BL aussi blacklisté (chargement automatique)" \
    || note "pas de ligne blacklist $BL (install suffit, mais l'énoncé \
demandait les deux)"
  lsmod | grep -q "^$BL " && ko "$BL est encore chargé (reboot ?)" \
    || ok "$BL n'est pas chargé"
  K=$(uname -r)
  if command -v lsinitramfs >/dev/null 2>&1; then
    lsinitramfs "/boot/initrd.img-$K" 2>/dev/null | grep -q 'etc/modprobe.d' \
      && ok "l'initramfs embarque modprobe.d" \
      || ko "l'initramfs ne contient pas modprobe.d : update-initramfs -u ?"
  elif command -v lsinitrd >/dev/null 2>&1; then
    lsinitrd 2>/dev/null | grep -q 'modprobe.d' \
      && ok "l'initramfs (dracut) embarque modprobe.d" \
      || note "modprobe.d non vu dans lsinitrd (dracut -f ?)"
  fi
else
  ko "aucun module (joydev, mac_hid, pcspkr) interdit avec install /bin/false"
fi

# --- 4. rapport -----------------------------------------------------------
if [ -f "$RAP/modules.md" ] && [ "$(wc -l < "$RAP/modules.md")" -ge 12 ]; then
  ok "rapport modules.md présent"
  grep -qi 'dkms' "$RAP/modules.md" && ok "note DKMS présente" \
    || ko "le rapport ne parle pas de DKMS"
  grep -qi 'virtio_scsi' "$RAP/modules.md" && ok "inventaire virtio présent" \
    || ko "le rapport ne cite pas virtio_scsi"
else
  ko "rapport $RAP/modules.md absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
