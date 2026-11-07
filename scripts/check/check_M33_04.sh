#!/usr/bin/env bash
# check_M33_04.sh — vérifie le lab L33.4 (dépôts signés apt et dnf)
# À lancer sans sudo sur lab-adm et lab-db, avec sudo sur lab-rhel.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L33.4 =="
WEB=http://lab-web.lab.local:8033
UIDDEPOT='Dépôt lab33 <depot@lab.local>'

role=""
for a in $(hostname -I 2>/dev/null); do
  case "$a" in 10.10.10.10) role=adm ;; 10.10.10.12) role=db ;; 10.10.10.13) role=rhel ;; esac
done
if [ -z "$role" ]; then
  if [ -f /etc/redhat-release ]; then role=rhel
  elif [ -d "$HOME/lab33/reprepro" ]; then role=adm
  else role=db; fi
fi
echo "   rôle : $role"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# =============================================================================
if [ "$role" = adm ]; then
  [ "$(id -u)" -ne 0 ] || { ko "sur lab-adm, lance le contrôle SANS sudo (trousseau de ton compte)"; fin; }
  L="$HOME/lab33"
  P="$L/publication"

  # --- la clé -----------------------------------------------------------------
  cle=$(gpg --list-secret-keys --with-colons "=$UIDDEPOT" 2>/dev/null)
  if [ -z "$cle" ]; then
    ko "pas de clé secrète « $UIDDEPOT »"; fin
  fi
  ok "clé « Dépôt lab33 » présente"
  FPR=$(printf '%s\n' "$cle" | awk -F: '/^fpr/{print $10; exit}')
  printf '%s\n' "$cle" | awk -F: '$1=="sec"{print $12}' | has -v 's' \
    && ok "clé principale réservée à la certification" \
    || note "la clé principale signe aussi : une sous-clé de signature suffit"
  printf '%s\n' "$cle" | awk -F: '$1=="ssb" && $12 ~ /s/' | has . \
    && ok "sous-clé de signature" || ko "pas de sous-clé de signature (gpg --quick-add-key … sign)"
  exp=$(printf '%s\n' "$cle" | awk -F: '$1=="sec"{print $7}')
  if [ -n "$exp" ]; then
    j=$(( (exp - $(date +%s)) / 86400 ))
    [ "$j" -le 1100 ] && ok "expiration fixée (dans $j jours)" || ko "expiration trop lointaine (dans $j jours, deux ans attendus)"
  else
    ko "la clé n'expire jamais (expiration à deux ans attendue)"
  fi
  prot=1
  for kg in $(printf '%s\n' "$cle" | awk -F: '/^grp/{print $10}'); do
    gpg-connect-agent "KEYINFO $kg" /bye 2>/dev/null | has -E "^S KEYINFO $kg .* C " && prot=0
  done
  [ "$prot" -eq 1 ] && ok "clé protégée par une phrase de passe" || ko "une partie de la clé n'a pas de phrase de passe"

  # --- clé publique exportée -----------------------------------------------------
  head -1 "$P/lab33.asc" 2>/dev/null | has 'BEGIN PGP PUBLIC KEY BLOCK' && ok "publication/lab33.asc (armé)" \
                                                                       || ko "publication/lab33.asc absent ou non armé"
  gpg --show-keys --with-colons "$P/lab33.gpg" 2>/dev/null | has ":$FPR:" \
    && ok "publication/lab33.gpg (binaire) contient la clé du dépôt" || ko "publication/lab33.gpg absent ou autre clé"
  gpg --show-keys --with-colons "$P/lab33.gpg" 2>/dev/null | has '^sec' && ko "lab33.gpg contient une clé SECRÈTE"

  # --- dépôt apt -------------------------------------------------------------------
  C="$L/reprepro/conf/distributions"
  if [ -s "$C" ]; then
    ok "reprepro configuré dans lab33/reprepro"
    has -E '^Codename:[[:space:]]*lab33' "$C" && ok "distribution lab33" || ko "pas de Codename: lab33"
    has -E '^Components:.*main' "$C" && ok "composant main" || ko "pas de composant main"
    has -E '^Architectures:.*amd64' "$C" && has -E '^Architectures:.*source' "$C" \
      && ok "architectures amd64 et source" || ko "Architectures : amd64 et source attendues"
    has -E '^SignWith:' "$C" && ok "SignWith présent" || ko "pas de SignWith : dépôt non signé"
  else
    ko "lab33/reprepro/conf/distributions absent"
  fi
  find "$P" \( -name distributions -o -name options -o -path '*/db/*' \) 2>/dev/null | has . \
    && ko "la configuration ou la base de reprepro est dans publication/" || ok "configuration et base de reprepro hors de publication/"
  IR="$P/debian/dists/lab33/InRelease"
  if [ -s "$IR" ]; then
    gpgv --keyring "$P/lab33.gpg" "$IR" >/dev/null 2>&1 && ok "InRelease signé par la clé publiée" \
                                                       || ko "InRelease : signature invalide avec publication/lab33.gpg"
    has '^Valid-Until:' "$IR" && note "Valid-Until présent : republier avant expiration"
  else
    ko "publication/debian/dists/lab33/InRelease absent"
  fi
  if command -v reprepro >/dev/null && [ -s "$C" ]; then
    lst=$(reprepro -b "$L/reprepro" list lab33 2>/dev/null)
    printf '%s\n' "$lst" | has -E '\|amd64: lab33-sante 1\.1-1' && ok "lab33-sante 1.1-1 (amd64) dans le dépôt" \
                                                                 || ko "lab33-sante 1.1-1 amd64 absent du dépôt"
    printf '%s\n' "$lst" | has -E '\|source: lab33-sante 1\.1-1' && ok "paquet source 1.1-1 dans le dépôt" \
                                                                  || ko "paquet source 1.1-1 absent du dépôt (includedsc)"
  fi

  # --- dépôt dnf --------------------------------------------------------------------
  R="$P/rpm/el9/x86_64"
  if [ -s "$R/repodata/repomd.xml" ]; then
    ok "dépôt RPM généré (repodata/repomd.xml)"
    gpgv --keyring "$P/lab33.gpg" "$R/repodata/repomd.xml.asc" "$R/repodata/repomd.xml" >/dev/null 2>&1 \
      && ok "repomd.xml signé (signature détachée valide)" || ko "repomd.xml.asc absent ou invalide"
    head -1 "$R/repodata/repomd.xml.asc" 2>/dev/null | has 'BEGIN PGP SIGNATURE' \
      && ok "signature détachée armée" || ko "repomd.xml.asc n'est pas une signature armée (--armor)"
    n=0
    mkdir -p "$t/rpmdb"
    rpmkeys --dbpath "$t/rpmdb" --import "$P/lab33.asc" 2>/dev/null
    for r in "$R"/*.rpm; do
      [ -e "$r" ] || continue
      n=$((n+1))
      rpmkeys --dbpath "$t/rpmdb" -K "$r" 2>/dev/null | has 'signatures OK' \
        && ok "$(basename "$r") signé par la clé du dépôt" || ko "$(basename "$r") non signé ou mal signé"
    done
    [ "$n" -gt 0 ] || ko "aucun RPM dans publication/rpm/el9/x86_64"
    ls "$R"/lab33-sante-1.1-*.rpm >/dev/null 2>&1 && ok "RPM 1.1 publié" || ko "pas de RPM lab33-sante 1.1 dans le dépôt"
  else
    ko "publication/rpm/el9/x86_64/repodata/repomd.xml absent"
  fi

  # --- publication -----------------------------------------------------------------
  K="$HOME/.ssh/id_depot"
  if [ -f "$K" ]; then
    ok "clé SSH de publication id_depot"
    S="ssh -i $K -o BatchMode=yes -o ConnectTimeout=5"
    if rsync -n -a -e "$S" "$P/lab33.asc" depot@lab-web.lab.local: >/dev/null 2>&1; then
      ok "id_depot peut écrire dans le dépôt"
      if rsync -a -e "$S" depot@lab-web.lab.local:lab33.asc "$t/lu.asc" >/dev/null 2>&1; then
        ko "id_depot peut aussi LIRE : écriture seule attendue (rrsync -wo)"
      else
        ok "id_depot ne peut pas lire (écriture seule)"
      fi
      $S depot@lab-web.lab.local true >/dev/null 2>&1 && ko "id_depot ouvre un shell sur lab-web" \
                                                        || ok "id_depot n'ouvre pas de shell"
    else
      ko "rsync avec id_depot vers depot@lab-web.lab.local refusé"
    fi
  else
    ko "clé ~/.ssh/id_depot absente"
  fi
  if curl -fsS -o "$t/InRelease" "$WEB/debian/dists/lab33/InRelease" 2>/dev/null; then
    cmp -s "$t/InRelease" "$IR" && ok "lab-web sert l'InRelease à jour" || ko "l'InRelease servi diffère de publication/ (republie)"
  else
    ko "$WEB/debian/dists/lab33/InRelease inaccessible"
  fi
  curl -fsS -o /dev/null "$WEB/rpm/el9/x86_64/repodata/repomd.xml.asc" 2>/dev/null \
    && ok "lab-web sert repomd.xml.asc" || ko "$WEB/rpm/el9/x86_64/repodata/repomd.xml.asc inaccessible"
  curl -fsS -o /dev/null "$WEB/lab33.asc" 2>/dev/null && ok "lab-web sert la clé publique" || ko "$WEB/lab33.asc inaccessible"

  # --- publier.sh ---------------------------------------------------------------------
  PS="$L/publier.sh"
  if [ -x "$PS" ] && bash -n "$PS" 2>/dev/null; then
    ok "publier.sh présent, exécutable, syntaxe valide"
    has -E 'gpgv|gpg[^|]*--verify' "$PS" && ok "publier.sh vérifie les signatures gpg" \
                                         || ko "publier.sh ne vérifie pas InRelease / repomd.xml"
    has -E 'rpmkeys|rpm +-K|rpm +--checksig' "$PS" && ok "publier.sh vérifie la signature des RPM" \
                                                   || ko "publier.sh ne vérifie pas les RPM (BF33.3)"
    has 'rsync' "$PS" && ok "publier.sh publie par rsync" || ko "publier.sh ne publie pas"
  else
    ko "lab33/publier.sh absent, non exécutable ou invalide"
  fi
  fin
fi

# =============================================================================
if [ "$role" = db ]; then
  src=$(grep -rlE 'lab-web(\.lab\.local)?:8033' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | head -1)
  if [ -n "$src" ]; then
    ok "source apt du dépôt : $src"
  else
    ko "aucune source apt vers lab-web:8033"; fin
  fi
  case "$src" in *.sources) ok "format deb822 (.sources)" ;; *) ko "format deb822 attendu (lab33.sources)" ;; esac
  has -i 'trusted *= *yes\|trusted: *yes\|allow-insecure' "$src" && ko "le dépôt est marqué de confiance sans signature"
  kr=$(sed -n 's/^Signed-By:[[:space:]]*//p' "$src" | head -1)
  if [ -n "$kr" ] && [ -s "$kr" ]; then
    ok "Signed-By: $kr"
    case "$kr" in /etc/apt/keyrings/*|/usr/share/keyrings/*) ok "trousseau dans un répertoire dédié" ;;
                  *) ko "trousseau hors de /etc/apt/keyrings" ;; esac
    FPR=$(gpg --show-keys --with-colons "$kr" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
    for g in /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d/*; do
      [ -s "$g" ] || continue
      gpg --show-keys --with-colons "$g" 2>/dev/null | has ":$FPR:" && ko "la clé du dépôt est aussi dans le trousseau global ($g)"
    done
  else
    ko "pas de Signed-By, ou trousseau introuvable"
  fi
  li=$(find /var/lib/apt/lists -maxdepth 1 -name 'lab-web*8033*InRelease' 2>/dev/null | head -1)
  if [ -n "$li" ] && [ -n "${kr:-}" ] && gpgv --keyring "$kr" "$li" >/dev/null 2>&1; then
    ok "dernier InRelease téléchargé valide avec Signed-By"
  else
    ko "pas d'InRelease valide du dépôt dans /var/lib/apt/lists (apt update)"
  fi
  pol=$(LC_ALL=C apt-cache policy lab33-sante 2>/dev/null)
  inst=$(printf '%s\n' "$pol" | awk -F': ' '/Installed:/{print $2; exit}')
  case "$inst" in
    1.1-*) ok "lab33-sante $inst installé" ;;
    ""|"(none)") ko "lab33-sante n'est pas installé" ;;
    *) ko "lab33-sante $inst installé : la 1.1 est attendue" ;;
  esac
  printf '%s\n' "$pol" | awk '/\*\*\*/{f=1; next} f&&/^ +[0-9]+ /{print} f&&/^ +[0-9]+\.|^ +\(/{exit}' | has 'lab-web' \
    && ok "la version installée provient du dépôt lab-web" || ko "la version installée ne provient pas du dépôt (fichier .deb local ?)"
  fin
fi

# =============================================================================
[ "$(id -u)" -eq 0 ] || { ko "sur lab-rhel, lance le contrôle avec sudo"; fin; }
repo=$(grep -lE 'lab-web(\.lab\.local)?:8033' /etc/yum.repos.d/*.repo 2>/dev/null | head -1)
if [ -n "$repo" ]; then
  ok "dépôt dnf : $repo"
else
  ko "aucun fichier .repo vers lab-web:8033"; fin
fi
has -E '^gpgcheck[[:space:]]*=[[:space:]]*(1|True|yes)' "$repo" && ok "gpgcheck=1 (paquets vérifiés)" || ko "gpgcheck=1 absent"
has -E '^repo_gpgcheck[[:space:]]*=[[:space:]]*(1|True|yes)' "$repo" && ok "repo_gpgcheck=1 (métadonnées vérifiées)" \
                                                                    || ko "repo_gpgcheck=1 absent"
has -E '^(repo_)?gpgcheck[[:space:]]*=[[:space:]]*0' "$repo" && ko "une vérification est désactivée (=0)"
has -E '^gpgkey[[:space:]]*=' "$repo" && ok "gpgkey indiquée" || ko "pas de gpgkey="
rpm -q gpg-pubkey --qf '%{SUMMARY}\n' 2>/dev/null | has 'Dépôt lab33' && ok "clé du dépôt importée dans RPM" \
                                                                      || ko "clé « Dépôt lab33 » non importée (rpm -q gpg-pubkey)"
v=$(rpm -q --qf '%{VERSION}-%{RELEASE}' lab33-sante 2>/dev/null) || v=""
case "$v" in 1.1-*) ok "lab33-sante $v installé" ;; "") ko "lab33-sante n'est pas installé" ;; *) ko "lab33-sante $v : 1.1 attendue" ;; esac
if [ -n "$v" ]; then
  sig=$(rpm -q --qf '%{RSAHEADER:pgpsig}|%{SIGPGP:pgpsig}' lab33-sante 2>/dev/null)
  [ "$sig" != "(none)|(none)" ] && ok "le paquet installé est signé" || ko "le paquet installé n'est pas signé"
  LC_ALL=C dnf -q info --installed lab33-sante 2>/dev/null | has -E '^From repo[[:space:]]*: *lab33' \
    && ok "installé depuis le dépôt lab33" || ko "lab33-sante n'a pas été installé depuis le dépôt lab33 (dnf info --installed)"
fi
fin
