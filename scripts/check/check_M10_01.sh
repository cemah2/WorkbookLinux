#!/usr/bin/env bash
# check_M10_01.sh — vérifie le lab L10.1 (deux disques mis en service)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L10.1 =="

ARCH=/srv/factura/archives
JOUR=/srv/factura/journaux

# --- 1. /srv/factura/archives : monté, ext4, durci ----------------------
if findmnt -no TARGET "$ARCH" >/dev/null 2>&1; then
  ok "$ARCH est monté"

  FS=$(findmnt -no FSTYPE "$ARCH")
  [ "$FS" = "ext4" ] && ok "$ARCH est en ext4" \
    || ko "$ARCH est en $FS, ext4 était demandé"

  OPTS=$(findmnt -no OPTIONS "$ARCH")
  for o in noatime nodev nosuid noexec; do
    case ",$OPTS," in
      *",$o,"*) ok "option $o active sur $ARCH" ;;
      *) ko "option $o absente sur $ARCH (findmnt -no OPTIONS $ARCH)" ;;
    esac
  done

  # noexec réellement effectif ?
  TMPEXE="$ARCH/.check-noexec"
  if cp /bin/true "$TMPEXE" 2>/dev/null && chmod +x "$TMPEXE" 2>/dev/null; then
    if "$TMPEXE" 2>/dev/null; then
      ko "un binaire s'exécute depuis $ARCH : noexec n'est pas effectif"
    else
      ok "noexec est effectif (un binaire copié ne s'exécute pas)"
    fi
    rm -f "$TMPEXE"
  else
    note "impossible de tester noexec en écrivant dans $ARCH (droits ?)"
  fi
else
  ko "$ARCH n'est pas monté (findmnt $ARCH)"
fi

# --- 2. la ligne de fstab : par UUID, nofail, pass 0 --------------------
LIGNE_A=$(awk -v m="$ARCH" '$0 !~ /^[[:space:]]*#/ && $2 == m {print}' \
  /etc/fstab 2>/dev/null | tail -1)
if [ -n "$LIGNE_A" ]; then
  ok "une ligne de /etc/fstab couvre $ARCH"
  case "$LIGNE_A" in
    UUID=*) ok "le montage est référencé par UUID" ;;
    /dev/*) ko "le montage est référencé par un nom /dev/... : utilise UUID=" ;;
    *)      note "source inhabituelle : $(echo "$LIGNE_A" | awk '{print $1}')" ;;
  esac
  echo "$LIGNE_A" | awk '{print $4}' | grep -q 'nofail' \
    && ok "l'option nofail est présente" \
    || ko "il manque nofail : un disque absent bloquerait le démarrage"
  PASSF=$(echo "$LIGNE_A" | awk '{print $6}')
  [ "${PASSF:-0}" = "0" ] && ok "sixième champ à 0 (pas de fsck au démarrage)" \
    || ko "sixième champ à ${PASSF} : mets 0 pour ce volume de données"
else
  ko "aucune ligne de /etc/fstab pour $ARCH : le montage ne survivra pas au reboot"
fi

# --- 3. /srv/factura/journaux en XFS -----------------------------------
if findmnt -no TARGET "$JOUR" >/dev/null 2>&1; then
  ok "$JOUR est monté"
  FSJ=$(findmnt -no FSTYPE "$JOUR")
  [ "$FSJ" = "xfs" ] && ok "$JOUR est en XFS" \
    || ko "$JOUR est en $FSJ, XFS était demandé (mkfs.xfs)"
else
  ko "$JOUR n'est pas monté"
fi

awk -v m="$JOUR" '$0 !~ /^[[:space:]]*#/ && $2 == m' /etc/fstab 2>/dev/null \
  | grep -q '^UUID=' \
  && ok "$JOUR est référencé par UUID dans /etc/fstab" \
  || ko "$JOUR n'a pas de ligne fstab par UUID"

# --- 4. cohérence globale de fstab -------------------------------------
if findmnt --verify >/dev/null 2>&1; then
  ok "findmnt --verify ne signale aucune anomalie dans /etc/fstab"
else
  ko "findmnt --verify signale une anomalie (lance-le avec --verbose)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
