#!/usr/bin/env bash
# check_M10_01.sh — vérifie le lab L10.1 (inventaire du parc)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L10.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab10/rapports/inventaire.md"
SCR="$HOMEDIR/lab10/bin/inventaire.sh"

# --- 1. le script -------------------------------------------------------
if [ -f "$SCR" ]; then
  ok "$SCR existe"
  [ -x "$SCR" ] && ok "script exécutable" \
    || ko "script non exécutable (chmod +x)"
  head -1 "$SCR" | grep -q '^#!' \
    && ok "shebang présent" || ko "pas de shebang en première ligne"
  SORTIE=$(bash "$SCR" 2>/dev/null)
  if [ -n "$SORTIE" ]; then
    ok "le script produit une sortie"
  else
    ko "le script n'écrit rien sur stdout"
  fi
else
  ko "$SCR introuvable"
  SORTIE=""
fi

# --- 2. le rapport ------------------------------------------------------
if [ -s "$RAP" ]; then
  ok "$RAP existe"
else
  ko "rapport absent : ~/lab10/rapports/inventaire.md"
fi

TITRES="Paquets installés|Installés manuellement|États anormaux"
TITRES="$TITRES|Hors dépôt officiel|Conffiles modifiés"
MANQUE=""
for t in "Paquets installés" "Installés manuellement" "États anormaux" \
         "Hors dépôt officiel" "Conffiles modifiés"; do
  grep -qF "$t" "$RAP" 2>/dev/null || MANQUE="$MANQUE « $t »"
done
if [ -z "$MANQUE" ]; then
  ok "les cinq sections imposées sont présentes"
else
  ko "section(s) manquante(s) dans le rapport :$MANQUE"
fi

# --- 3. les chiffres sont-ils plausibles ? ------------------------------
REEL=$(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)
if grep -qE "\b$REEL\b" "$RAP" 2>/dev/null; then
  ok "le nombre de paquets du rapport ($REEL) correspond au système"
else
  ko "le rapport ne contient pas le nombre réel de paquets ($REEL) — \
compte avec dpkg-query -W, pas avec dpkg -l dont l'en-tête fait 5 lignes"
fi

# --- 4. états anormaux --------------------------------------------------
ANORMAUX=$(dpkg-query -f '${db:Status-Abbrev} ${binary:Package}\n' -W \
           2>/dev/null | grep -cv '^ii ')
if [ "$ANORMAUX" -eq 0 ]; then
  note "aucun paquet en état anormal sur cette machine : la section \
« États anormaux » doit le dire explicitement"
else
  note "$ANORMAUX paquet(s) en état anormal : ils doivent figurer nommément"
fi

# --- 5. hors dépôt officiel ---------------------------------------------
if command -v apt-cache >/dev/null 2>&1; then
  HORS=$(apt-mark showmanual 2>/dev/null | while read -r p; do
    apt-cache policy "$p" 2>/dev/null \
      | awk -v P="$p" '/^ +\*\*\*/ {v=$2} /http|file:/ {t=1}
                       END {if (!t) print P}'
  done | wc -l)
  note "paquets sans dépôt d'origine détectés côté check : $HORS"
fi

# --- 6. le rapport n'est pas une copie brute de dpkg -l ------------------
if [ -s "$RAP" ] && grep -q 'Desired=Unknown/Install/Remove/Purge/Hold' \
     "$RAP" 2>/dev/null; then
  ko "le rapport contient l'en-tête brut de dpkg -l : c'est un rapport, \
pas un copier-coller de sortie"
else
  ok "pas de copier-coller brut de dpkg -l"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
