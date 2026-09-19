#!/usr/bin/env bash
# check_M14_06.sh — vérifie le défi D14 (lab-adm en bastion)
# À lancer sur lab-adm, SANS sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D14 =="

BASE="$HOME/lab14"
REF="$BASE/conf/ssh_config.reference"
BAS="$BASE/conf/60-bastion.conf"
KH="$BASE/bin/known-hosts-parc.sh"
PARC="$BASE/bin/parc.sh"
RAP="$BASE/rapports/bastion.md"

# --- 1. configuration client de référence ---------------------------------
if [ -s "$REF" ]; then
  ok "fichier de référence présent : ~/lab14/conf/ssh_config.reference"
  MANQUE=""
  for mot in ProxyJump ControlMaster ControlPersist ServerAliveInterval \
             IdentitiesOnly Include Match; do
    grep -qi "^[[:space:]]*$mot" "$REF" || MANQUE="$MANQUE $mot"
  done
  [ -z "$MANQUE" ] \
    && ok "toutes les directives imposées sont présentes" \
    || ko "directives manquantes dans le fichier de référence :$MANQUE"
  for ip in 10.10.10.10 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14; do
    grep -q "$ip" "$REF" || ko "la machine $ip n'apparaît pas"
  done
  grep -q '10.10.10.14' "$REF" && ok "les cinq machines sont décrites"
  # Host * doit être le dernier bloc
  DERNIER=$(grep -niE '^[[:space:]]*(Host|Match)[[:space:]]' "$REF" \
            | tail -1 | cut -d: -f2-)
  case "$DERNIER" in
    *'Host *'*) ok "le bloc Host * est bien le dernier" ;;
    *) ko "le dernier bloc est '$DERNIER' : Host * doit fermer le fichier" ;;
  esac
  grep -cE '^[[:space:]]*#' "$REF" >/dev/null && \
    [ "$(grep -cE '^[[:space:]]*#' "$REF")" -ge 4 ] \
    && ok "les blocs sont commentés" \
    || ko "chaque bloc doit porter un commentaire d'une ligne"
else
  ko "fichier manquant : ~/lab14/conf/ssh_config.reference"
fi

# --- 2. durcissement du bastion, réellement appliqué ----------------------
if [ -s "$BAS" ]; then
  ok "fragment présent : ~/lab14/conf/60-bastion.conf"
else
  ko "fragment manquant : ~/lab14/conf/60-bastion.conf"
fi
EFF=""
sudo -n true 2>/dev/null && EFF=$(sudo -n sshd -T 2>/dev/null)
if [ -n "$EFF" ]; then
  val() { printf '%s\n' "$EFF" | awk -v k="$1" 'tolower($1)==k {sub($1" ","");
          print; exit}'; }
  [ "$(val permitrootlogin)" = no ] \
    && ok "bastion : permitrootlogin no" || ko "bastion : root encore autorisé"
  [ "$(val passwordauthentication)" = no ] \
    && ok "bastion : passwordauthentication no" \
    || ko "bastion : le mot de passe est encore accepté"
  [ "$(val allowtcpforwarding)" = yes ] \
    && ok "bastion : allowtcpforwarding yes (c'est son métier)" \
    || ko "bastion : allowtcpforwarding doit rester yes pour ProxyJump/-L"
  [ "$(val allowagentforwarding)" = no ] \
    && ok "bastion : allowagentforwarding no" \
    || ko "bastion : le transfert d'agent doit être interdit"
  [ "$(val loglevel)" = VERBOSE ] \
    && ok "bastion : loglevel VERBOSE" \
    || ko "bastion : loglevel VERBOSE attendu"
  case "$(val allowgroups)" in
    *ssh-users*) ok "bastion : allowgroups ssh-users" ;;
    *) ko "bastion : l'accès n'est pas réservé au groupe ssh-users" ;;
  esac
else
  note "sshd -T illisible sans mot de passe : vérifie toi-même avec"
  note "  sudo sshd -T | grep -Ei 'allowgroups|agentforward|tcpforward'"
fi

# --- 3. provisionnement des empreintes ------------------------------------
if [ -x "$KH" ]; then
  ok "$KH présent et exécutable"
  head -1 "$KH" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang conforme" || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$KH" \
    && ok "set -euo pipefail présent" || ko "set -euo pipefail manquant"
  grep -q 'ssh-keyscan' "$KH" \
    && ok "le script utilise ssh-keyscan" || ko "ssh-keyscan attendu"
  [ -s "$BASE/conf/empreintes.txt" ] \
    && ok "liste de référence présente : ~/lab14/conf/empreintes.txt" \
    || ko "liste de référence manquante : ~/lab14/conf/empreintes.txt"
  # comportement attendu : refus d'écrire si une empreinte diverge
  TMPREF=$(mktemp); TMPOUT=$(mktemp)
  printf '10.10.10.11 SHA256:CeciNestPasUneEmpreinte\n' > "$TMPREF"
  REF="$TMPREF" OUT="$TMPOUT" HOTES="10.10.10.11" bash "$KH" >/dev/null 2>&1
  RC=$?
  [ "$RC" -eq 2 ] \
    && ok "le script sort en 2 quand une empreinte diverge" \
    || ko "code de retour $RC sur divergence : 2 attendu"
  [ ! -s "$TMPOUT" ] \
    && ok "aucun known_hosts écrit en cas de divergence" \
    || ko "le script a écrit malgré la divergence : c'est le défaut à éviter"
  rm -f "$TMPREF" "$TMPOUT"
else
  ko "script absent ou non exécutable : ~/lab14/bin/known-hosts-parc.sh"
fi

# --- 4. outil de parc ------------------------------------------------------
if [ -x "$PARC" ]; then
  ok "$PARC présent et exécutable"
  head -1 "$PARC" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang conforme" || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$PARC" \
    && ok "set -euo pipefail présent" || ko "set -euo pipefail manquant"
  grep -qE '10\.10\.10\.[0-9]+' "$PARC" \
    && ko "des adresses IP sont codées en dur : utilise les alias" \
    || ok "aucune IP en dur : les alias de configuration sont utilisés"
  grep -q 'BatchMode' "$PARC" \
    && ok "BatchMode utilisé (aucune interaction possible)" \
    || ko "BatchMode=yes manquant : le script peut bloquer sur une invite"
  grep -q 'ConnectTimeout' "$PARC" \
    && ok "ConnectTimeout utilisé" || ko "ConnectTimeout manquant"
  SORTIE=$(bash "$PARC" 'echo lab14-ping' 2>&1); RC=$?
  if [ "$RC" -eq 0 ]; then
    ok "parc.sh sort en 0 quand tout va bien"
  else
    ko "parc.sh sort en $RC sur une commande triviale : $(echo "$SORTIE" \
        | tail -1)"
  fi
  printf '%s\n' "$SORTIE" | grep -q 'lab14-ping' \
    && ok "la sortie de chaque machine est restituée" \
    || ko "la sortie distante n'apparaît pas dans le tableau"
  for h in lab-web lab-db lab-rhel lab-ops; do
    printf '%s\n' "$SORTIE" | grep -q "$h" || ko "$h absent du tableau"
  done
  bash "$PARC" 'exit 7' >/dev/null 2>&1; RC=$?
  [ "$RC" -eq 1 ] \
    && ok "code global 1 quand une commande échoue" \
    || ko "code global $RC attendu à 1 quand la commande distante échoue"
  TMPS=$(mktemp); printf '#!/usr/bin/env bash\necho lab14-script\n' > "$TMPS"
  bash "$PARC" -s "$TMPS" >/dev/null 2>&1 \
    && ok "l'option -s exécute un script local à distance" \
    || ko "l'option -s ne fonctionne pas (ssh h 'bash -s' < script)"
  rm -f "$TMPS"
  bash "$PARC" -p 4 'true' >/dev/null 2>&1 \
    && ok "l'option -p accepte un niveau de parallélisme" \
    || ko "l'option -p échoue"
else
  ko "script absent ou non exécutable : ~/lab14/bin/parc.sh"
fi

# --- 5. le rapport ---------------------------------------------------------
if [ -s "$RAP" ]; then
  ok "rapport présent : ~/lab14/rapports/bastion.md"
  L=$(grep -c . "$RAP")
  [ "$L" -ge 30 ] \
    && ok "rapport rédigé ($L lignes)" \
    || ko "rapport trop court ($L lignes, 30 minimum)"
  MANQUE=""
  for mot in ProxyJump ssh-users révocation certificat 'IDENTIFICATION HAS'; do
    grep -qi -- "$mot" "$RAP" || MANQUE="$MANQUE ${mot}"
  done
  [ -z "$MANQUE" ] \
    && ok "le rapport couvre les cinq rubriques imposées" \
    || ko "il manque dans le rapport :$MANQUE"
else
  ko "rapport manquant : ~/lab14/rapports/bastion.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
