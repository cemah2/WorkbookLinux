#!/usr/bin/env bash
# check_M07_04.sh — vérifie le lab L7.4 (exec-tracee.sh : "$@", codes, signaux)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L7.4 =="

S="$HOME/lab07/bin/exec-tracee.sh"
JOURNAL="$HOME/lab07/var/exec.log"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$S" ]; then
  ko "$S est absent"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "le script existe"
[ -x "$S" ] && ok "le script est exécutable" \
            || ko "il manque le bit d'exécution (chmod +x)"

# --- 1. transmission des arguments --------------------------------------
"$S" -- printf '[%s]\n' 'a b' c > "$TMP/args" 2>/dev/null
if [ "$(grep -c . "$TMP/args")" -eq 2 ] && grep -qxF '[a b]' "$TMP/args"; then
  ok "les arguments passent intacts (« a b » reste un seul argument)"
else
  ko "attendu deux lignes dont « [a b] » : tu utilises \$* ou \$@ non quoté"
fi

# --- 2. propagation du code de sortie -----------------------------------
"$S" -- sh -c 'exit 7' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "code de la commande propagé (7)" \
                || ko "code 7 attendu, obtenu $rc"

"$S" -- true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "succès propagé (0)" || ko "code 0 attendu, obtenu $rc"

"$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "aucune commande fournie -> code 2" \
                || ko "sans commande : code 2 attendu, obtenu $rc"

# --- 3. la sortie de la commande n'est pas polluée ----------------------
"$S" -- echo bonjour > "$TMP/pur" 2>/dev/null
if [ "$(cat "$TMP/pur")" = "bonjour" ]; then
  ok "stdout de la commande reste intact (journal sur stderr)"
else
  ko "stdout pollué : « $(head -1 "$TMP/pur") » — le journal va sur stderr"
fi

# --- 4. journal local ----------------------------------------------------
: > "$JOURNAL" 2>/dev/null || true
"$S" -t verif-m07 -- sh -c 'exit 3' >/dev/null 2>&1
if [ -s "$JOURNAL" ]; then
  ok "le journal local $JOURNAL est alimenté"
else
  ko "rien dans ~/lab07/var/exec.log après une exécution"
fi
if grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' \
     "$JOURNAL" 2>/dev/null; then
  ok "les lignes sont horodatées au format ISO 8601"
else
  ko "horodatage ISO attendu (date +%Y-%m-%dT%H:%M:%S%:z)"
fi
if grep -q '3' "$JOURNAL" 2>/dev/null && \
   grep -Eqi 'error|echec|échec|code' "$JOURNAL"; then
  ok "l'échec (code 3) est tracé dans le journal"
else
  ko "le journal ne mentionne pas le code de retour en cas d'échec"
fi

# --- 5. signaux ----------------------------------------------------------
"$S" -- sleep 30 >/dev/null 2>&1 &
BG=$!
sleep 1
if kill -TERM "$BG" 2>/dev/null; then
  wait "$BG"; rc=$?
  [ "$rc" -eq 143 ] && ok "SIGTERM -> code 143 (128+15)" \
                    || ko "après SIGTERM, code 143 attendu, obtenu $rc"
else
  ko "impossible d'envoyer SIGTERM au script"
fi
if pgrep -u "$(id -un)" -f '^sleep 30$' >/dev/null 2>&1; then
  ko "un « sleep 30 » survit au script : le trap doit tuer la commande fille"
  pkill -u "$(id -un)" -f '^sleep 30$' 2>/dev/null || true
else
  ok "aucune commande fille orpheline après le signal"
fi

# --- 6. syslog -----------------------------------------------------------
if command -v journalctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  if journalctl -t verif-m07 -n 20 --no-pager 2>/dev/null | grep -q .; then
    ok "les évènements arrivent dans syslog (tag verif-m07)"
  else
    ko "rien dans journalctl -t verif-m07 : utilise logger -t \"\$TAG\""
  fi
elif [ -r /var/log/syslog ] && grep -q 'verif-m07' /var/log/syslog; then
  ok "les évènements arrivent dans /var/log/syslog"
else
  note "journald indisponible ici : contrôle syslog ignoré"
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$S" >/dev/null 2>&1 \
    && ok "shellcheck ne signale rien" \
    || ko "shellcheck remonte des avertissements : shellcheck $S"
else
  note "shellcheck n'est pas installé (sudo apt install -y shellcheck)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
