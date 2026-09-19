#!/usr/bin/env bash
# check_M10_05.sh — vérifie le lab L10.5 (LUKS + client NFS)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L10.5 =="

COFFRE=/srv/coffre
NFSMNT=/mnt/archives-adm

# ======================= Partie A : LUKS ==============================
if ! command -v cryptsetup >/dev/null 2>&1; then
  ko "cryptsetup absent : sudo apt install -y cryptsetup-bin"
else

# --- 1. le volume déchiffré est monté ----------------------------------
if findmnt -no TARGET "$COFFRE" >/dev/null 2>&1; then
  SRC=$(findmnt -no SOURCE "$COFFRE")
  case "$SRC" in
    /dev/mapper/coffre) ok "$COFFRE est monté depuis /dev/mapper/coffre" ;;
    *) ko "$COFFRE est monté depuis $SRC, pas depuis /dev/mapper/coffre" ;;
  esac
else
  ko "$COFFRE n'est pas monté (cryptsetup luksOpen puis mount)"
fi

# --- 2. le périphérique déchiffré est bien un conteneur LUKS ouvert ----
if [ -e /dev/mapper/coffre ]; then
  ok "/dev/mapper/coffre existe (conteneur ouvert)"
  BACKING=$(lsblk -nrpo NAME,TYPE 2>/dev/null \
    | awk '$2=="crypt"{print}' | head -1)
  PARENT=$(lsblk -nrpso NAME /dev/mapper/coffre 2>/dev/null | sed -n 2p)
  if [ -n "$PARENT" ] && cryptsetup isLuks "$PARENT" 2>/dev/null; then
    ok "le périphérique sous-jacent ($PARENT) est un conteneur LUKS"

    # --- 3. crypttab référence l'UUID DU CONTENEUR --------------------
    UUID_LUKS=$(cryptsetup luksUUID "$PARENT" 2>/dev/null)
    if grep -qs "$UUID_LUKS" /etc/crypttab 2>/dev/null; then
      ok "/etc/crypttab référence l'UUID du conteneur LUKS"
    elif grep -qs '^coffre' /etc/crypttab 2>/dev/null; then
      ko "/etc/crypttab contient bien une entrée « coffre » mais pas l'UUID \
du conteneur ($UUID_LUKS) : c'est celui de cryptsetup luksUUID, pas celui \
du système de fichiers"
    else
      ko "aucune entrée « coffre » dans /etc/crypttab : le volume ne sera \
pas déverrouillé au démarrage"
    fi

    # --- 4. deux emplacements de clé ----------------------------------
    NBK=$(cryptsetup luksDump "$PARENT" 2>/dev/null \
      | grep -cE '^[[:space:]]+[0-9]+: luks2|^Key Slot [0-9]+: ENABLED')
    if [ "${NBK:-0}" -ge 2 ]; then
      ok "$NBK emplacements de clé occupés"
    else
      ko "${NBK:-0} emplacement de clé occupé : ajoute-en un second \
(cryptsetup luksAddKey $PARENT)"
    fi
  else
    ko "impossible d'identifier le conteneur LUKS sous /dev/mapper/coffre"
    [ -n "$BACKING" ] && note "vu par lsblk : $BACKING"
  fi
else
  ko "/dev/mapper/coffre n'existe pas : le conteneur n'est pas ouvert"
fi

# --- 5. fstab utilise le nom du mapper et des options durcies ----------
LIGNE=$(awk -v m="$COFFRE" '$0 !~ /^[[:space:]]*#/ && $2 == m {print}' \
  /etc/fstab 2>/dev/null | tail -1)
if [ -n "$LIGNE" ]; then
  echo "$LIGNE" | grep -q '^/dev/mapper/coffre' \
    && ok "/etc/fstab utilise /dev/mapper/coffre" \
    || ko "/etc/fstab doit référencer /dev/mapper/coffre, pas un UUID"
  OPT=$(echo "$LIGNE" | awk '{print $4}')
  for o in nodev nosuid noexec; do
    case ",$OPT," in
      *",$o,"*) ok "option $o présente dans fstab" ;;
      *) note "option $o absente : recommandée sur un volume de données" ;;
    esac
  done
else
  ko "aucune ligne /etc/fstab pour $COFFRE"
fi

fi  # fin cryptsetup

# ======================= Partie B : NFS ===============================
if findmnt -no TARGET "$NFSMNT" >/dev/null 2>&1; then
  ok "$NFSMNT est monté"
  FS=$(findmnt -no FSTYPE "$NFSMNT")
  case "$FS" in
    nfs4|nfs) ok "le type est $FS" ;;
    *) ko "le type est $FS, un montage NFS était demandé" ;;
  esac
  OPTS=$(findmnt -no OPTIONS "$NFSMNT")
  case ",$OPTS," in
    *",ro,"*) ok "le partage est monté en lecture seule" ;;
    *) ko "le partage n'est pas en ro (options : $OPTS)" ;;
  esac
  case "$OPTS" in
    *soft*) ko "le partage est monté en soft : préfère hard pour éviter \
les corruptions silencieuses" ;;
    *) ok "le partage n'est pas en soft" ;;
  esac
else
  ko "$NFSMNT n'est pas monté (showmount -e 10.10.10.10 puis mount -t nfs4)"
fi

LNFS=$(awk -v m="$NFSMNT" '$0 !~ /^[[:space:]]*#/ && $2 == m {print}' \
  /etc/fstab 2>/dev/null | tail -1)
if [ -n "$LNFS" ]; then
  ok "une ligne /etc/fstab couvre $NFSMNT"
  echo "$LNFS" | awk '{print $4}' | grep -q '_netdev' \
    && ok "l'option _netdev est présente" \
    || ko "il manque _netdev : le montage serait tenté avant le réseau"
  echo "$LNFS" | awk '{print $4}' | grep -qE 'nofail|x-systemd.automount' \
    && ok "le boot est protégé (nofail ou x-systemd.automount)" \
    || ko "ajoute nofail ou x-systemd.automount : sinon lab-adm éteint \
bloque le démarrage de lab-db"
else
  ko "aucune ligne /etc/fstab pour $NFSMNT"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
