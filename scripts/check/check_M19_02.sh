#!/usr/bin/env bash
# check_M19_02.sh — vérifie le lab L19.2 (frontal nginx : vhost templaté, TLS)
# À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute la 2e exécution.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification L19.2 =="

export PATH="$HOME/.local/bin:$PATH"
BASE="$HOME/lab19"
cd "$BASE" 2>/dev/null || { ko "$BASE absent (setup_M19.sh)"; exit 1; }
command -v ansible >/dev/null || { ko "ansible introuvable dans le PATH"; exit 1; }
PB=playbooks/nginx.yml
[ -f "$PB" ] && ok "$PB présent" || { ko "$PB absent"; exit 1; }

# --- 1. variables et template ---------------------------------------------
GV=inventory/group_vars
for v in vitrine_server_name vitrine_root vitrine_tls_dir vitrine_version; do
  grep -rqs "^$v:" "$GV/web.yml" "$GV/web/" 2>/dev/null \
    && ok "$v défini dans group_vars web" \
    || ko "$v absent de group_vars/web (énoncé, étape 1)"
done
for v in nginx_vhost_dir nginx_user; do
  grep -rqs "^$v:" "$GV/ubuntu.yml" "$GV/ubuntu/" 2>/dev/null && \
  grep -rqs "^$v:" "$GV/rhel.yml" "$GV/rhel/" 2>/dev/null \
    && ok "$v défini pour ubuntu ET rhel" \
    || ko "$v manque dans group_vars ubuntu ou rhel"
done
TPL=playbooks/templates/vitrine.conf.j2
if [ -f "$TPL" ]; then
  ok "$TPL présent"
  grep -q 'X-Vitrine-Version' "$TPL" && ok "template : add_header X-Vitrine-Version" \
    || ko "template : pas d'en-tête X-Vitrine-Version"
  grep -Eq 'return 301|listen 443' "$TPL" && ok "template : redirection 80 -> 443" \
    || ko "template : redirection 80 -> 443 ou listen 443 absent"
  grep -q 'vitrine_version' "$TPL" && ok "template : version issue d'une variable" \
    || ko "template : la version n'est pas templatée"
else ko "$TPL absent"; fi

# --- 2. le site répond en HTTPS depuis lab-adm ----------------------------
for h in lab-web:10.10.10.11 lab-rhel:10.10.10.13; do
  n=${h%%:*}; ip=${h##*:}
  body=$(curl -sk -m 5 -H 'Host: vitrine.lab.local' "https://$ip/" 2>/dev/null)
  printf '%s\n' "$body" | has -E "vitrine [0-9]+\.[0-9]+\.[0-9]+ sur $n" \
    && ok "$n : corps « vitrine X.Y.Z sur $n » en HTTPS" \
    || ko "$n : https://$ip/ ne renvoie pas « vitrine <version> sur $n »"
  hdr=$(curl -skI -m 5 "https://$ip/" 2>/dev/null)
  printf '%s\n' "$hdr" | has -i 'x-vitrine-version:' \
    && ok "$n : en-tête X-Vitrine-Version présent" \
    || ko "$n : en-tête X-Vitrine-Version absent (add_header, reload ?)"
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' \
           -H 'Host: vitrine.lab.local' "http://$ip/" 2>/dev/null)
  [ "$code" = 301 ] || [ "$code" = 308 ] \
    && ok "$n : HTTP 80 redirige ($code)" \
    || ko "$n : http://$ip/ répond $code au lieu d'une redirection 301"
done

# --- 3. TLS généré sur la cible, clé protégée ------------------------------
r=$(ansible web -b -m ansible.builtin.shell -o \
      -a 'stat -c "%a %U" /etc/nginx/tls/vitrine.key; \
          openssl x509 -in /etc/nginx/tls/vitrine.crt -noout -ext subjectAltName' \
      2>/dev/null)
[ "$(printf '%s\n' "$r" | grep -c '600 root')" -eq 2 ] \
  && ok "clé privée en 0600 root sur les 2 hôtes" \
  || ko "clé /etc/nginx/tls/vitrine.key absente ou droits != 0600 root"
[ "$(printf '%s\n' "$r" | grep -c 'IP Address:10.10.10')" -eq 2 ] \
  && ok "certificat avec SAN IP de l'hôte" \
  || ko "certificat sans subjectAltName IP (openssl x509 -ext subjectAltName)"

# --- 4. idempotence et lint ------------------------------------------------
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : seconde exécution non testée"
else
  out=$(ansible-playbook "$PB" 2>&1)
  if [ "$(printf '%s\n' "$out" | grep -c 'changed=0 .*failed=0')" -eq 2 ]; then
    ok "seconde exécution : changed=0 failed=0 sur lab-web et lab-rhel"
  else ko "la seconde exécution n'est pas changed=0 partout (relis le recap)"; fi
fi
if command -v ansible-lint >/dev/null; then
  ansible-lint -q "$PB" >/dev/null 2>&1 && ok "ansible-lint muet sur $PB" \
    || ko "ansible-lint signale des problèmes sur $PB"
else note "ansible-lint absent, lint non testé"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
