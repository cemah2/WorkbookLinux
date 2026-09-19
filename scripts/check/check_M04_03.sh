#!/usr/bin/env bash
# check_M04_03.sh — vérifie le lab L4.3 (délégation sudo nginx)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L4.3 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

getent passwd karim >/dev/null || {
  ko "compte karim absent (relance setup_M04.sh)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. groupe deploy ---------------------------------------------------
if getent group deploy >/dev/null; then
  ok "le groupe deploy existe"
else
  ko "groupe deploy absent (groupadd deploy)"
fi
if id -nG karim | tr ' ' '\n' | grep -qx deploy; then
  ok "karim est membre de deploy"
else
  ko "karim n'est pas dans deploy (gpasswd -a karim deploy)"
fi
for g in sudo factura; do
  getent group "$g" >/dev/null || continue
  id -nG karim | tr ' ' '\n' | grep -qx "$g" \
    && ok "karim a conservé son groupe $g" \
    || ko "karim a perdu le groupe $g : usermod -aG, pas -G"
done

# --- 2. le fichier de règles -------------------------------------------
FIC=$(ls /etc/sudoers.d/ 2>/dev/null | grep -E '^[0-9]*-?deploy$' | head -1)
if [ -n "$FIC" ]; then
  F="/etc/sudoers.d/$FIC"
  ok "fichier de règles $F"
  mode=$(stat -c '%a' "$F"); own=$(stat -c '%U:%G' "$F")
  [ "$mode" = "440" ] && ok "  mode 0440" \
      || ko "  mode $mode, attendu 0440 (visudo -f le pose tout seul)"
  [ "$own" = "root:root" ] && ok "  propriétaire root:root" \
      || ko "  propriétaire $own, attendu root:root"
  case "$FIC" in
    *.*) ko "  le nom '$FIC' contient un point : sudo l'ignore silencieusement" ;;
    *)   ok "  nom de fichier accepté par sudo (ni point ni tilde)" ;;
  esac
else
  ko "aucun fichier /etc/sudoers.d/*deploy (visudo -f /etc/sudoers.d/60-deploy)"
fi

# --- 3. syntaxe globale -------------------------------------------------
if visudo -c >/dev/null 2>&1; then
  ok "visudo -c : tous les fichiers sudoers sont valides"
else
  ko "visudo -c signale une erreur : $(visudo -c 2>&1 | head -1)"
fi

# --- 4. ce que karim peut réellement faire ------------------------------
LISTE=$(sudo -l -U karim 2>/dev/null)
if [ -z "$LISTE" ]; then
  ko "sudo -l -U karim ne renvoie rien"
elif ! printf '%s' "$LISTE" | grep -q 'systemctl'; then
  ko "aucune règle systemctl pour karim ; si le champ hôte vaut lab-web, \
vérifie que hostname vaut bien lab-web sur cette machine"
else
  ok "sudo -l -U karim renvoie des règles systemctl"

  printf '%s' "$LISTE" | grep -qE 'NOPASSWD.*systemctl restart nginx' \
    && ok "  restart nginx autorisé sans mot de passe" \
    || ko "  'NOPASSWD: /usr/bin/systemctl restart nginx' manquant"

  printf '%s' "$LISTE" | grep -qE 'systemctl (reload|status) +nginx' \
    && ok "  reload/status nginx autorisés" \
    || ko "  reload ou status nginx manquants"

  printf '%s' "$LISTE" | grep -qE 'nginx -t' \
    && ok "  nginx -t autorisé" \
    || ko "  'nginx -t' manquant (chemin /usr/sbin/nginx)"

  printf '%s' "$LISTE" | grep -qE '(restart|reload) +(ssh|sshd)' \
    && ko "  karim peut agir sur ssh : la délégation est trop large" \
    || ok "  aucune action autorisée sur ssh"

  printf '%s' "$LISTE" | grep -qE '/[^ ,]*\*' \
    && ko "  un joker '*' figure dans un chemin de commande : trop permissif" \
    || ok "  aucun joker dans les chemins de commandes"

  printf '%s' "$LISTE" | grep -qE 'NOPASSWD: *ALL|\(ALL(:ALL)?\) *ALL' \
    && note "  karim dispose aussi d'un accès sudo complet (groupe sudo) : \
normal pour un ops, mais la règle deploy doit rester restrictive" \
    || true

fi

# --- 4 bis. pas d'échappement shell dans LA délégation deploy -----------
DANGER='vim|vi|nano|emacs|less|more|man|find|awk|sed|tar|python3|perl|bash|sh'
if [ -n "${F:-}" ]; then
  if grep -vE '^\s*(#|$)' "$F" | grep -qE "/($DANGER)( |,|$)"; then
    ko "un binaire à échappement shell est délégué dans $F (less, vim, find…) : \
il donne un shell root en une frappe"
  else
    ok "aucun binaire à échappement shell dans $F"
  fi
  grep -qE 'journalctl' "$F" && ! grep -qE 'journalctl[^,]*--no-pager' "$F" \
    && ko "journalctl est délégué sans --no-pager : son pager ouvre un shell" \
    || true
fi
if printf '%s' "$LISTE" | grep -vE '\(ALL(:ALL)?\) *ALL' \
     | grep -qE "/($DANGER)( |,|$)"; then
  note "karim dispose par ailleurs d'une règle déléguant un binaire à \
échappement shell (hors de ce lab : voir /etc/sudoers.d/, c'est l'objet de D4)"
fi

# --- 5. journalisation et ticket ---------------------------------------
CONF=$(cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null)
printf '%s' "$CONF" | grep -qE '^\s*Defaults.*logfile\s*=' \
  && ok "un journal sudo dédié est configuré (Defaults logfile=)" \
  || ko "aucun 'Defaults logfile=' : la traçabilité demandée manque"
printf '%s' "$CONF" | grep -qE '^\s*Defaults.*timestamp_timeout\s*=' \
  && ok "timestamp_timeout est fixé explicitement" \
  || ko "timestamp_timeout non fixé (ticket de 15 min par défaut)"
printf '%s' "$CONF" | grep -qE '^\s*Defaults.*use_pty' \
  && ok "use_pty actif" \
  || note "use_pty absent : il est actif par défaut sur Ubuntu 24.04"

LOG=$(printf '%s' "$CONF" | sed -n 's/.*logfile[[:space:]]*=[[:space:]]*//p' \
      | tr -d '"' | head -1)
if [ -n "$LOG" ] && [ -s "$LOG" ]; then
  ok "le journal $LOG contient des entrées"
elif [ -n "$LOG" ]; then
  ko "le journal $LOG est vide : lance une commande sudo pour le remplir"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
