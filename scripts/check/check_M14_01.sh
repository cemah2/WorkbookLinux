#!/usr/bin/env bash
# check_M14_01.sh — vérifie le lab L14.1 (accès par clé sur tout le parc)
# À lancer sur lab-adm, SANS sudo, avec l'utilisateur du lab.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L14.1 =="

HOTES="10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14"
KEY="$HOME/.ssh/id_ed25519"
SSHOPT="-o BatchMode=yes -o ConnectTimeout=5 -o PasswordAuthentication=no"

command -v ssh-keygen >/dev/null 2>&1 || { \
  ko "ssh-keygen introuvable : installe openssh-client"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. la nouvelle clé ---------------------------------------------------
if [ -f "$KEY" ] && [ -f "$KEY.pub" ]; then
  ok "paire ~/.ssh/id_ed25519 présente"
  LIGNE=$(ssh-keygen -lf "$KEY.pub" 2>/dev/null)
  case "$LIGNE" in
    *"(ED25519)") ok "la clé est bien de type ED25519" ;;
    *) ko "type inattendu : $LIGNE (ed25519 attendu)" ;;
  esac
  COMMENT=$(printf '%s\n' "$LIGNE" | awk '{$1="";$2="";$NF="";print}' \
            | tr -s ' ' | sed 's/^ //;s/ $//')
  [ -n "$COMMENT" ] \
    && ok "commentaire présent : $COMMENT" \
    || ko "clé sans commentaire (ssh-keygen -c -C ... pour en poser un)"
  if ssh-keygen -y -P '' -f "$KEY" >/dev/null 2>&1; then
    ko "la clé privée n'a PAS de passphrase (ssh-keygen -p -f $KEY)"
  else
    ok "la clé privée est protégée par une passphrase"
  fi
else
  ko "clé absente : ~/.ssh/id_ed25519(.pub)"
fi

# --- 2. permissions -------------------------------------------------------
[ "$(stat -c %a "$HOME/.ssh" 2>/dev/null)" = 700 ] \
  && ok "~/.ssh en 700" \
  || ko "~/.ssh doit être en 700 (lu : $(stat -c %a "$HOME/.ssh" 2>/dev/null))"
if [ -f "$KEY" ]; then
  [ "$(stat -c %a "$KEY")" = 600 ] \
    && ok "clé privée en 600" \
    || ko "clé privée en $(stat -c %a "$KEY") : ssh l'ignorera (600 attendu)"
fi
[ "$(( 0$(stat -c %a "$HOME") & 022 ))" -eq 0 ] \
  && ok "le home n'est pas accessible en écriture au groupe ni aux autres" \
  || ko "home en $(stat -c %a "$HOME") : StrictModes refusera (chmod go-w ~)"

# --- 3. agent -------------------------------------------------------------
if ssh-add -l >/dev/null 2>&1; then
  ok "un agent est joignable"
  if [ -f "$KEY.pub" ]; then
    FP=$(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')
    ssh-add -l | awk '{print $2}' | grep -qxF "$FP" \
      && ok "la clé ed25519 est chargée dans l'agent" \
      || ko "la clé n'est pas dans l'agent (ssh-add -t 28800 $KEY)"
  fi
else
  ko "aucun agent joignable (eval \"\$(ssh-agent -s)\" puis ssh-add)"
fi

# --- 4. connexion par clé sur les quatre serveurs -------------------------
for h in $HOTES; do
  # shellcheck disable=SC2086
  if ssh $SSHOPT "$h" true 2>/dev/null; then
    ok "connexion par clé vers $h"
  else
    ko "échec de connexion par clé vers $h (ssh -v $h, puis le journal)"
  fi
done

# --- 5. la vieille clé RSA ne doit plus rien ouvrir ------------------------
if [ -f "$HOME/.ssh/id_rsa" ]; then
  ko "~/.ssh/id_rsa existe encore sur le poste : la rotation est incomplète"
  RSAFP=$(ssh-keygen -lf "$HOME/.ssh/id_rsa.pub" 2>/dev/null | awk '{print $2}')
else
  ok "la vieille clé RSA a été retirée du poste"
  RSAFP=""
fi
for h in $HOTES; do
  # shellcheck disable=SC2086
  SORTIE=$(ssh $SSHOPT "$h" \
    'ssh-keygen -lf ~/.ssh/authorized_keys 2>/dev/null' 2>/dev/null) || {
      note "$h injoignable : vérification des authorized_keys sautée"
      continue; }
  if printf '%s\n' "$SORTIE" | grep -q '(RSA)'; then
    ko "$h : une clé RSA figure encore dans ~/.ssh/authorized_keys"
  else
    ok "$h : plus aucune clé RSA autorisée"
  fi
done

# --- 6. lab-web n'accepte plus le mot de passe ----------------------------
SORTIE=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
  -o PubkeyAuthentication=no -o PreferredAuthentications=password \
  10.10.10.11 true 2>&1)
case "$SORTIE" in
  *"Permission denied (publickey)"*)
      ok "lab-web refuse l'authentification par mot de passe" ;;
  *"Permission denied"*)
      ko "lab-web refuse, mais propose encore d'autres méthodes : $SORTIE" ;;
  "")  ko "lab-web accepte encore une méthode sans clé" ;;
  *)   ko "réponse inattendue de lab-web : $SORTIE" ;;
esac

# --- 7. rapports ----------------------------------------------------------
for f in cles-avant.md cles-apres.md; do
  [ -s "$HOME/lab14/rapports/$f" ] \
    && ok "rapport présent : ~/lab14/rapports/$f" \
    || ko "rapport manquant ou vide : ~/lab14/rapports/$f"
done

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
