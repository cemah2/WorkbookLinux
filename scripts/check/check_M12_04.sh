#!/usr/bin/env bash
# check_M12_04.sh — vérifie le lab L12.4 (sockets, états TCP, sysctl)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L12.4 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab12/rapports/sockets.md"

# --- 1. le rapport d'inventaire ---------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c '|' "$RAP")" -ge 4 ]; then
  ok "rapport sockets.md présent et tabulé"
else
  ko "rapport absent ou sans tableau : $RAP (4 colonnes attendues)"
fi

# le rapport doit refléter la réalité : au moins un port réellement
# en écoute doit y figurer
REEL=$(ss -H -tln 2>/dev/null | awk '{print $4}' | sed 's/.*://' |
       sort -un | head -5)
trouve=0
for p in $REEL; do
  grep -q ":$p\b" "$RAP" 2>/dev/null && trouve=$((trouve+1))
done
if [ "$trouve" -ge 1 ]; then
  ok "le rapport cite des ports réellement en écoute ($trouve)"
else
  ko "aucun port en écoute de la machine ne figure au rapport"
fi

grep -qiE 'expos|127\.0\.0\.1|0\.0\.0\.0' "$RAP" 2>/dev/null \
  && ok "l'exposition des sockets est renseignée" \
  || ko "le rapport ne distingue pas les sockets exposés des sockets locaux"

# --- 2. l'API doit être joignable via le reverse proxy ----------------
if command -v curl >/dev/null 2>&1; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
         http://127.0.0.1/api/health 2>/dev/null)
  if [ "$CODE" = 200 ]; then
    ok "http://<lab-web>/api/ répond 200 via le reverse proxy"
  else
    ko "/api/ ne répond pas (code $CODE) : vérifie proxy_pass et nginx -t"
  fi
fi

# --- 3. le service applicatif tourne toujours -------------------------
if ss -tln 2>/dev/null | grep -q ':8099'; then
  ok "factura-api écoute toujours sur 8099"
else
  ko "rien n'écoute sur 8099 : le service a été cassé ou arrêté"
fi

# --- 4. somaxconn persistant ------------------------------------------
VAL=$(sysctl -n net.core.somaxconn 2>/dev/null)
if [ -n "$VAL" ] && [ "$VAL" -ge 8192 ] 2>/dev/null; then
  ok "net.core.somaxconn = $VAL en mémoire"
else
  ko "net.core.somaxconn = ${VAL:-?} : la valeur demandée (>= 8192) n'est \
pas appliquée"
fi

if grep -rqs 'somaxconn' /etc/sysctl.d/ /etc/sysctl.conf 2>/dev/null; then
  ok "somaxconn déclaré de façon persistante (/etc/sysctl.d/)"
else
  ko "aucun fichier de /etc/sysctl.d/ ne fixe somaxconn : ce sera perdu \
au redémarrage"
fi

# --- 5. le rapport mentionne les états TCP observés -------------------
if grep -qiE 'time.?wait' "$RAP" 2>/dev/null ||
   grep -qiE 'close.?wait' "$RAP" 2>/dev/null; then
  ok "les états TCP observés sont commentés"
else
  note "le rapport ne mentionne ni TIME-WAIT ni CLOSE-WAIT (étapes 5 et 6)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
