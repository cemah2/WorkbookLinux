#!/usr/bin/env bash
# check_M09_04.sh — vérifie le lab L9.4 (compiler puis empaqueter)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.4 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab09/rapports/compilation.md"
PAQDIR="$HOMEDIR/lab09/paquets"

# --- 1. le paquet construit ---------------------------------------------
DEB=$(ls "$PAQDIR"/horodate*.deb 2>/dev/null | head -1)
if [ -n "$DEB" ]; then
  ok "paquet construit : $(basename "$DEB")"
  CTRL=$(dpkg-deb -f "$DEB" 2>/dev/null)
  printf '%s' "$CTRL" | grep -qi '^Version:.*1\.4' \
    && ok "le champ Version reprend la version amont (1.4)" \
    || ko "le champ Version du paquet ne contient pas 1.4"
  printf '%s' "$CTRL" | grep -qi '^Maintainer:' \
    && ok "champ Maintainer renseigné" \
    || ko "champ Maintainer absent du control"
  if dpkg-deb -c "$DEB" 2>/dev/null | grep -q './usr/local/bin/horodate'; then
    ok "le paquet livre /usr/local/bin/horodate"
  else
    ko "le paquet ne contient pas ./usr/local/bin/horodate — utilise \
make install DESTDIR=... avec --prefix=/usr/local"
  fi
  if dpkg-deb -c "$DEB" 2>/dev/null | grep -qE ' \./usr/bin/'; then
    ko "le paquet écrit dans /usr/bin : ce territoire appartient à la \
distribution, pas à toi"
  else
    ok "le paquet ne touche pas à /usr/bin"
  fi
else
  ko "aucun paquet horodate*.deb dans ~/lab09/paquets/"
fi

# --- 2. le paquet est installé et suivi par dpkg -------------------------
PKG=$(dpkg-query -W -f '${binary:Package}\n' 2>/dev/null \
      | grep -i '^horodate' | head -1)
if [ -n "$PKG" ]; then
  ok "paquet installé et connu de dpkg : $PKG"
  ETAT=$(dpkg-query -f '${db:Status-Abbrev}' -W "$PKG" 2>/dev/null)
  [ "$ETAT" = "ii " ] && ok "état ii" || ko "état « $ETAT », on attend ii"
else
  ko "aucun paquet horodate installé : dpkg -i ton .deb"
fi

# --- 3. le binaire répond et appartient au paquet ------------------------
BIN=/usr/local/bin/horodate
if [ -x "$BIN" ]; then
  ok "$BIN est exécutable"
  V=$("$BIN" --version 2>/dev/null)
  [ "$V" = "horodate 1.4" ] \
    && ok "horodate --version répond « horodate 1.4 »" \
    || ko "horodate --version répond « ${V:-rien} »"
  if dpkg -S "$BIN" >/dev/null 2>&1; then
    ok "dpkg -S $BIN retrouve le paquet propriétaire"
  else
    ko "dpkg -S $BIN ne trouve rien : le binaire a été posé par un \
make install sauvage, pas par un paquet"
  fi
else
  ko "$BIN absent ou non exécutable"
fi

# --- 4. aucune trace du make install direct ------------------------------
for f in /usr/bin/horodate /usr/local/bin/horodate.old; do
  [ -e "$f" ] && ko "résidu à nettoyer : $f"
done
ORPH=$(ls -1 /usr/local/bin 2>/dev/null | while read -r f; do
         dpkg -S "/usr/local/bin/$f" >/dev/null 2>&1 || echo "$f"
       done | wc -l)
[ "$ORPH" -eq 0 ] \
  && ok "aucun binaire non suivi dans /usr/local/bin" \
  || note "$ORPH binaire(s) de /usr/local/bin ne sont suivis par aucun \
paquet — acceptable, mais sache-le"

# --- 5. le rapport --------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 10 ]; then
  ok "rapport compilation.md rédigé"
  grep -qi 'DESTDIR' "$RAP" \
    && ok "le rapport explique DESTDIR" \
    || ko "le rapport doit expliquer le rôle de DESTDIR"
  grep -qiE 'prefix' "$RAP" \
    && ok "le rapport explique --prefix" \
    || ko "le rapport doit expliquer --prefix et le choix de /usr/local"
  grep -qiE 'desinstall|désinstall|uninstall|purge' "$RAP" \
    && ok "le rapport décrit la désinstallation" \
    || ko "le rapport doit décrire comment on retire proprement l'outil"
else
  ko "rapport absent ou trop court : ~/lab09/rapports/compilation.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
