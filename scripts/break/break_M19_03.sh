#!/usr/bin/env bash
# break_M19_03.sh — panne BF19.3 : « le vault ne s'ouvre plus »
# Rechiffre inventory/group_vars/all/vault.yml avec un autre mot de passe et
# retire vault_password_file d'ansible.cfg. Laisse un mail dans ~/lab19/casse.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab19"
VAULT="$BASE/inventory/group_vars/all/vault.yml"
CFG="$BASE/ansible.cfg"
VP="$BASE/.vault_pass"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$BASE/casse"
[ -f "$VAULT" ] && [ -f "$VP" ] && [ -f "$CFG" ] \
  || { echo "projet ~/lab19 incomplet : lance setup_M19.sh" >&2; exit 1; }

as_user() { sudo -u "$LAB_USER" -H env PATH="$LAB_HOME/.local/bin:$PATH" "$@"; }
JULIEN_PASS='Julien-Temp-2026!'
TMPJ=$(mktemp); printf '%s\n' "$JULIEN_PASS" > "$TMPJ"; chmod 644 "$TMPJ"
trap 'rm -f "$TMPJ"' EXIT

# état sain ? -> sauvegarde ; déjà cassé ? -> on repart de la sauvegarde
if as_user ansible-vault view --vault-password-file "$VP" "$VAULT" \
     >/dev/null 2>&1; then
  cp -a "$VAULT" "$SAUV/M19_03_vault.yml"
  cp -a "$CFG" "$SAUV/M19_03_ansible.cfg"
elif [ -f "$SAUV/M19_03_vault.yml" ]; then
  cp -a "$SAUV/M19_03_vault.yml" "$VAULT"
  cp -a "$SAUV/M19_03_ansible.cfg" "$CFG"
else
  echo "vault.yml ne se déchiffre pas et aucune sauvegarde : relance" \
       "setup_M19.sh" >&2; exit 1
fi

# 1. rechiffrage avec le mot de passe perso de Julien
as_user ansible-vault rekey --vault-password-file "$VP" \
  --new-vault-password-file "$TMPJ" "$VAULT" >/dev/null
# 2. « nettoyage » d'ansible.cfg : plus de fichier de mot de passe
sed -i 's/^vault_password_file/# vault_password_file/' "$CFG"

# 3. le mail
cat > "$BASE/casse/mail-julien.txt" <<'EOF'
De      : julien@lab.local
À       : ops@lab.local
Objet   : vault - pense-bête avant mes congés
Date    : vendredi, 17:52

Salut,

j'ai dû tester baseline.yml depuis mon portable perso où je n'ai pas le
.vault_pass de l'équipe (et je ne voulais pas le copier dessus). J'ai donc
rechiffré inventory/group_vars/all/vault.yml avec un mot de passe à moi le
temps du test, et j'ai enlevé la ligne vault_password_file d'ansible.cfg qui
me générait une erreur sur le portable.

Je remets tout en ordre lundi en rentrant. Si vous en avez besoin avant, mon
mot de passe temporaire est : Julien-Temp-2026!
(ne le notez nulle part, je le change à mon retour)

Bon week-end,
Julien
EOF
chown -R "$LAB_USER":"$LAB_USER" "$BASE/casse" "$VAULT" "$CFG"

cat <<'EOF'

Symptôme attendu : dans ~/lab19, n'importe quelle commande Ansible, même
ansible all -m ansible.builtin.ping, s'arrête avant de toucher un hôte :
  ERROR! Attempting to decrypt but no vault secrets found
Après un premier bricolage dans ansible.cfg, le message devient :
  ERROR! Decryption failed (no vault secrets were found that could decrypt)
Un mail de Julien traîne dans ~/lab19/casse/. Objectif : retrouver l'accès,
rechiffrer avec le mot de passe de l'équipe (~/lab19/.vault_pass), remettre
ansible.cfg en état.
EOF
