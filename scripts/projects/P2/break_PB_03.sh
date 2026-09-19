#!/usr/bin/env bash
# break_PB_03.sh — INC-B3 : le déploiement de prod échoue, vault illisible
# À lancer avec sudo sur lab-adm. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/INC-B3/ (vault.yml prod d'origine).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
REPO="${REPO:-$LAB_HOME/factura-v2}"
BK=/root/.breakfix-backup/INC-B3
VAULT=ansible/inventory/group_vars/prod/vault.yml
mkdir -p "$BK"
u() { sudo -u "$LAB_USER" -H env PATH="$LAB_HOME/.local/bin:$PATH" "$@"; }
cd "$REPO"

# déjà cassé ? (le .vault-pass ne déchiffre plus le fichier)
if ! u ansible-vault view --vault-password-file .vault-pass "$VAULT" \
     >/dev/null 2>&1; then
  echo "Symptôme : ansible-vault view $VAULT échoue ; cd-prod rouge."
  exit 0
fi

[ -f "$BK/vault.yml" ] || cp -a "$VAULT" "$BK/vault.yml"

# « rotation » faite par un collègue : nouvelle valeur, ET nouveau mot de
# passe de coffre connu de lui seul
TMP=$(mktemp -d); chown "$LAB_USER" "$TMP"
u ansible-vault view --vault-password-file .vault-pass "$VAULT" > "$TMP/clair.yml"
NEWPW="Prd-Db-$(date +%Y)-rot$(openssl rand -hex 3)"
sed -i "s/^vault_db_password:.*/vault_db_password: \"$NEWPW\"/" "$TMP/clair.yml"
openssl rand -base64 24 > "$TMP/newvaultpass"
chown "$LAB_USER" "$TMP"/*
u ansible-vault encrypt --vault-password-file "$TMP/newvaultpass" \
  "$TMP/clair.yml" >/dev/null 2>&1
cp "$TMP/clair.yml" "$VAULT"; chown "$LAB_USER" "$VAULT"
rm -rf "$TMP"

u git -c user.name="Collegue" -c user.email="collegue@lab.local" \
  commit -q -m "chore(vault): rotation" -- "$VAULT" >/dev/null 2>&1 || true

cat <<EOF
Symptôme : depuis le commit « chore(vault): rotation » de ce matin, la
promotion en prod échoue.
  ansible-vault view $VAULT   -> ERROR! Decryption failed
  Run cd-prod rouge à l'étape Ansible. Le staging se déploie normalement.
  La prod tourne encore ; un correctif urgent doit partir avant 18 h.
EOF
