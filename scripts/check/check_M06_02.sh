#!/usr/bin/env bash
# check_M06_02.sh — vérifie le lab L6.2 (extraction d'un rapport d'incident)
# On vérifie le CONTENU FINAL du fichier, jamais la méthode employée.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L6.2 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
F="$HOMEDIR/lab06/edition/inc-4488.log"

[ -s "$F" ] || { ko "$F absent ou vide (cp app.log inc-4488.log puis vim)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# corps = tout sauf les lignes de commentaire (#)
CORPS=$(grep -v '^#' "$F" | grep -v '^[[:space:]]*$')

# --- 1. bruit supprimé ----------------------------------------------------
for MOT in DEBUG INFO; do
  if printf '%s\n' "$CORPS" | grep -q "$MOT"; then
    ko "il reste des lignes $MOT (:g/$MOT/d)"
  else
    ok "plus aucune ligne $MOT"
  fi
done

# --- 2. ce qu'on garde ----------------------------------------------------
NB_ERR=$(printf '%s\n' "$CORPS" | grep -c 'ERROR')
NB_WARN=$(printf '%s\n' "$CORPS" | grep -c 'WARN')
[ "$NB_ERR" -ge 5 ] && ok "$NB_ERR lignes ERROR conservées" || \
  ko "seulement $NB_ERR ligne(s) ERROR : elles devaient toutes être gardées"
[ "$NB_WARN" -ge 8 ] && ok "$NB_WARN lignes WARN conservées" || \
  ko "seulement $NB_WARN ligne(s) WARN : elles devaient toutes être gardées"

# --- 3. annotation des ERROR ---------------------------------------------
MANQUE=$(printf '%s\n' "$CORPS" | grep 'ERROR' | grep -vc '\[INC-4488\]$')
if [ "$MANQUE" -eq 0 ]; then
  ok "toutes les lignes ERROR se terminent par [INC-4488]"
else
  ko "$MANQUE ligne(s) ERROR sans l'annotation finale \
(:g/ERROR/normal A  [INC-4488])"
fi
if printf '%s\n' "$CORPS" | grep 'WARN' | grep -q '\[INC-4488\]'; then
  ko "des lignes WARN ont été annotées : seules les ERROR devaient l'être"
else
  ok "les lignes WARN n'ont pas été annotées"
fi

# --- 4. horodatage raccourci ---------------------------------------------
if printf '%s\n' "$CORPS" | grep -q '2026-09-17T'; then
  ko "l'horodatage complet 2026-09-17T.. est toujours là (capture \\1 attendue)"
else
  ok "l'horodatage complet a été remplacé"
fi
BON=$(printf '%s\n' "$CORPS" | grep -cE '^04:[0-9]{2}[[:space:]]')
TOT=$(printf '%s\n' "$CORPS" | grep -c .)
if [ "$TOT" -gt 0 ] && [ "$BON" -eq "$TOT" ]; then
  ok "les $TOT lignes commencent par l'heure au format 04:MM"
else
  ko "$BON/$TOT lignes au format 04:MM en tête"
fi

# --- 5. worker= supprimé --------------------------------------------------
if printf '%s\n' "$CORPS" | grep -q 'worker='; then
  ko "la mention worker=N est toujours présente (:%s/worker=[0-9]* //)"
else
  ok "plus aucune mention worker="
fi

# --- 6. trié et dédoublonné ----------------------------------------------
DUP=$(printf '%s\n' "$CORPS" | sort | uniq -d | grep -c .)
if [ "$DUP" -eq 0 ]; then
  ok "aucun doublon strict"
else
  ko "$DUP ligne(s) en double subsistent (:sort u)"
fi
if printf '%s\n' "$CORPS" | sort -c 2>/dev/null; then
  ok "le corps du fichier est trié"
else
  ko "le corps n'est pas trié (:sort u)"
fi

# --- 7. en-tête daté ------------------------------------------------------
TETE=$(head -1 "$F")
if printf '%s' "$TETE" | grep -q 'INC-4488'; then
  ok "la première ligne est l'en-tête INC-4488"
else
  ko "la première ligne n'est pas l'en-tête attendu (:0r !echo ...)"
fi
if printf '%s' "$TETE" | grep -qE '(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}'; then
  ok "l'en-tête porte une date réelle"
else
  ko "pas de date au format AAAA-MM-JJ dans l'en-tête"
fi
if printf '%s' "$TETE" | grep -qi "$(hostname -s)"; then
  ok "l'en-tête porte le nom d'hôte"
else
  note "le nom d'hôte ($(hostname -s)) n'apparaît pas dans l'en-tête"
fi

# --- 8. volume plausible --------------------------------------------------
NL=$(grep -c . "$F")
if [ "$NL" -ge 10 ] && [ "$NL" -le 45 ]; then
  ok "$NL lignes au total : volume cohérent"
else
  ko "$NL lignes : on attendait une vingtaine de lignes plus l'en-tête"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
