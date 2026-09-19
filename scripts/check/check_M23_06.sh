#!/usr/bin/env bash
# check_M23_06.sh — vérifie le défi D23 (pilotage / sante-serveur)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D23 =="

PROJ="$HOME/lab23/pilotage"
CMD=/opt/factura/venv/bin/sante-serveur
PY="$HOME/lab23/venv/bin/python"; [ -x "$PY" ] || PY=python3
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

[ -f "$PROJ/pyproject.toml" ] && ok "pyproject.toml présent" || ko "$PROJ/pyproject.toml attendu"
[ -d "$PROJ/src" ] && ok "arborescence src/" || ko "structure src/<paquet>/ attendue"
grep -q 'sante-serveur' "$PROJ/pyproject.toml" 2>/dev/null \
  && ok "[project.scripts] déclare sante-serveur" || ko "déclare sante-serveur dans [project.scripts]"

if [ -x "$CMD" ]; then
  ok "$CMD installé"
  sudo -n true 2>/dev/null && SUDO="sudo -n" || SUDO=""
  $SUDO "$CMD" > "$TMP/out" 2>"$TMP/err"; rc=$?
  [ "$rc" -ge 0 ] && [ "$rc" -le 2 ] && ok "code de sortie $rc (0/1/2)" \
    || ko "code attendu 0, 1 ou 2, obtenu $rc"
  head -1 "$TMP/out" | grep -q '^# ' && ok "stdout commence par un titre Markdown" \
    || ko "le rapport doit être du Markdown sur stdout"
  grep -q '^## VERDICT' "$TMP/out" && ok "section VERDICT présente" || ko "section « ## VERDICT » attendue"
  grep -qi 'inode' "$TMP/out" && ok "les inodes sont rapportés" || ko "usage des inodes attendu"
  grep -qi 'wa=' "$TMP/out" && ok "répartition CPU us/sy/wa/st" || ko "us/sy/wa/st attendus"
  grep -q 'Traceback' "$TMP/err" && ko "Traceback sur stderr" || ok "pas de Traceback"
  grep -Eq 'WARNING|INFO|ERROR' "$TMP/out" && ko "des lignes de journal polluent stdout" \
    || ok "stdout ne contient que le rapport"
else ko "$CMD absent : python3 -m venv /opt/factura/venv && /opt/factura/venv/bin/pip install $PROJ"; fi

if [ -d "$PROJ/tests" ] && "$PY" -m pytest --version >/dev/null 2>&1; then
  if (cd "$PROJ" && PYTHONPATH=src "$PY" -m pytest -q > "$TMP/pt" 2>&1); then
    nt=$(grep -Eo '[0-9]+ passed' "$TMP/pt" | grep -Eo '[0-9]+')
    ok "pytest : $nt tests passent"
    [ "${nt:-0}" -ge 5 ] && ok "au moins 5 tests" || ko "au moins 5 tests attendus"
  else ko "pytest échoue dans $PROJ"; fi
else note "tests/ absent ou pytest indisponible"; fi

if systemctl list-unit-files 2>/dev/null | grep -q '^sante-serveur.timer'; then
  ok "sante-serveur.timer installé"
  systemctl is-enabled sante-serveur.timer >/dev/null 2>&1 && ok "timer activé" \
    || ko "systemctl enable --now sante-serveur.timer"
  grep -q '^ExecStart=/opt/factura/venv/bin/' /etc/systemd/system/sante-serveur.service 2>/dev/null \
    && ok "ExecStart appelle le venv par chemin absolu" \
    || ko "ExecStart=/opt/factura/venv/bin/sante-serveur attendu"
  grep -q 'SuccessExitStatus' /etc/systemd/system/sante-serveur.service 2>/dev/null \
    && ok "SuccessExitStatus : 1 et 2 ne sont pas des plantages" \
    || ko "ajoute SuccessExitStatus=1 2 (un verdict n'est pas un échec)"
else ko "sante-serveur.timer attendu dans /etc/systemd/system/"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
