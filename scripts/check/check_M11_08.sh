#!/usr/bin/env bash
# check_M11_08.sh — vérifie le lab L11.7 (serveur NFS sur lab-ops, clients
#                   lab-db et lab-web). À lancer sur chacune des trois VM :
#                   le script choisit les tests selon le nom d'hôte.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.7 =="

SERVEUR=10.10.10.14
EXP_RW=/srv/nfs/partage
EXP_RO=/srv/nfs/depots
MNT_RW=/mnt/partage-ops
MNT_RO=/mnt/depots-ops
HOTE="$(hostname -s 2>/dev/null || hostname)"

# Une ligne de fstab pour un point de montage (hors commentaires).
ligne_fstab() {
  awk -v m="$1" '$0 !~ /^[[:space:]]*#/ && $2 == m {print}' /etc/fstab \
    2>/dev/null | tail -1
}

# Vérifie un montage NFS client : monté, type, options, fstab.
verif_client() {
  local mnt="$1" mode="$2" ligne opts fs
  # un automount non déclenché apparaît en autofs : on le réveille
  ls "$mnt" >/dev/null 2>&1 || true
  if findmnt -no TARGET "$mnt" >/dev/null 2>&1; then
    fs=$(findmnt -no FSTYPE "$mnt" | tail -1)
    case "$fs" in
      nfs4) ok "$mnt est monté en NFSv4" ;;
      nfs)  ko "$mnt est monté en NFSv3 : demande nfs4 (ou vers=4)" ;;
      autofs) ko "$mnt : automount posé mais le montage échoue (ls $mnt ; \
journalctl -u '$(systemd-escape -p "$mnt").automount')" ;;
      *) ko "$mnt est de type $fs, un montage NFS était demandé" ;;
    esac
    opts=$(findmnt -no OPTIONS "$mnt" | tail -1)
    case "$opts" in
      *soft*) ko "$mnt est monté en soft : préfère hard" ;;
      *) ok "$mnt n'est pas en soft" ;;
    esac
    if [ "$mode" = "ro" ]; then
      case ",$opts," in
        *",ro,"*) ok "$mnt est en lecture seule" ;;
        *) ko "$mnt devrait être en lecture seule" ;;
      esac
    else
      case ",$opts," in
        *",rw,"*) ok "$mnt est en lecture-écriture" ;;
        *) ko "$mnt devrait être en lecture-écriture" ;;
      esac
    fi
  else
    ko "$mnt n'est pas monté (showmount -e $SERVEUR ; mount -a)"
  fi
  ligne=$(ligne_fstab "$mnt")
  if [ -n "$ligne" ]; then
    ok "une ligne /etc/fstab couvre $mnt"
    opts=$(echo "$ligne" | awk '{print $4}')
    echo "$opts" | grep -q '_netdev' \
      && ok "_netdev présent pour $mnt" \
      || ko "il manque _netdev pour $mnt (montage tenté avant le réseau)"
    echo "$opts" | grep -qE 'nofail|x-systemd.automount' \
      && ok "le boot est protégé pour $mnt (nofail ou automount)" \
      || ko "ajoute nofail ou x-systemd.automount pour $mnt"
    echo "$ligne" | awk '{print $1}' | grep -q "^$SERVEUR:" \
      && ok "la source de $mnt est bien $SERVEUR" \
      || ko "la source de $mnt n'est pas $SERVEUR:..."
  else
    ko "aucune ligne /etc/fstab pour $mnt"
  fi
}

case "$HOTE" in
# ======================= serveur ==========================================
lab-ops)
  if ! command -v exportfs >/dev/null 2>&1; then
    ko "nfs-kernel-server absent : sudo apt install -y nfs-kernel-server"
    echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
  fi
  if [ -d /run/systemd/system ]; then
    systemctl is-active --quiet nfs-server.service \
      && ok "nfs-server.service est actif" \
      || ko "nfs-server.service n'est pas actif"
  fi
  # /var/lib/nfs/etab : une ligne par export, options effectives complètes
  if [ -r /var/lib/nfs/etab ]; then
    EXPV=$(tr -s ' \t' ' ' < /var/lib/nfs/etab)
  else
    EXPV=$(exportfs -v 2>/dev/null | tr -s ' \t' ' ' | paste -sd' ' \
      | sed 's| /| \n/|g')
  fi
  # partage : rw, sync, no_subtree_check, root_squash, pour le /24
  L=$(echo "$EXPV" | grep "^$EXP_RW " | grep '10.10.10.0/24')
  if [ -n "$L" ]; then
    ok "$EXP_RW est exporté pour 10.10.10.0/24"
    for o in rw sync no_subtree_check root_squash; do
      echo "$L" | grep -qE "[(,]${o}[,)]" \
        && ok "option $o effective sur $EXP_RW" \
        || ko "option $o absente sur $EXP_RW (exportfs -v)"
    done
    echo "$L" | grep -q 'no_root_squash' \
      && ko "no_root_squash sur $EXP_RW : root du client serait root ici"
  else
    ko "$EXP_RW n'est pas exporté pour 10.10.10.0/24 (exportfs -ra)"
  fi
  # depots : ro, pour lab-web seulement
  L=$(echo "$EXPV" | grep "^$EXP_RO ")
  if [ -n "$L" ]; then
    echo "$L" | grep -q '10.10.10.11' \
      && ok "$EXP_RO est exporté pour lab-web" \
      || ko "$EXP_RO n'est pas exporté pour 10.10.10.11"
    echo "$L" | grep -qE '10\.10\.10\.0/24|\*' \
      && ko "$EXP_RO est ouvert à tout le réseau : lab-web seulement"
    echo "$L" | grep -qE '[(,]ro[,)]' \
      && ok "$EXP_RO est en lecture seule" \
      || ko "$EXP_RO doit être exporté en ro"
  else
    ko "$EXP_RO n'est pas exporté"
  fi
  MODE_RW=$([ -d "$EXP_RW" ] && stat -c %a "$EXP_RW" || echo "?")
  case "$MODE_RW" in
    2777) ok "$EXP_RW est en 2777 (setgid, root squashé peut écrire)" ;;
    2775) note "$EXP_RW est en 2775 : root squashé (65534) ne pourra pas \
y écrire, l'étape 6 échouera (chmod 2777)" ;;
    *) note "$EXP_RW est en $MODE_RW : setgid attendu (2777)" ;;
  esac
  ss -tln 2>/dev/null | grep -q ':2049 ' \
    && ok "le port 2049 écoute" \
    || ko "rien n'écoute sur 2049"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null \
       | grep -q '^Status: active'; then
    ufw status | grep -q '2049' \
      && ok "ufw laisse passer 2049" \
      || ko "ufw actif sans règle pour 2049"
  fi
  ;;
# ======================= clients ==========================================
lab-db)
  command -v mount.nfs4 >/dev/null 2>&1 || ko "nfs-common absent"
  verif_client "$MNT_RW" rw
  if findmnt -no TARGET "$MNT_RW" >/dev/null 2>&1; then
    T="$MNT_RW/.check-$HOTE-$$"
    if touch "$T" 2>/dev/null; then
      ok "écriture possible dans $MNT_RW en tant que $(id -un)"
      rm -f "$T"
    else
      note "écriture refusée en tant que $(id -un) (root_squash ou droits)"
    fi
  fi
  findmnt -no TARGET "$MNT_RO" >/dev/null 2>&1 \
    && ko "$MNT_RO est monté sur lab-db : l'export est réservé à lab-web"
  ;;
lab-web)
  command -v mount.nfs4 >/dev/null 2>&1 || ko "nfs-common absent"
  verif_client "$MNT_RW" rw
  verif_client "$MNT_RO" ro
  ;;
*)
  ko "hôte inattendu ($HOTE) : lance ce script sur lab-ops, lab-db ou lab-web"
  ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
