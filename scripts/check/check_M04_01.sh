#!/usr/bin/env bash
# check_M04_01.sh — vérifie le lab L4.1 (onboarding de trois arrivants)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L4.1 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
RAPPORT="$LAB_HOME/lab04/rapports/motsdepasse.txt"

# --- 1. squelette ------------------------------------------------------
if [ -s /etc/skel/BIENVENUE.txt ]; then
  ok "/etc/skel/BIENVENUE.txt est en place"
else
  ko "/etc/skel/BIENVENUE.txt absent ou vide (il doit exister AVANT useradd -m)"
fi
if grep -qE '^[[:space:]]*umask[[:space:]]+0?27' /etc/skel/.bashrc 2>/dev/null
then
  ok "/etc/skel/.bashrc impose umask 027"
else
  ko "umask 027 absent de /etc/skel/.bashrc"
fi

# --- 2. les comptes existent, bien formés ------------------------------
for u in lucie hugo nadia; do
  if ! getent passwd "$u" >/dev/null; then
    ko "compte $u inexistant"
    continue
  fi
  ok "compte $u créé"

  home=$(getent passwd "$u" | cut -d: -f6)
  shell=$(getent passwd "$u" | cut -d: -f7)

  [ -d "$home" ] && ok "  home $home présent" \
                 || ko "  home $home absent (oubli de -m ?)"
  [ -s "$home/BIENVENUE.txt" ] && ok "  $u a reçu BIENVENUE.txt" \
      || ko "  $home/BIENVENUE.txt absent (skel copié seulement à la création)"
  case "$shell" in
    */bash) ok "  shell bash" ;;
    *)      ko "  shell de $u = $shell, attendu /bin/bash (option -s)" ;;
  esac
done

# --- 3. groupes --------------------------------------------------------
for pair in "lucie factura" "hugo factura" "nadia deploy"; do
  set -- $pair
  getent passwd "$1" >/dev/null || continue
  if id -nG "$1" | tr ' ' '\n' | grep -qx "$2"; then
    ok "$1 est membre de $2"
  else
    ko "$1 n'est pas dans $2 (colonne 3 du CSV, option -G)"
  fi
  if id -gn "$1" 2>/dev/null | grep -qx "$1"; then
    ok "$1 a bien un groupe primaire éponyme"
  else
    ko "groupe primaire de $1 = $(id -gn "$1" 2>/dev/null), attendu $1"
  fi
done

# --- 4. mot de passe défini ET à changer -------------------------------
for u in lucie hugo nadia; do
  getent passwd "$u" >/dev/null || continue
  hash=$(getent shadow "$u" | cut -d: -f2)
  last=$(getent shadow "$u" | cut -d: -f3)
  case "$hash" in
    \$*) ok "$u a un mot de passe utilisable" ;;
    *)   ko "$u n'a pas de mot de passe exploitable (champ 2 = '$hash')" ;;
  esac
  if [ "${last:-x}" = "0" ]; then
    ok "$u devra changer son mot de passe à la première connexion"
  else
    ko "$u : champ 3 de shadow = '$last', attendu 0 (chage -d 0, APRÈS chpasswd)"
  fi
done

# --- 5. politique 90 / 1 / 14 ------------------------------------------
for u in lucie hugo nadia; do
  getent passwd "$u" >/dev/null || continue
  max=$(getent shadow "$u" | cut -d: -f5)
  min=$(getent shadow "$u" | cut -d: -f4)
  warn=$(getent shadow "$u" | cut -d: -f6)
  [ "${max:-0}" = "90" ] && ok "$u : âge maxi 90 jours" \
      || ko "$u : âge maxi = '$max', attendu 90 (chage -M 90)"
  [ "${min:-0}" = "1" ] && ok "$u : âge mini 1 jour" \
      || ko "$u : âge mini = '$min', attendu 1 (chage -m 1)"
  [ "${warn:-0}" = "14" ] && ok "$u : avertissement 14 jours" \
      || ko "$u : avertissement = '$warn', attendu 14 (chage -W 14)"
done

# --- 6. valeurs par défaut de la machine -------------------------------
if awk '$1=="PASS_MAX_DAYS"{print $2}' /etc/login.defs | grep -qx 90; then
  ok "login.defs : PASS_MAX_DAYS 90 pour les prochains comptes"
else
  ko "PASS_MAX_DAYS de /etc/login.defs n'est pas à 90"
fi

# --- 7. fichier de mots de passe ---------------------------------------
if [ -f "$RAPPORT" ]; then
  mode=$(stat -c '%a' "$RAPPORT")
  [ "$mode" = "600" ] && ok "$RAPPORT est en 600" \
      || ko "$RAPPORT est en $mode, attendu 600"
  [ "$(grep -c . "$RAPPORT")" -ge 3 ] \
      && ok "les trois mots de passe sont consignés" \
      || ko "moins de 3 lignes dans $RAPPORT"
else
  ko "$RAPPORT absent (les mots de passe générés doivent être consignés)"
fi

# --- 8. idempotence du script ------------------------------------------
SCRIPT="$LAB_HOME/lab04/bin/creer-arrivants.sh"
if [ -f "$SCRIPT" ]; then
  ok "le script creer-arrivants.sh existe"
  avant=$(getent shadow lucie | cut -d: -f2)
  if bash "$SCRIPT" >/dev/null 2>&1; then
    apres=$(getent shadow lucie | cut -d: -f2)
    [ "$avant" = "$apres" ] \
      && ok "relancé, le script ne réinitialise pas les comptes existants" \
      || ko "le script a changé le mot de passe de lucie : il n'est pas idempotent"
  else
    ko "le script échoue quand on le relance (idempotence exigée)"
  fi
else
  note "script $SCRIPT introuvable : idempotence non testée"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
