#!/usr/bin/env bash
# check_M11_04.sh — vérifie le lab L11.4 (croissance du disque + swap)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.4 =="

# --- 1. la racine a bien grandi ----------------------------------------
GO=$(df -BG --output=size / 2>/dev/null | tail -1 | tr -dc '0-9')
if [ "${GO:-0}" -ge 45 ]; then
  ok "/ fait ${GO} Go (>= 45 Go attendus)"
else
  ko "/ ne fait que ${GO:-?} Go : la chaîne growpart -> pvresize -> lvextend \
-> resize2fs n'est pas allée jusqu'au bout (df -h /, puis pvs et vgs)"
fi

# --- 2. la chaîne a bien été poussée couche par couche -----------------
if command -v pvs >/dev/null 2>&1; then
  SRC=$(findmnt -no SOURCE / 2>/dev/null)
  case "$SRC" in
    /dev/mapper/*|/dev/*-*)
      ok "/ est sur un volume logique ($SRC)"
      VGFREE=$(vgs --noheadings --units g --nosuffix -o vg_free 2>/dev/null \
        | head -1 | tr -d ' ' | cut -d. -f1)
      [ "${VGFREE:-0}" -le 2 ] \
        && ok "le groupe de volumes est consommé (${VGFREE:-0} Go libres)" \
        || note "il reste ${VGFREE} Go libres dans le VG : \
lvextend -l +100%FREE n'a pas tout pris"
      ;;
    *) note "/ n'est pas sur LVM ($SRC) : adapte la procédure à ta VM" ;;
  esac
fi

# --- 3. le swap est actif et de la bonne taille ------------------------
SWKB=$(awk 'NR>1 {s+=$3} END {print s+0}' /proc/swaps 2>/dev/null)
SWMO=$(( SWKB / 1024 ))
if [ "$SWMO" -ge 1900 ]; then
  ok "swap actif : ${SWMO} Mio"
else
  ko "swap actif : ${SWMO} Mio (2 Gio attendus) — mkswap puis swapon, \
vérifie avec swapon --show"
fi

# --- 4. le swap est permanent ------------------------------------------
if awk '$0 !~ /^[[:space:]]*#/ && $3 == "swap"' /etc/fstab 2>/dev/null \
     | grep -q .; then
  ok "une ligne swap est présente dans /etc/fstab"
else
  ko "aucune ligne swap dans /etc/fstab : le swap disparaîtra au redémarrage \
(/swapfile none swap sw 0 0)"
fi

if [ -f /swapfile ]; then
  DROITS=$(stat -c %a /swapfile)
  [ "$DROITS" = "600" ] && ok "/swapfile est en mode 600" \
    || ko "/swapfile est en mode $DROITS : swapon exige 600 (chmod 600)"
fi

# --- 5. swappiness -----------------------------------------------------
SW=$(cat /proc/sys/vm/swappiness 2>/dev/null)
[ "${SW:-60}" = "10" ] && ok "vm.swappiness vaut 10" \
  || ko "vm.swappiness vaut ${SW:-?} au lieu de 10"

if grep -rqs 'swappiness' /etc/sysctl.d/ /etc/sysctl.conf 2>/dev/null; then
  ok "vm.swappiness est fixé de façon persistante"
else
  ko "vm.swappiness n'est écrit nulle part dans /etc/sysctl.d/ : la valeur \
sera perdue au redémarrage"
fi

# --- 6. fstab cohérent --------------------------------------------------
findmnt --verify >/dev/null 2>&1 \
  && ok "findmnt --verify ne signale aucune anomalie" \
  || ko "findmnt --verify signale une anomalie dans /etc/fstab"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
