#!/usr/bin/env bash
# check_M10_06.sh — vérifie le défi D10 (politique de mise à jour)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D10 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
SCR="$HOMEDIR/lab10/bin/etat-paquets.sh"
RAP="$HOMEDIR/lab10/rapports/politique-maj.md"

# --- 1. le script ---------------------------------------------------------
if [ -x "$SCR" ]; then
  ok "$SCR existe et est exécutable"
  head -1 "$SCR" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang #!/usr/bin/env bash" \
    || ko "shebang attendu : #!/usr/bin/env bash"
  grep -qE '^set -euo pipefail' "$SCR" \
    && ok "set -euo pipefail présent" || ko "set -euo pipefail manquant"

  SORTIE=$(bash "$SCR" 2>/dev/null); RC=$?
  ERR=$(bash "$SCR" 2>&1 >/dev/null)

  [ -n "$SORTIE" ] && ok "le script écrit un rapport sur stdout" \
                   || ko "stdout vide"
  printf '%s' "$SORTIE" | grep -q '^#' \
    && ok "le rapport est en Markdown" \
    || ko "le rapport stdout ne contient aucun titre Markdown"

  for t in 'retenu' 'épingl' 'sécurit'; do
    printf '%s' "$SORTIE" | grep -qi "$t" \
      && ok "le rapport couvre « $t »" \
      || ko "le rapport ne dit rien sur « $t »"
  done

  if printf '%s' "$ERR" | grep -q '^#'; then
    ko "du Markdown part sur stderr : le rapport va sur stdout, la trace \
de diagnostic sur stderr"
  else
    ok "stderr ne contient pas le rapport"
  fi
  case "$RC" in
    0|1) ok "code retour $RC (0 = conforme, 1 = dérive)" ;;
    *)   ko "code retour $RC : seuls 0 et 1 sont prévus" ;;
  esac
else
  ko "$SCR introuvable ou non exécutable"
fi

# --- 2. unattended-upgrades ----------------------------------------------
if dpkg -s unattended-upgrades >/dev/null 2>&1; then
  ok "unattended-upgrades installé"
else
  ko "unattended-upgrades n'est pas installé"
fi

AUTO=/etc/apt/apt.conf.d/20auto-upgrades
if [ -f "$AUTO" ]; then
  ok "$AUTO présent"
  grep -qE 'Update-Package-Lists "1"' "$AUTO" \
    && ok "mise à jour des index activée" \
    || ko "APT::Periodic::Update-Package-Lists doit valoir \"1\""
  grep -qE 'Unattended-Upgrade "1"' "$AUTO" \
    && ok "unattended-upgrade activé" \
    || ko "APT::Periodic::Unattended-Upgrade doit valoir \"1\""
else
  ko "$AUTO absent : sudo dpkg-reconfigure -plow unattended-upgrades \
ou écris-le à la main"
fi

# Les réglages locaux doivent être dans un fichier à soi, pas dans
# 50unattended-upgrades qui est un conffile du paquet.
LOCAL=$(grep -rls 'Unattended-Upgrade::' /etc/apt/apt.conf.d/ 2>/dev/null \
        | grep -v '50unattended-upgrades' | head -1)
if [ -n "$LOCAL" ]; then
  ok "réglages locaux dans un fichier dédié : $(basename "$LOCAL")"
  CIBLE="$LOCAL"
else
  note "aucun fichier local : les réglages sont dans le conffile du \
paquet, ils déclencheront un prompt dpkg à la prochaine mise à jour"
  CIBLE=/etc/apt/apt.conf.d/50unattended-upgrades
fi

if [ -f "$CIBLE" ]; then
  grep -A20 'Allowed-Origins\|Origins-Pattern' "$CIBLE" 2>/dev/null \
    | grep -qiE '^\s*"?\$?\{?distro_id\}?:\$?\{?distro_codename\}?-security' \
    && ok "l'origine -security est autorisée" \
    || note "vérifie que \${distro_id}:\${distro_codename}-security est \
bien la seule origine décommentée"
  grep -qE '^\s*Unattended-Upgrade::Automatic-Reboot\s+"false"' "$CIBLE" \
    && ok "redémarrage automatique désactivé" \
    || ko "Automatic-Reboot doit être explicitement \"false\" sur un \
serveur de production"
  grep -qE '^\s*Unattended-Upgrade::Package-Blacklist' "$CIBLE" \
    && ok "une liste d'exclusion est définie" \
    || ko "définis Package-Blacklist, même vide : c'est le point de \
rendez-vous documenté pour exclure un paquet applicatif"
fi

if command -v unattended-upgrade >/dev/null 2>&1; then
  if unattended-upgrade --dry-run >/dev/null 2>&1; then
    ok "unattended-upgrade --dry-run s'exécute sans erreur"
  else
    ko "unattended-upgrade --dry-run échoue : la configuration est \
syntaxiquement invalide (relance-la avec --debug)"
  fi
fi

# --- 3. le rapport --------------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 15 ]; then
  ok "rapport politique-maj.md rédigé"
  for mot in 'sécurité' 'redémarrage' 'exclusion' 'rollback'; do
    grep -qi "$mot" "$RAP" \
      && ok "le rapport traite « $mot »" \
      || ko "le rapport doit traiter « $mot »"
  done
else
  ko "rapport absent ou trop court : ~/lab10/rapports/politique-maj.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
