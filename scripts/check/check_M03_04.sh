#!/usr/bin/env bash
# check_M03_04.sh — vérifie le lab L3.4 (capability au lieu de SUID)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L3.4 =="

API=/usr/local/bin/factura-api
HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)

[ -x "$API" ] || { ko "$API absent (relance setup_M03.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

if ! command -v getcap >/dev/null 2>&1; then
  note "getcap/setcap absents : installe libcap2-bin (voir §3.1)"
fi

# --- 1. la capability cap_net_bind_service est posée --------------------
if command -v getcap >/dev/null 2>&1; then
  if getcap "$API" 2>/dev/null | grep -q 'cap_net_bind_service'; then
    ok "cap_net_bind_service est présente sur $API"
  else
    ko "cap_net_bind_service absente (setcap cap_net_bind_service=+ep $API)"
  fi
fi

# --- 2. le binaire n'est PAS SUID (la mauvaise solution) ----------------
if printf '%s' "$(stat -c '%A' "$API")" | grep -q '^...s'; then
  ko "$API est SUID : la solution attendue est la capability, pas le SUID"
else
  ok "$API n'est pas SUID (bonne approche)"
fi

# --- 3. bind réel du port 80 en tant qu'utilisateur non root ------------
TESTU="facturation"; getent passwd "$TESTU" >/dev/null || TESTU="webdev"
if command -v ss >/dev/null 2>&1; then
  sudo -u "$TESTU" "$API" --port 80 >/dev/null 2>&1 &
  pid=$!
  sleep 1
  if ss -tlnp 2>/dev/null | grep -q ':80 '; then
    ok "le port 80 est en écoute, lancé par $TESTU (non root)"
  else
    ko "le port 80 n'est pas en écoute : la capability ne s'applique pas"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
else
  note "ss indisponible : contrôle du bind port 80 ignoré"
fi

# --- 4. rapport ---------------------------------------------------------
RAP="$HOMEDIR/lab03/rapports/capability.md"
if [ -s "$RAP" ]; then
  ok "le rapport capability.md est présent"
else
  ko "rapport ~/lab03/rapports/capability.md absent"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
