#!/usr/bin/env bash
# check_M01_04.sh — vérifie le lab L1.4 (cartographie des environnements)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L1.4 =="

CARTO="$HOME/lab01/cartographie.md"
TRACE="$HOME/lab01/logs/startup.log"

# --- 1. trace d'instrumentation -----------------------------------------
if [ -s "$TRACE" ]; then
  ok "la trace $TRACE existe et n'est pas vide"
else
  ko "trace absente ou vide : instrumente .profile / .bashrc (étape 1)"
fi

for f in ".bashrc" ".profile"; do
  if grep -q "$f" "$TRACE" 2>/dev/null; then
    ok "le passage dans ~/$f a été tracé"
  else
    ko "aucune trace de ~/$f : le fichier est-il instrumenté ?"
  fi
done

# --- 2. cartographie ----------------------------------------------------
if [ -s "$CARTO" ]; then
  ok "$CARTO existe"
else
  ko "~/lab01/cartographie.md absent (étape 3)"
fi

manquants=""
for mot in "login" "interactif" "ssh" "bashrc"; do
  grep -qi -- "$mot" "$CARTO" 2>/dev/null || manquants="$manquants $mot"
done
if [ -z "$manquants" ]; then
  ok "la cartographie couvre les quatre situations"
else
  ko "la cartographie ne mentionne pas :$manquants"
fi

# --- 3. JAVA_HOME -------------------------------------------------------
v_login=$(bash -lc 'printf %s "${JAVA_HOME:-}"' 2>/dev/null)
if [ "$v_login" = "/opt/jdk21" ]; then
  ok "JAVA_HOME vaut /opt/jdk21 dans un shell de login"
else
  ko "JAVA_HOME = '${v_login}' dans un shell de login (attendu /opt/jdk21)"
fi

if grep -q '^JAVA_HOME=/opt/jdk21' /etc/environment 2>/dev/null; then
  ok "JAVA_HOME est posé dans /etc/environment (couvre aussi cron)"
else
  printf '  [INFO] JAVA_HOME absent de /etc/environment : cron ne le verra\n'
  printf '         pas. Acceptable si la consigne shell seule a été suivie.\n'
fi

if command -v ssh >/dev/null 2>&1 &&
   ssh -o BatchMode=yes -o ConnectTimeout=3 "$USER@localhost" true \
       >/dev/null 2>&1; then
  r=$(ssh -o BatchMode=yes "$USER@localhost" 'echo $JAVA_HOME' 2>/dev/null)
  if [ "$r" = "/opt/jdk21" ]; then
    ok "ssh localhost 'echo \$JAVA_HOME' renvoie /opt/jdk21"
  else
    ko "en SSH non interactif, JAVA_HOME = '$r' (place-le au-dessus de la
         garde case \$- ou dans /etc/environment)"
  fi
else
  printf '  [SKIP] ssh vers localhost indisponible, test ignoré\n'
fi

# --- 4. pas de pollution de stdout --------------------------------------
bruit=$(bash -lc 'true' 2>/dev/null)
if [ -z "$bruit" ]; then
  ok "l'instrumentation n'écrit rien sur stdout"
else
  ko "les traces partent sur stdout et casseront scp/rsync"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
