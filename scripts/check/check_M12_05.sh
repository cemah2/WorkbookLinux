#!/usr/bin/env bash
# check_M12_05.sh — vérifie le lab L12.5 (clé de service restreinte)
# À lancer SUR lab-web, avec sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L12.5 =="

[ "$(id -u)" -eq 0 ] || { \
  ko "à lancer avec sudo (lecture de /home/sauvegarde/.ssh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

AK=/home/sauvegarde/.ssh/authorized_keys
SC=/usr/local/bin/lab12-recevoir

# --- 1. le compte et ses droits -------------------------------------------
getent passwd sauvegarde >/dev/null \
  && ok "le compte sauvegarde existe" \
  || ko "compte sauvegarde absent : relance setup_M12.sh sur lab-web"
[ -d /srv/sauvegarde ] \
  && ok "/srv/sauvegarde présent" \
  || ko "/srv/sauvegarde absent"
[ "$(stat -c %a /home/sauvegarde/.ssh 2>/dev/null)" = 700 ] \
  && ok "/home/sauvegarde/.ssh en 700" \
  || ko "/home/sauvegarde/.ssh doit être en 700"

# --- 2. la ligne authorized_keys ------------------------------------------
if [ -s "$AK" ]; then
  ok "authorized_keys présent"
  [ "$(stat -c %a "$AK")" = 600 ] \
    && ok "authorized_keys en 600" \
    || ko "authorized_keys en $(stat -c %a "$AK") : 600 attendu"
  LIGNES=$(grep -c '^[^#[:space:]]' "$AK")
  [ "$LIGNES" -eq 1 ] \
    && ok "une seule clé autorisée" \
    || ko "$LIGNES clés autorisées : une seule attendue pour ce compte"
  OPTS=$(head -1 "$AK")
  case "$OPTS" in
    *restrict*) ok "option restrict présente" ;;
    *) ko "option restrict absente (préférable à une liste de no-*)" ;;
  esac
  case "$OPTS" in
    *'from="10.10.10.14"'*) ok 'option from="10.10.10.14" présente' ;;
    *from=*) ko "from= présent mais pas limité à 10.10.10.14 : $OPTS" ;;
    *) ko "option from= absente : la clé est utilisable depuis partout" ;;
  esac
  case "$OPTS" in
    *command=*) ok "commande forcée présente" ;;
    *) ko "option command= absente : la clé ouvre un shell complet" ;;
  esac
  case "$OPTS" in
    ssh-ed25519*|ssh-rsa*) ko "les options doivent précéder la clé" ;;
    *) : ;;
  esac
  ssh-keygen -lf "$AK" >/dev/null 2>&1 \
    && ok "la ligne est une clé publique valide (une seule ligne)" \
    || ko "ligne illisible par ssh-keygen : clé coupée en deux ?"
else
  ko "authorized_keys absent ou vide : $AK"
fi

# --- 3. le script de commande forcée --------------------------------------
if [ -x "$SC" ]; then
  ok "$SC présent et exécutable"
  head -1 "$SC" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang conforme" || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'SSH_ORIGINAL_COMMAND' "$SC" \
    && ok "le script lit SSH_ORIGINAL_COMMAND" \
    || ko "le script doit lire \$SSH_ORIGINAL_COMMAND"
  if grep -qE '^[^#]*eval[[:space:]]+"?\$\{?SSH_ORIGINAL_COMMAND' "$SC"; then
    ko "le script fait eval de la commande demandée : la restriction est vide"
  else
    ok "aucun eval de la commande demandée"
  fi
  # comportement réel : liste acceptée, reste refusé
  if SSH_ORIGINAL_COMMAND=liste bash "$SC" >/dev/null 2>&1; then
    ok "'liste' est acceptée"
  else
    ko "'liste' devrait fonctionner (SSH_ORIGINAL_COMMAND=liste)"
  fi
  SSH_ORIGINAL_COMMAND='rm -rf /srv/sauvegarde' bash "$SC" >/dev/null 2>&1
  RC=$?
  [ "$RC" -ne 0 ] \
    && ok "une commande arbitraire est refusée (code $RC)" \
    || ko "une commande arbitraire a été acceptée : la liste blanche manque"
  [ -d /srv/sauvegarde ] \
    && ok "/srv/sauvegarde a survécu au test de refus" \
    || ko "/srv/sauvegarde a été supprimé : le script exécute ce qu'on demande"
  SSH_ORIGINAL_COMMAND='depot ../../etc/passwd' bash "$SC" \
    </dev/null >/dev/null 2>&1
  [ $? -ne 0 ] \
    && ok "un nom d'archive avec traversée de répertoire est refusé" \
    || ko "le nom d'archive n'est pas validé (traversée ../ acceptée)"
else
  ko "script absent ou non exécutable : $SC"
fi

# --- 4. journalisation ----------------------------------------------------
LOG=/var/log/lab12-recevoir.log
if [ -f "$LOG" ]; then
  ok "journal présent : $LOG"
  grep -qiE 'refus|refuse' "$LOG" \
    && ok "les refus sont journalisés" \
    || ko "aucun refus journalisé : le script doit tracer les tentatives"
else
  ko "journal absent : $LOG"
fi

# --- 5. le rapport --------------------------------------------------------
LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab12/rapports/cle-service.md"
if [ -s "$RAP" ]; then
  ok "rapport présent : ~/lab12/rapports/cle-service.md"
  MANQUE=""
  for mot in restrict from= command= rotation certificat; do
    grep -qi -- "$mot" "$RAP" || MANQUE="$MANQUE $mot"
  done
  [ -z "$MANQUE" ] \
    && ok "le rapport couvre les cinq points imposés" \
    || ko "il manque dans le rapport :$MANQUE"
else
  ko "rapport manquant : ~/lab12/rapports/cle-service.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
