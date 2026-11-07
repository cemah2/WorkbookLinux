#!/usr/bin/env bash
# check_M11_06.sh — vérifie le défi D11 (RAID1 + LVM + LUKS + supervision)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D11 =="

VG=vg_sauv
MNT=/srv/sauvegardes
SAUV=/opt/factura/bin/sauvegarde.sh
VERIF=/opt/factura/bin/verif-stockage.sh

# --- 1. RAID1 -----------------------------------------------------------
if grep -qE '^md[0-9]+ : active raid1' /proc/mdstat 2>/dev/null; then
  ok "un tableau RAID1 est actif"
  LIGNE=$(grep -E '^md[0-9]+ : active raid1' /proc/mdstat | head -1)
  NBD=$(echo "$LIGNE" | grep -oE '\[[0-9]+\]' | wc -l)
  [ "$NBD" -ge 2 ] && ok "le miroir compte $NBD membres" \
    || ko "le miroir ne compte que $NBD membre : --raid-devices=2 attendu"
  if grep -qE '\[U+\]' /proc/mdstat; then
    ok "le tableau est sain (tous les membres marqués U)"
  elif grep -qE 'recovery|resync' /proc/mdstat; then
    note "reconstruction en cours : c'est attendu juste après l'étape 7"
  else
    ko "le tableau est dégradé : $(grep -E '\[[U_]+\]' /proc/mdstat | tr -s ' ')"
  fi
else
  ko "aucun RAID1 actif dans /proc/mdstat (mdadm --create /dev/md0 \
--level=1 --raid-devices=2 ...)"
fi

CONF=""
for f in /etc/mdadm/mdadm.conf /etc/mdadm.conf; do
  [ -f "$f" ] && CONF="$f" && break
done
if [ -n "$CONF" ] && grep -q '^ARRAY' "$CONF"; then
  ok "$CONF contient une ligne ARRAY"
else
  ko "aucune ligne ARRAY dans mdadm.conf : le tableau reviendra en \
/dev/md127 au prochain démarrage (mdadm --detail --scan | tee -a ...)"
fi

if [ -d /boot ] && ls /boot/initrd.img-* >/dev/null 2>&1 && [ -n "$CONF" ]; then
  RECENT=$(ls -1t /boot/initrd.img-* 2>/dev/null | head -1)
  if [ "$RECENT" -nt "$CONF" ]; then
    ok "l'initramfs est plus récent que mdadm.conf (update-initramfs fait)"
  else
    ko "l'initramfs est plus ancien que $CONF : lance \
sudo update-initramfs -u, sinon l'assemblage au boot utilisera l'ancienne conf"
  fi
fi

# --- 2. LVM sur le RAID -------------------------------------------------
if command -v vgs >/dev/null 2>&1; then
  if vgs --noheadings -o vg_name 2>/dev/null | grep -qw "$VG"; then
    ok "le groupe $VG existe"
    PVL=$(pvs --noheadings -o pv_name --select "vg_name=$VG" 2>/dev/null \
      | tr -d ' ')
    echo "$PVL" | grep -q '/dev/md' \
      && ok "le PV du groupe est un tableau md ($PVL)" \
      || ko "le PV du groupe est $PVL : le PV doit être posé sur /dev/md0"

    TOT=$(LC_ALL=C vgs --noheadings --units m --nosuffix -o vg_size "$VG" \
      2>/dev/null | tr -d ' ' | cut -d. -f1)
    LVC=$(LC_ALL=C lvs --noheadings --units m --nosuffix -o lv_size \
      "$VG/lv_coffre" \
      2>/dev/null | tr -d ' ' | cut -d. -f1)
    if [ -n "${LVC:-}" ] && [ "${TOT:-0}" -gt 0 ]; then
      PCT=$(( LVC * 100 / TOT ))
      if [ "$PCT" -ge 55 ] && [ "$PCT" -le 65 ]; then
        ok "lv_coffre occupe ${PCT} % du groupe (60 % attendus)"
      else
        ko "lv_coffre occupe ${PCT} % du groupe : 60 % étaient demandés, \
les 40 % restants doivent rester libres"
      fi
    else
      ko "lv_coffre est absent de $VG"
    fi
  else
    ko "le groupe $VG n'existe pas"
  fi
fi

# --- 3. LUKS et montage -------------------------------------------------
if findmnt -no TARGET "$MNT" >/dev/null 2>&1; then
  SRC=$(findmnt -no SOURCE "$MNT")
  case "$SRC" in
    /dev/mapper/coffre) ok "$MNT est monté depuis /dev/mapper/coffre" ;;
    *) ko "$MNT est monté depuis $SRC : la pile LUKS n'est pas en place" ;;
  esac
  OPTS=$(findmnt -no OPTIONS "$MNT")
  for o in nodev nosuid noexec; do
    case ",$OPTS," in
      *",$o,"*) ok "option $o active sur $MNT" ;;
      *) ko "option $o absente sur $MNT" ;;
    esac
  done
else
  ko "$MNT n'est pas monté"
fi

grep -qs '^coffre' /etc/crypttab 2>/dev/null \
  && ok "/etc/crypttab contient une entrée coffre" \
  || ko "aucune entrée coffre dans /etc/crypttab"

# --- 4. script de sauvegarde -------------------------------------------
if [ -x "$SAUV" ]; then
  ok "$SAUV existe et est exécutable"
  grep -q 'set -euo pipefail' "$SAUV" && ok "set -euo pipefail présent" \
    || ko "set -euo pipefail manquant dans $SAUV"
  grep -qE '^\s*trap\b' "$SAUV" && ok "trap de nettoyage présent" \
    || ko "aucun trap : un échec laissera un snapshot en place"
  grep -qE 'vg_free|vgs' "$SAUV" \
    && ok "le script contrôle l'espace libre du groupe avant de démarrer" \
    || ko "le script ne vérifie pas l'espace libre du VG (exigence 4)"
  grep -qE '\b7\b' "$SAUV" \
    && ok "une rétention est implémentée" \
    || note "vérifie la rétention à 7 archives"
  grep -q '/var/log/factura' "$SAUV" \
    && ok "le script journalise dans /var/log/factura" \
    || ko "aucune journalisation vers /var/log/factura"
else
  ko "$SAUV absent ou non exécutable"
fi

# --- 5. script de supervision ------------------------------------------
if [ -x "$VERIF" ]; then
  ok "$VERIF existe et est exécutable"
  for motif in mdstat data_percent vg_free findmnt; do
    grep -q "$motif" "$VERIF" && ok "contrôle « $motif » présent" \
      || ko "le script ne contrôle pas « $motif » (exigence 5)"
  done
  grep -qE 'ipcent|df -i|inode' "$VERIF" \
    && ok "le script surveille aussi les inodes" \
    || ko "le script ne surveille pas les inodes (df -i / --output=ipcent)"
  "$VERIF" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 0 ] || [ "$RC" -eq 1 ]; then
    ok "le script sort en $RC (0 = tout va bien, 1 = alerte)"
  else
    ko "le script sort en $RC : seuls 0 et 1 sont prévus"
  fi
else
  ko "$VERIF absent ou non exécutable"
fi

# --- 6. timers ----------------------------------------------------------
if [ -d /run/systemd/system ]; then
  for t in factura-sauvegarde.timer verif-stockage.timer; do
    if systemctl is-enabled "$t" >/dev/null 2>&1; then
      ok "$t est activé"
    else
      ko "$t n'est pas activé (systemctl enable --now $t)"
    fi
  done
else
  note "systemd n'est pas actif : contrôle des timers sauté"
fi

# --- 7. rapport ---------------------------------------------------------
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab11/rapports/d11.md"
if [ -s "$RAP" ]; then
  L=$(grep -c . "$RAP")
  [ "$L" -ge 20 ] && ok "rapport d11.md rédigé ($L lignes)" \
    || ko "rapport d11.md trop court ($L lignes, 20 minimum)"
  for mot in raid luks lvm; do
    grep -qi "$mot" "$RAP" || note "le rapport ne parle pas de « $mot »"
  done
  grep -qi 'reconstruction\|recovery\|resync' "$RAP" \
    || note "le rapport ne mentionne pas le temps de reconstruction (étape 7)"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
