#!/usr/bin/env bash
# check_M08_03.sh — vérifie le lab L8.3 (choisir le bon Type=)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L8.3 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab08/rapports/types.md"

[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : ce lab est inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

v() { systemctl show -p "$2" --value "$1" 2>/dev/null; }

# --- 1. factura-collecte : oneshot + RemainAfterExit --------------------
U=factura-collecte.service
if systemctl cat "$U" >/dev/null 2>&1; then
  ok "$U existe"
  [ "$(v "$U" Type)" = oneshot ] \
    && ok "collecte : Type=oneshot" \
    || ko "collecte : Type=$(v "$U" Type) — le traitement se termine, il ne \
tourne pas en continu"
  [ "$(v "$U" RemainAfterExit)" = yes ] \
    && ok "collecte : RemainAfterExit=yes" \
    || ko "collecte : sans RemainAfterExit=yes, l'unité retombe en inactive \
dès la fin du traitement"
  # ExecStartPre= ou une directive Condition*/Assert* : les deux répondent
  # à « une directive dédiée, pas un test dans le script ».
  if [ -n "$(v "$U" ExecStartPre)" ] || \
     systemctl cat "$U" 2>/dev/null | grep -Eq '^(Condition|Assert)Path'; then
    ok "collecte : contrôle de /srv/factura/data par une directive dédiée"
  else
    ko "collecte : le contrôle de /srv/factura/data doit passer par \
ExecStartPre= (ou ConditionPathIsDirectory=), pas par le script"
  fi
  ETAT="$(systemctl is-active "$U" 2>/dev/null)"
  SUB="$(v "$U" SubState)"
  if [ "$ETAT" = active ] && [ "$SUB" = exited ]; then
    ok "collecte : active (exited) — état « fait » conservé"
  else
    ko "collecte : état « $ETAT ($SUB) », on attend active (exited) — \
lance-la au moins une fois"
  fi
else
  ko "$U introuvable"
fi

# --- 2. factura-legacy : forking + PIDFile + RuntimeDirectory -----------
U=factura-legacy.service
if systemctl cat "$U" >/dev/null 2>&1; then
  ok "$U existe"
  [ "$(v "$U" Type)" = forking ] \
    && ok "legacy : Type=forking" \
    || ko "legacy : Type=$(v "$U" Type) — ce démon se détache tout seul"
  PF="$(v "$U" PIDFile)"
  [ -n "$PF" ] \
    && ok "legacy : PIDFile=$PF" \
    || ko "legacy : sans PIDFile=, systemd devine mal le processus principal"
  [ "$(v "$U" RuntimeDirectory)" = factura ] \
    && ok "legacy : RuntimeDirectory=factura (systemd crée /run/factura)" \
    || ko "legacy : RuntimeDirectory=factura attendu, pour que /run/factura \
soit créé et nettoyé par systemd"
  if [ "$(systemctl is-active "$U" 2>/dev/null)" = active ] && \
     [ "$(v "$U" SubState)" = running ]; then
    ok "legacy : active (running)"
  else
    ko "legacy : le service n'est pas active (running)"
  fi
  MP="$(v "$U" MainPID)"
  if [ -n "$PF" ] && [ -r "$PF" ]; then
    FP="$(tr -dc '0-9' < "$PF")"
    [ -n "$MP" ] && [ "$MP" = "$FP" ] \
      && ok "legacy : MainPID ($MP) = contenu du fichier de PID" \
      || ko "legacy : MainPID=$MP mais le fichier contient $FP — systemd ne \
suit pas le bon processus"
  else
    ko "legacy : fichier de PID illisible ($PF)"
  fi
else
  ko "$U introuvable"
fi

# --- 3. le rapport ------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 6 ]; then
  ok "rapport types.md rédigé"
  grep -qi 'notify' "$RAP" || \
    note "le rapport ne mentionne pas Type=notify (point 4 de l'énoncé)"
else
  ko "rapport absent ou trop court : ~/lab08/rapports/types.md (6 lignes min)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
