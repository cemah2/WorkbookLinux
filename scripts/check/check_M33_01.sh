#!/usr/bin/env bash
# check_M33_01.sh — vérifie le lab L33.1 (compiler proprement)
# À lancer sur lab-adm, en tant que mathieu (sans sudo).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L33.1 =="
H=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)/lab33

# --- 1. compilation dans l'arborescence des sources ----------------------------
S="$H/src/lab33-sante-1.0"
B="$S/lab33-sante"
if [ -x "$B" ]; then
  ok "binaire compilé dans lab33/src/lab33-sante-1.0"
  "$B" --version 2>/dev/null | has -x 'lab33-sante 1.0' && ok "le binaire répond à --version (1.0)" \
                                                      || ko "lab33-sante --version ne répond pas « lab33-sante 1.0 »"
  # --- 4. durcissement ---------------------------------------------------------
  readelf -h "$B" 2>/dev/null | has -E 'Type:[[:space:]]+DYN' && ok "exécutable PIE" || ko "binaire non PIE"
  readelf -d "$B" 2>/dev/null | has -E 'BIND_NOW|FLAGS.*NOW' && ok "RELRO complet (BIND_NOW)" \
                                                          || ko "pas de BIND_NOW (RELRO partiel)"
  nm -D "$B" 2>/dev/null | has '__stack_chk_fail' && ok "canari de pile présent" || ko "pas de canari de pile"
  nm -D "$B" 2>/dev/null | has -E '__[a-z]+_chk@' && ok "fonctions _FORTIFY_SOURCE présentes" \
                                                  || ko "pas de fonctions __*_chk (FORTIFY : compile avec -O2)"
  strings -a "$B" | has -x '/etc/lab33-sante.conf' \
    && ok "dernière compilation avec PREFIX=/usr (étape 4)" \
    || note "le binaire des sources ne vise pas /etc/lab33-sante.conf (dernière compilation sans PREFIX=/usr)"
else
  ko "pas de binaire exécutable lab33/src/lab33-sante-1.0/lab33-sante"
fi

# --- 3. installation de transit --------------------------------------------------
T="$H/transit"
manque=0
for f in usr/bin/lab33-sante etc/lab33-sante.conf usr/share/man/man1/lab33-sante.1 \
         usr/lib/systemd/system/lab33-sante.service usr/lib/systemd/system/lab33-sante.timer \
         usr/lib/sysusers.d/lab33-sante.conf; do
  [ -e "$T/$f" ] || { ko "transit : $f manquant"; manque=1; }
done
[ "$manque" -eq 0 ] && ok "arborescence de transit complète (6 fichiers)"
if [ -e "$T/usr/bin/lab33-sante" ]; then
  strings -a "$T/usr/bin/lab33-sante" | has -x '/etc/lab33-sante.conf' \
    && ok "le binaire de transit cherche /etc/lab33-sante.conf" \
    || ko "le binaire de transit ne cherche pas /etc/lab33-sante.conf (PREFIX=/usr à la compilation ?)"
fi
if [ -e "$T/usr/lib/systemd/system/lab33-sante.service" ]; then
  has -x 'ExecStart=/usr/bin/lab33-sante' "$T/usr/lib/systemd/system/lab33-sante.service" \
    && ok "l'unité de transit lance /usr/bin/lab33-sante" \
    || ko "l'unité de transit ne lance pas /usr/bin/lab33-sante (unité générée sans PREFIX=/usr)"
fi
[ -e "$T/usr/local" ] && ko "transit contient usr/local (PREFIX non passé)" || ok "rien sous transit/usr/local"

# --- 2. /usr/local propre après désinstallation ------------------------------------
reste=""
for f in /usr/local/bin/lab33-sante /usr/local/etc/lab33-sante.conf \
         /usr/local/share/man/man1/lab33-sante.1 /usr/local/lib/systemd/system/lab33-sante.service \
         /usr/local/lib/systemd/system/lab33-sante.timer /usr/local/lib/sysusers.d/lab33-sante.conf; do
  [ -e "$f" ] && reste="$reste $f"
done
[ -z "$reste" ] && ok "/usr/local propre (aucun fichier de lab33-sante)" || ko "reste dans /usr/local :$reste"

# --- 5. rapport ----------------------------------------------------------------------
R="$H/compilation.md"
if [ -s "$R" ]; then
  ok "compilation.md présent"
  [ "$(grep -c '[^[:space:]]' "$R")" -ge 5 ] && ok "rapport d'au moins 5 lignes" || ko "rapport trop court"
  has -i 'libc' "$R" && ok "le rapport cite les dépendances d'exécution" || ko "le rapport ne cite pas les dépendances (ldd)"
  has -Ei 'pie|relro|bind_now|fortify|canari|stack' "$R" && ok "le rapport décrit les protections" \
                                                        || ko "le rapport ne décrit pas les protections"
  has -i 'make install' "$R" && ok "le rapport explique le problème de make install" \
                             || ko "le rapport n'explique pas pourquoi « make install » dans /usr est proscrit"
else
  ko "lab33/compilation.md absent"
fi
fin
