#!/usr/bin/env bash
# check_M10_05.sh — vérifie le lab L10.5 (versant RHEL, sur lab-rhel)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L10.5 =="

command -v rpm >/dev/null 2>&1 || {
  ko "rpm absent : ce lab se fait sur lab-rhel (10.10.10.13)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab10/rapports/rhel.md"

# --- 1. le dépôt interne déclaré -----------------------------------------
REPO=$(grep -rls 'depot-lab\|8099' /etc/yum.repos.d/ 2>/dev/null | head -1)
if [ -n "$REPO" ]; then
  ok "dépôt déclaré : $REPO"
  grep -qE '^gpgcheck[[:space:]]*=[[:space:]]*1' "$REPO" \
    && ok "gpgcheck=1" \
    || ko "gpgcheck=1 absent de $REPO : les paquets ne sont pas vérifiés"
  grep -qE '^gpgkey[[:space:]]*=' "$REPO" \
    && ok "gpgkey= renseigné" \
    || ko "gpgkey= absent : dnf ne saura pas quelle clé importer"
  grep -qE '^enabled[[:space:]]*=[[:space:]]*1' "$REPO" \
    && ok "dépôt activé" || ko "enabled=1 manquant"
else
  ko "aucun fichier de /etc/yum.repos.d/ ne décrit le dépôt interne"
fi

# --- 2. la clé importée dans la base rpm ---------------------------------
if rpm -q gpg-pubkey --qf '%{SUMMARY}\n' 2>/dev/null \
     | grep -qi 'depot@lab.local'; then
  ok "la clé du dépôt est importée (rpm -q gpg-pubkey)"
else
  ko "clé absente de la base rpm : sudo rpm --import <clé>"
fi

# --- 3. le paquet installé, et attribué au dépôt --------------------------
if rpm -q outil-lab >/dev/null 2>&1; then
  ok "outil-lab installé ($(rpm -q --qf '%{VERSION}' outil-lab))"
  FROM=$(dnf -q repoquery --installed --qf '%{from_repo}' outil-lab \
         2>/dev/null | head -1)
  case "$FROM" in
    ""|"@System"|"@commandline")
      ko "outil-lab n'est rattaché à aucun dépôt (from_repo=$FROM) : \
tu l'as posé avec rpm -i au lieu de dnf install" ;;
    *) ok "installé depuis le dépôt « $FROM »" ;;
  esac
  rpm -V outil-lab >/dev/null 2>&1 \
    && ok "rpm -V outil-lab ne signale aucune altération" \
    || note "rpm -V signale des écarts — normal si tu as modifié le \
fichier de configuration"
else
  ko "outil-lab n'est pas installé (sudo dnf install outil-lab)"
fi

# --- 4. l'historique dnf porte la trace d'un undo ------------------------
HIST=$(dnf history list 2>/dev/null | head -20)
if printf '%s' "$HIST" | grep -qiE '^\s*[0-9]+ +\|.*(Erase|Removed|Undone)'; then
  ok "l'historique dnf contient une transaction annulée ou une suppression"
else
  ko "aucune trace d'annulation dans dnf history : l'étape 5 demande un \
dnf history undo"
fi

# --- 5. dnf-automatic : sécurité seulement, appliquée, sans reboot -------
CONF=/etc/dnf/automatic.conf
if [ -f "$CONF" ]; then
  ok "$CONF présent"
  grep -qE '^upgrade_type[[:space:]]*=[[:space:]]*security' "$CONF" \
    && ok "upgrade_type = security" \
    || ko "upgrade_type doit valoir security, pas default"
  grep -qE '^(apply_updates|download_updates)[[:space:]]*=' "$CONF" \
    && ok "apply_updates / download_updates explicitement réglés" \
    || ko "règle explicitement download_updates et apply_updates"
  if systemctl is-enabled dnf-automatic.timer >/dev/null 2>&1; then
    ok "dnf-automatic.timer actif au démarrage"
  else
    ko "dnf-automatic.timer n'est pas activé \
(systemctl enable --now dnf-automatic.timer)"
  fi
else
  ko "$CONF absent : sudo dnf install -y dnf-automatic"
fi

# --- 6. le rapport --------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 10 ]; then
  ok "rapport rhel.md rédigé"
  for mot in 'rpm -qf' 'history' 'EPEL'; do
    grep -qiF "$mot" "$RAP" \
      && ok "le rapport traite « $mot »" \
      || ko "le rapport doit traiter « $mot »"
  done
else
  ko "rapport absent ou trop court : ~/lab10/rapports/rhel.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
