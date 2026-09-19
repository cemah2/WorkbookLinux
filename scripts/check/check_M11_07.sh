#!/usr/bin/env bash
# check_M11_07.sh — vérifie le lab L11.6 (RAID1 mdadm sous LVM, panne et
#                   reconstruction)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.6 =="

MD=/dev/md0
VG=vg_raid
LV=lv_partage
MNT=/srv/factura/partage
CONF=/etc/mdadm/mdadm.conf
LAB_USER="${SUDO_USER:-mathieu}"
HOME_LAB="$(getent passwd "$LAB_USER" | cut -d: -f6)"
RAPPORT="${HOME_LAB:-/root}/lab11/rapports/inf-4201.md"

if ! command -v mdadm >/dev/null 2>&1; then
  ko "mdadm absent : sudo apt install -y mdadm"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- 1. le tableau existe et il est en RAID1 ------------------------------
if [ -b "$MD" ] && grep -q '^md0 ' /proc/mdstat 2>/dev/null; then
  ok "$MD est assemblé"
  grep -q '^md0 : active raid1' /proc/mdstat \
    && ok "$MD est un RAID1" \
    || ko "$MD n'est pas en raid1 (cat /proc/mdstat)"
else
  ko "$MD n'est pas assemblé (cat /proc/mdstat ; mdadm --assemble --scan)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- 2. deux membres actifs, pas de faulty, pas de reconstruction en cours -
DETAIL=$(mdadm --detail "$MD" 2>/dev/null)
ACTIFS=$(echo "$DETAIL" | awk -F: '/Active Devices/{gsub(/ /,"",$2);print $2}')
FAUTIFS=$(echo "$DETAIL" | awk -F: '/Failed Devices/{gsub(/ /,"",$2);print $2}')
ETAT=$(echo "$DETAIL" | awk -F': ' '/^ *State :/{print $2}')
if [ "${ACTIFS:-0}" -ge 2 ]; then
  ok "deux membres actifs"
else
  ko "seulement ${ACTIFS:-0} membre actif : le miroir est dégradé \
(mdadm --detail $MD, puis --remove / --add)"
fi
[ "${FAUTIFS:-0}" -eq 0 ] \
  && ok "aucun membre marqué faulty" \
  || ko "$FAUTIFS membre(s) faulty : retire-le puis réintègre-le"
case "$ETAT" in
  *degraded*|*recovering*|*resyncing*)
    ko "état « $ETAT » : attends la fin de la reconstruction ou répare" ;;
  *) ok "état du tableau : $ETAT" ;;
esac
grep -q 'recovery\|resync' /proc/mdstat \
  && note "une synchronisation est en cours (watch cat /proc/mdstat)"

# --- 3. persistance : mdadm.conf + initramfs ------------------------------
UUID_MD=$(echo "$DETAIL" | awk -F': ' '/^ *UUID :/{print $2}' | tr -d ' ')
if [ -n "$UUID_MD" ] && grep -qs "^ARRAY.*$UUID_MD" "$CONF"; then
  ok "la ligne ARRAY de $MD est dans $CONF"
  NB=$(grep -c "^ARRAY.*$UUID_MD" "$CONF")
  [ "$NB" -eq 1 ] || note "$NB lignes ARRAY pour le même UUID : nettoie"
else
  ko "pas de ligne ARRAY avec l'UUID du tableau dans $CONF \
(mdadm --detail --scan)"
fi
grep -qs '^MAILADDR' "$CONF" \
  && ok "MAILADDR est renseigné" \
  || ko "pas de MAILADDR dans $CONF : mdmonitor n'a personne à prévenir"
INITRD=/boot/initrd.img-$(uname -r)
if [ -f "$INITRD" ] && command -v lsinitramfs >/dev/null 2>&1; then
  if lsinitramfs "$INITRD" 2>/dev/null | grep -q 'etc/mdadm/mdadm.conf'; then
    if [ "$INITRD" -nt "$CONF" ]; then
      ok "l'initramfs est plus récent que $CONF"
    else
      ko "$CONF a changé après l'initramfs : sudo update-initramfs -u"
    fi
  else
    ko "l'initramfs ne contient pas mdadm.conf (update-initramfs -u)"
  fi
else
  note "initramfs non vérifiable ici (conteneur ou Rocky : dracut -f)"
fi

# --- 4. supervision ---------------------------------------------------------
if [ -d /run/systemd/system ]; then
  systemctl is-active --quiet mdmonitor.service \
    && ok "mdmonitor.service est actif" \
    || ko "mdmonitor.service n'est pas actif (systemctl enable --now mdmonitor)"
fi

# --- 5. LVM par-dessus ------------------------------------------------------
if command -v pvs >/dev/null 2>&1; then
  PVMD=$(pvs --noheadings -o pv_name,vg_name 2>/dev/null \
    | awk -v vg="$VG" '$2==vg{print $1}')
  case "$PVMD" in
    */md0|*/md/*) ok "le VG $VG repose sur $PVMD" ;;
    "") ko "aucun PV du VG $VG (pvcreate $MD ; vgcreate $VG $MD)" ;;
    *)  ko "le VG $VG repose sur $PVMD, pas sur $MD" ;;
  esac
  lvs "$VG/$LV" >/dev/null 2>&1 \
    && ok "le LV $VG/$LV existe" \
    || ko "le LV $VG/$LV n'existe pas"
else
  ko "lvm2 absent"
fi

# --- 6. montage et fstab ----------------------------------------------------
if findmnt -no TARGET "$MNT" >/dev/null 2>&1; then
  SRC=$(findmnt -no SOURCE "$MNT")
  case "$SRC" in
    /dev/mapper/${VG}-${LV}|/dev/${VG}/${LV})
      ok "$MNT est monté depuis $VG/$LV" ;;
    *) ko "$MNT est monté depuis $SRC, attendu $VG/$LV" ;;
  esac
  touch "$MNT/.check" 2>/dev/null && rm -f "$MNT/.check" \
    && ok "$MNT accepte les écritures" \
    || ko "$MNT refuse les écritures (lecture seule ?)"
else
  ko "$MNT n'est pas monté"
fi
LIGNE=$(awk -v m="$MNT" '$0 !~ /^[[:space:]]*#/ && $2 == m {print}' \
  /etc/fstab 2>/dev/null | tail -1)
if [ -n "$LIGNE" ]; then
  ok "une ligne /etc/fstab couvre $MNT"
  echo "$LIGNE" | awk '{print $4}' | grep -q nofail \
    && ok "option nofail présente" \
    || ko "il manque nofail : un tableau non assemblé bloquerait le boot"
else
  ko "aucune ligne /etc/fstab pour $MNT"
fi

# --- 7. rapport --------------------------------------------------------------
if [ -f "$RAPPORT" ]; then
  ok "le rapport $RAPPORT existe"
  grep -qiE 'recover|reconstruct|resync' "$RAPPORT" \
    && ok "le rapport parle de la reconstruction" \
    || ko "le rapport ne mentionne pas la reconstruction ni sa durée"
else
  ko "rapport absent : $RAPPORT"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
