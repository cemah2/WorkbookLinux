#!/usr/bin/env bash
# check_M09_02.sh — vérifie le lab L9.2 (dépôt interne signé)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.2 =="

SRC=$(grep -rslE '^(Types:|deb )' /etc/apt/sources.list.d/ 2>/dev/null \
      | xargs -r grep -rls 'depot-lab\|8099' 2>/dev/null | head -1)

# --- 1. la source est déclarée, et au format deb822 ---------------------
if [ -n "$SRC" ]; then
  ok "source du dépôt déclarée : $SRC"
  case "$SRC" in
    *.sources) ok "format deb822 (.sources)" ;;
    *.list)    ko "$SRC est au format une-ligne : l'énoncé demande un \
fichier .sources deb822" ;;
  esac
else
  ko "aucun fichier de /etc/apt/sources.list.d/ ne référence le dépôt"
fi

# --- 2. la clé : signed-by, keyrings, et rien d'autre -------------------
KEYF=""
if [ -n "$SRC" ]; then
  KEYF=$(grep -iE '^Signed-By:' "$SRC" 2>/dev/null | awk '{print $2}')
  [ -z "$KEYF" ] && KEYF=$(grep -oE 'signed-by=[^]" ]+' "$SRC" 2>/dev/null \
                           | cut -d= -f2)
fi
if [ -n "$KEYF" ]; then
  ok "la source désigne un trousseau : $KEYF"
  case "$KEYF" in
    /etc/apt/keyrings/*|/usr/share/keyrings/*)
      ok "le trousseau est dans un répertoire keyrings" ;;
    *) ko "$KEYF n'est ni dans /etc/apt/keyrings ni dans \
/usr/share/keyrings" ;;
  esac
  if [ -r "$KEYF" ]; then
    ok "le trousseau est lisible"
    PERM=$(stat -c '%a' "$KEYF")
    case "$PERM" in
      644|444|664) ok "permissions $PERM (lisible par _apt)" ;;
      *) ko "permissions $PERM : _apt doit pouvoir lire le trousseau \
(0644 attendu)" ;;
    esac
    if gpg --show-keys --with-colons "$KEYF" 2>/dev/null \
         | grep -q 'depot@lab.local'; then
      ok "le trousseau contient bien la clé depot@lab.local"
    else
      ko "le trousseau ne contient pas la clé du dépôt \
(gpg --show-keys $KEYF)"
    fi
  else
    ko "$KEYF est introuvable ou illisible"
  fi
else
  ko "la source ne comporte ni Signed-By: ni [signed-by=...] : sans lui, \
la clé vaut pour TOUS les dépôts de la machine"
fi

# --- 3. aucune clé posée dans le trousseau global -----------------------
if ls /etc/apt/trusted.gpg.d/ 2>/dev/null | grep -qi 'depot\|lab'; then
  ko "une clé du lab traîne dans /etc/apt/trusted.gpg.d : elle serait \
acceptée pour n'importe quel dépôt"
else
  ok "rien du lab dans /etc/apt/trusted.gpg.d"
fi
if [ -s /etc/apt/trusted.gpg ] && \
   gpg --show-keys /etc/apt/trusted.gpg 2>/dev/null \
     | grep -q 'depot@lab.local'; then
  ko "la clé est dans /etc/apt/trusted.gpg (méthode apt-key, obsolète)"
else
  ok "pas de clé du lab dans /etc/apt/trusted.gpg"
fi

# --- 4. apt update passe sans avertissement GPG -------------------------
SORTIE=$(apt-get update 2>&1)
if printf '%s' "$SORTIE" | grep -qi 'NO_PUBKEY\|is not signed\|GPG error'; then
  ko "apt update signale encore un problème de signature"
  printf '%s\n' "$SORTIE" | grep -i 'NO_PUBKEY\|not signed\|GPG error' \
    | head -2 | sed 's/^/         /'
else
  ok "apt update ne signale aucun problème de signature"
fi

# --- 5. le paquet vient bien du dépôt interne ---------------------------
POL=$(apt-cache policy outil-lab 2>/dev/null)
if printf '%s' "$POL" | grep -q 'Installed: 1\.'; then
  ok "outil-lab est installé ($(printf '%s' "$POL" \
      | awk '/Installed:/ {print $2}'))"
else
  ko "outil-lab n'est pas installé (apt install outil-lab)"
fi
if printf '%s' "$POL" | grep -qE '(8099|/srv/depot-lab)'; then
  ok "le dépôt interne est bien une source de outil-lab"
else
  ko "apt-cache policy outil-lab ne montre pas le dépôt interne"
fi

# --- 6. le paquet vient du dépôt, pas d'un dpkg -i ----------------------
if apt-cache policy outil-lab 2>/dev/null \
     | grep -A1 '^ \*\*\*' | grep -qE '8099|/srv/depot-lab'; then
  ok "la version installée est attribuée au dépôt, pas à un dpkg -i"
else
  note "la version installée n'est rattachée à aucun dépôt : \
tu l'as sans doute posée avec dpkg -i"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
