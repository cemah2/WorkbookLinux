#!/usr/bin/env bash
# check_M04_04.sh — vérifie le lab L4.4 (durcissement de l'authentification)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L4.4 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"

# fichiers PAM : Debian/Ubuntu ou RHEL/Rocky
if [ -f /etc/pam.d/common-password ]; then
  PAM_PW=/etc/pam.d/common-password
  PAM_AUTH=/etc/pam.d/common-auth
  PAM_ACC=/etc/pam.d/common-account
else
  PAM_PW=/etc/pam.d/system-auth
  PAM_AUTH=/etc/pam.d/system-auth
  PAM_ACC=/etc/pam.d/system-auth
fi

# --- 1. qualité des mots de passe --------------------------------------
if grep -qE '^\s*password.*pam_pwquality\.so' "$PAM_PW"; then
  ok "pam_pwquality est dans la pile password de $PAM_PW"
  if grep -nE '^\s*password.*pam_(pwquality|unix)\.so' "$PAM_PW" \
     | sed -n '1p' | grep -q pwquality; then
    ok "  il est placé AVANT pam_unix (sinon il ne juge rien)"
  else
    ko "  pam_pwquality est placé après pam_unix : il n'est jamais consulté"
  fi
else
  ko "pam_pwquality absent de $PAM_PW (apt install libpam-pwquality)"
fi

PWQ=/etc/security/pwquality.conf
if [ -f "$PWQ" ]; then
  ml=$(grep -E '^\s*minlen' "$PWQ" | tail -1 | tr -dc '0-9')
  mc=$(grep -E '^\s*minclass' "$PWQ" | tail -1 | tr -dc '0-9')
  [ "${ml:-0}" -ge 12 ] 2>/dev/null && ok "minlen = $ml (>= 12)" \
      || ko "minlen absent ou < 12 dans $PWQ"
  [ "${mc:-0}" -ge 3 ] 2>/dev/null && ok "minclass = $mc (>= 3)" \
      || ko "minclass absent ou < 3 dans $PWQ"
  grep -qE '^\s*usercheck\s*=\s*[1-9]' "$PWQ" \
      && ok "usercheck actif (refus du login dans le mot de passe)" \
      || ko "usercheck non activé dans $PWQ"
else
  ko "$PWQ absent"
fi

if grep -qE '^\s*password.*pam_pwhistory\.so.*remember=[3-9]' "$PAM_PW"; then
  ok "pam_pwhistory mémorise au moins 3 anciens mots de passe"
else
  ko "historique des mots de passe absent (pam_pwhistory remember=3)"
fi

# --- 2. verrouillage après échecs --------------------------------------
if grep -qE '^\s*auth.*pam_faillock\.so' "$PAM_AUTH"; then
  ok "pam_faillock est dans la pile auth"
  grep -qE 'pam_faillock\.so.*preauth' "$PAM_AUTH" \
      && ok "  ligne preauth présente" || ko "  ligne 'preauth' manquante"
  grep -qE 'pam_faillock\.so.*authfail' "$PAM_AUTH" \
      && ok "  ligne authfail présente" || ko "  ligne 'authfail' manquante"
  d=$(grep -oE 'deny=[0-9]+' "$PAM_AUTH" | head -1 | tr -dc '0-9')
  [ "${d:-0}" -ge 1 ] && [ "${d:-99}" -le 5 ] 2>/dev/null \
      && ok "  deny=$d (<= 5)" || ko "  deny absent ou > 5"
  u=$(grep -oE 'unlock_time=[0-9]+' "$PAM_AUTH" | head -1 | tr -dc '0-9')
  [ "${u:-0}" -ge 900 ] 2>/dev/null && ok "  unlock_time=$u (>= 900 s)" \
      || ko "  unlock_time absent ou < 900 s (15 minutes demandées)"
  grep -qE 'pam_faillock\.so.*even_deny_root' "$PAM_AUTH" \
      && ko "  even_deny_root : root peut être verrouillé, l'énoncé l'interdit" \
      || ok "  root n'est pas verrouillable (pas d'even_deny_root)"
else
  ko "pam_faillock absent de $PAM_AUTH"
fi
grep -qE '^\s*account.*pam_faillock\.so' "$PAM_ACC" \
    && ok "pam_faillock est aussi dans la pile account" \
    || ko "ligne 'account required pam_faillock.so' manquante dans $PAM_ACC"

if command -v faillock >/dev/null 2>&1; then
  ok "la commande faillock est disponible pour débloquer un compte"
else
  ko "commande faillock introuvable"
fi

# --- 3. expiration des comptes humains ---------------------------------
UMIN=$(awk '$1=="UID_MIN"{print $2}' /etc/login.defs); : "${UMIN:=1000}"
MANQUE=""
while IFS=: read -r u _ uid _ _ _ sh; do
  [ "$uid" -ge "$UMIN" ] && [ "$uid" -ne 65534 ] || continue
  case "$sh" in */nologin|*/false) continue ;; esac
  max=$(getent shadow "$u" | cut -d: -f5)
  warn=$(getent shadow "$u" | cut -d: -f6)
  inact=$(getent shadow "$u" | cut -d: -f7)
  if [ "${max:-99999}" != "90" ] || [ "${warn:-0}" != "14" ] \
     || [ "${inact:-}" != "7" ]; then
    MANQUE="$MANQUE $u"
  fi
done < <(getent passwd)
if [ -z "$MANQUE" ]; then
  ok "tous les comptes humains sont en 90 / 14 / 7"
else
  ko "politique 90/14/7 non appliquée à :$MANQUE (chage -M 90 -W 14 -I 7)"
fi

# --- 4. limites de ressources ------------------------------------------
LIM=$(grep -rhE '^\s*@factura' /etc/security/limits.conf \
      /etc/security/limits.d/ 2>/dev/null)
if [ -n "$LIM" ]; then
  ok "des limites sont déclarées pour @factura"
  printf '%s' "$LIM" | grep -qE 'soft\s+nofile\s+4096' \
      && ok "  soft nofile 4096" || ko "  'soft nofile 4096' manquant"
  printf '%s' "$LIM" | grep -qE 'hard\s+nofile\s+8192' \
      && ok "  hard nofile 8192" || ko "  'hard nofile 8192' manquant"
  printf '%s' "$LIM" | grep -qE 'nproc\s+200' \
      && ok "  nproc 200" || ko "  'nproc 200' manquant"
else
  ko "aucune ligne @factura dans limits.conf ni limits.d/"
fi

if getent passwd sophie >/dev/null; then
  N=$(su - sophie -c 'ulimit -Sn' 2>/dev/null | tr -dc '0-9')
  if [ "${N:-0}" = "4096" ]; then
    ok "dans une session de sophie, ulimit -Sn vaut 4096"
  else
    ko "ulimit -Sn = '${N:-?}' pour sophie, attendu 4096 (pam_limits est-il \
appelé par ce service ? voir /etc/pam.d/su et /etc/pam.d/login)"
  fi
fi

# --- 5. rapport ---------------------------------------------------------
RAP="$LAB_HOME/lab04/rapports/politique-auth.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 12 ]; then
  ok "le rapport politique-auth.md est rédigé"
else
  ko "rapport $RAP absent ou trop court (12 lignes minimum, 4 points couverts)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
