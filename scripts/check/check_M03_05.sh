#!/usr/bin/env bash
# check_M03_05.sh — vérifie le Défi D3 (durcissement du service factura)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D3 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
WEB=/var/www/factura
CONF=/etc/factura/factura.conf
SECRETS=/etc/factura/secrets
EXPORTS=/srv/factura/exports
API=/usr/local/bin/factura-api

# --- 1. le script existe et est exécutable ------------------------------
SC="$HOMEDIR/lab03/bin/durcir-factura.sh"
if [ -s "$SC" ]; then
  ok "le script durcir-factura.sh est présent"
  head -1 "$SC" | grep -q 'env bash' && \
    ok "shebang #!/usr/bin/env bash présent" || \
    ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$SC" && \
    ok "set -euo pipefail présent" || \
    ko "set -euo pipefail manquant"
else
  ko "script ~/lab03/bin/durcir-factura.sh absent"
fi

# --- 2. arbo web : aucun fichier exécutable, 644/755 --------------------
if [ -d "$WEB" ]; then
  if find "$WEB" -type f -perm -111 2>/dev/null | grep -q .; then
    ko "des fichiers exécutables parasites subsistent sous $WEB"
  else
    ok "aucun fichier exécutable parasite sous $WEB"
  fi
  if [ "$(stat -c '%U' "$WEB")" = "www-data" ]; then
    ok "$WEB appartient à www-data"
  else
    ko "$WEB n'appartient pas à www-data"
  fi
fi

# --- 3. conf en 640 root:facturation ------------------------------------
if [ -e "$CONF" ]; then
  if [ "$(stat -c '%a %U:%G' "$CONF")" = "640 root:facturation" ]; then
    ok "$CONF est en 640 root:facturation"
  else
    ko "$CONF n'est pas en 640 root:facturation ($(stat -c '%a %U:%G' "$CONF"))"
  fi
fi

# --- 4. secrets : 700 dir, 600 fichiers ---------------------------------
if [ -d "$SECRETS" ]; then
  [ "$(stat -c '%a' "$SECRETS")" = "700" ] && \
    ok "$SECRETS est en 700" || \
    ko "$SECRETS n'est pas en 700 ($(stat -c '%a' "$SECRETS"))"
  bad=$(find "$SECRETS" -type f ! -perm 600 2>/dev/null | wc -l)
  [ "$bad" -eq 0 ] && ok "tous les secrets sont en 600" || \
    ko "$bad secret(s) ne sont pas en 600"
fi

# --- 5. exports : 2770 groupe facturation -------------------------------
if [ -d "$EXPORTS" ]; then
  m=$(stat -c '%a' "$EXPORTS"); g=$(stat -c '%G' "$EXPORTS")
  { [ "$m" = "2770" ] && [ "$g" = "facturation" ]; } && \
    ok "$EXPORTS est en 2770 groupe facturation" || \
    ko "$EXPORTS attendu 2770 facturation (obtenu $m $g)"
  if command -v getfacl >/dev/null 2>&1; then
    getfacl -p "$EXPORTS" 2>/dev/null | grep -q '^default:group:facturation:rw' \
      && ok "ACL par défaut g:facturation:rw présente sur exports" \
      || ko "ACL par défaut g:facturation:rw manquante sur exports"
  else
    note "getfacl absent : contrôle de l'ACL par défaut ignoré"
  fi
fi

# --- 6. API : capability posée, pas de SUID -----------------------------
if [ -x "$API" ]; then
  printf '%s' "$(stat -c '%A' "$API")" | grep -q '^...s' && \
    ko "$API est encore SUID (doit utiliser une capability)" || \
    ok "$API n'est pas SUID"
  if command -v getcap >/dev/null 2>&1; then
    getcap "$API" 2>/dev/null | grep -q 'cap_net_bind_service' && \
      ok "cap_net_bind_service posée sur $API" || \
      note "cap_net_bind_service absente sur $API (attendu si l'API bind < 1024)"
  fi
fi

# --- 7. rapport ---------------------------------------------------------
RAP="$HOMEDIR/lab03/rapports/durcissement-factura.md"
[ -s "$RAP" ] && ok "le rapport durcissement-factura.md est présent" || \
  ko "rapport ~/lab03/rapports/durcissement-factura.md absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
