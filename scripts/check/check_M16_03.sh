#!/usr/bin/env bash
# check_M16_03.sh — vérifie le lab L16.3 (disque plein, lent, en erreur)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L16.3 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab16"
SCRIPT="$BASE/bin/verif-disque.sh"
RAP="$BASE/rapports/disque.md"
DATA=/srv/vitrine/data

# --- 1. le script de qualification --------------------------------------
if [ -s "$SCRIPT" ]; then
  ok "verif-disque.sh présent"
  SORTIE=$(timeout 60 bash "$SCRIPT" "$DATA" 2>&1); RC=$?
  if [ "$RC" -le 2 ]; then
    ok "verif-disque.sh sort en $RC (0/1/2 attendus)"
  else
    ko "verif-disque.sh sort en $RC : le contrat est 0 sain, 1 \
avertissement, 2 anomalie bloquante"
  fi
  MANQUE=""
  a() { printf '%s' "$SORTIE" | grep -qiE "$1" || MANQUE="$MANQUE $2"; }
  a '%|utilis|occup'         'occupation'
  a 'inode'                  'inodes'
  a 'supprim|deleted'        'fichiers-supprimes'
  a '\bro\b|\brw\b|lecture'  'mode-de-montage'
  if [ -z "$MANQUE" ]; then
    ok "la sortie couvre occupation, inodes, fichiers supprimés, montage"
  else
    ko "absent de la sortie :$MANQUE"
  fi
  grep -qE 'df -i|/proc/mounts|findmnt' "$SCRIPT" \
    && ok "le script interroge les inodes et le montage" \
    || ko "le script doit utiliser df -i et findmnt (ou /proc/mounts)"
  grep -qE 'lsof' "$SCRIPT" \
    && ok "le script cherche les fichiers supprimés encore ouverts" \
    || ko "le script doit détecter les fichiers supprimés (lsof +L1)"
  grep -qE 'dmesg|journalctl -k' "$SCRIPT" \
    && ok "le script lit les erreurs d'E/S du noyau" \
    || ko "le script doit regarder dmesg pour les erreurs d'E/S"
else
  ko "script absent : $SCRIPT"
fi

# --- 2. l'état réel du volume -------------------------------------------
if mountpoint -q "$DATA" 2>/dev/null; then
  ok "$DATA est monté"
  OPT=$(findmnt -n -o OPTIONS --target "$DATA")
  case "$OPT" in
    ro,*|*,ro|*,ro,*) ko "$DATA est monté en lecture seule" ;;
    *) ok "$DATA est monté en écriture" ;;
  esac
  USE=$(df --output=pcent "$DATA" | tail -1 | tr -dc '0-9')
  if [ "${USE:-100}" -lt 90 ]; then
    ok "occupation de $DATA : ${USE}%"
  else
    ko "occupation de $DATA : ${USE}% — l'espace n'a pas été récupéré"
  fi
  IUSE=$(df -i --output=ipcent "$DATA" | tail -1 | tr -dc '0-9')
  [ "${IUSE:-100}" -lt 90 ] \
    && ok "inodes de $DATA : ${IUSE}%" \
    || ko "inodes de $DATA saturés : ${IUSE}%"
  if [ "$(id -u)" -eq 0 ] && command -v lsof >/dev/null 2>&1; then
    RET=$(lsof +L1 2>/dev/null | awk -v d="$DATA" '$0 ~ d {s+=$8} END \
      {printf "%d", s/1048576}')
    if [ "${RET:-0}" -lt 50 ]; then
      ok "aucun fichier supprimé ne retient plus de 50 Mo sur $DATA"
    else
      ko "${RET} Mo encore retenus par un fichier supprimé ouvert \
(truncate via /proc/<pid>/fd/<n>)"
    fi
  else
    note "lance en root pour contrôler les fichiers supprimés (lsof +L1)"
  fi
else
  ko "$DATA n'est pas monté"
fi

# --- 3. le rapport -------------------------------------------------------
if [ -s "$RAP" ]; then
  ok "disque.md présent"
  for m in 'lsof' 'df -i' 'await'; do
    grep -qF "$m" "$RAP" \
      && ok "disque.md traite « $m »" \
      || ko "disque.md ne mentionne pas « $m »"
  done
  [ "$(grep -c '[^[:space:]]' "$RAP")" -ge 18 ] \
    && ok "disque.md couvre les trois tickets" \
    || ko "disque.md fait moins de 18 lignes utiles pour trois tickets"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
