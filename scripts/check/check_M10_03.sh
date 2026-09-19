#!/usr/bin/env bash
# check_M10_03.sh — vérifie le lab L10.3 (figer une version)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L10.3 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab10/rapports/figer.md"

POL=$(apt-cache policy outil-lab 2>/dev/null)
INST=$(printf '%s' "$POL" | awk '/Installed:/ {print $2}')
CAND=$(printf '%s' "$POL" | awk '/Candidate:/ {print $2}')

# --- 1. la version en place ---------------------------------------------
[ "$INST" = "1.0.0" ] \
  && ok "outil-lab installé en 1.0.0" \
  || ko "version installée : ${INST:-aucune} — on attend 1.0.0 \
(apt install --allow-downgrades outil-lab=1.0.0)"

# --- 2. la version candidate --------------------------------------------
[ "$CAND" = "1.0.0" ] \
  && ok "version candidate ramenée à 1.0.0" \
  || ko "version candidate : ${CAND:-aucune} — tant qu'elle vaut 1.2.0, \
le prochain apt upgrade remontera le paquet"

# --- 3. l'épinglage existe et est lisible --------------------------------
PREF=$(grep -rls 'outil-lab' /etc/apt/preferences.d/ /etc/apt/preferences \
       2>/dev/null | head -1)
if [ -n "$PREF" ]; then
  ok "fichier d'épinglage trouvé : $PREF"
  grep -qiE '^Pin-Priority:[[:space:]]*(100[0-9]|[2-9][0-9]{3})' "$PREF" \
    && ok "priorité supérieure à 1000 (autorise la rétrogradation)" \
    || ko "la priorité de $PREF ne dépasse pas 1000 : apt refusera de \
redescendre une version déjà installée"
  grep -qiE '^Pin:[[:space:]]*version' "$PREF" \
    && ok "épinglage sur une version explicite" \
    || note "l'épinglage ne porte pas sur « Pin: version ... »"
  grep -qiE '^Package:[[:space:]]*\*[[:space:]]*$' "$PREF" \
    && ko "« Package: * » : cet épinglage s'applique à TOUT le système" \
    || ok "l'épinglage ne vise que outil-lab"
else
  ko "aucun fichier d'épinglage ne mentionne outil-lab dans \
/etc/apt/preferences.d/"
fi

# --- 4. apt-mark hold ne doit PAS être utilisé ---------------------------
if apt-mark showhold 2>/dev/null | grep -qx 'outil-lab'; then
  ko "outil-lab est aussi retenu par apt-mark hold : l'énoncé demande de \
figer par épinglage, et d'expliquer la différence — pas de cumuler"
else
  ok "outil-lab n'est pas retenu par apt-mark hold"
fi

# --- 5. une mise à niveau simulée ne bouge plus le paquet ---------------
SIM=$(apt-get -s upgrade 2>/dev/null)
if printf '%s' "$SIM" | grep -qE '^(Inst|Conf) outil-lab'; then
  ko "apt-get -s upgrade propose toujours de toucher à outil-lab"
else
  ok "apt-get -s upgrade ne touche plus à outil-lab"
fi
if printf '%s' "$SIM" | grep -q 'will be DOWNGRADED'; then
  ko "la simulation propose des rétrogradations : ton épinglage déborde \
sur d'autres paquets"
else
  ok "aucune rétrogradation collatérale"
fi

# --- 6. le rapport -------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 8 ]; then
  ok "rapport figer.md rédigé"
  grep -qi 'hold' "$RAP" \
    && ok "le rapport parle de apt-mark hold" \
    || ko "le rapport doit comparer l'épinglage et apt-mark hold"
  grep -qiE 'madison|policy' "$RAP" \
    && ok "le rapport cite la commande de contrôle des versions" \
    || note "cite apt-cache madison ou apt-cache policy dans la procédure"
else
  ko "rapport absent ou trop court : ~/lab10/rapports/figer.md (8 lignes)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
