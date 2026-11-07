#!/usr/bin/env bash
# setup_M28.sh — prépare le terrain du module 28 (identité centralisée)
# À lancer avec sudo sur lab-rhel, lab-web, lab-db et lab-adm. Idempotent.
#
# Ce script N'INSTALLE NI FreeIPA NI le client : c'est le travail du module.
# Il fournit la matière (comptes à importer, clés de test, ancienne clé de
# sauvegarde) et fait le bilan des prérequis d'une machine Kerberos : nom
# pleinement qualifié, résolution directe et inverse, heure, mémoire.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab28"
DOMAINE=lab.local
SERVEUR=lab-rhel.lab.local

role=inconnu; IP=""
for a in $(hostname -I); do
  case "$a" in
    10.10.10.10) role=adm;     IP=$a ;;
    10.10.10.11) role=web;     IP=$a ;;
    10.10.10.12) role=db;      IP=$a ;;
    10.10.10.13) role=serveur; IP=$a ;;
  esac
done
COURT="$(hostname -s)"
FQDN="$COURT.$DOMAINE"

echo "== Préparation du module 28 =="
echo "   utilisateur : $LAB_USER"
echo "   machine     : $COURT ($IP), rôle : $role"
echo "   base        : $BASE"
[ "$role" != inconnu ] || {
  echo "   cette machine n'est pas une VM du module 28 (lab-rhel, lab-web," \
       "lab-db, lab-adm)" >&2; exit 1; }

install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$BASE"

# ---------------------------------------------------------------------
# 1. Fichier de secrets (jamais commité : les fichiers secrets* sont ignorés)
# ---------------------------------------------------------------------
if [ ! -f "$BASE/secrets.md" ]; then
  cat > "$BASE/secrets.md" <<'EOF'
# Secrets du module 28 — NE PAS COMMITER
# Directory Manager :
# admin :
# mots de passe initiaux des comptes importés (L28.1) :
EOF
fi
chown "$LAB_USER": "$BASE/secrets.md"; chmod 600 "$BASE/secrets.md"

# ---------------------------------------------------------------------
# 2. Matière propre à chaque rôle
# ---------------------------------------------------------------------
case "$role" in
  serveur)
    if [ ! -s "$BASE/utilisateurs.csv" ]; then
      cat > "$BASE/utilisateurs.csv" <<'EOF'
login;prenom;nom;groupes
alice;Alice;Martin;admins-lab
bruno;Bruno;Lefèvre;devs
chloe;Chloé;Bernard;auditeurs
david;David;Moreau;devs,auditeurs
EOF
      chown "$LAB_USER": "$BASE/utilisateurs.csv"
      echo "   comptes à importer : $BASE/utilisateurs.csv (L28.1)"
    fi
    ;;
  adm)
    install -d -o "$LAB_USER" -g "$LAB_USER" -m 700 "$BASE/cles" "$BASE/defi"
    for u in alice bruno eve; do
      if [ ! -f "$BASE/cles/$u" ]; then
        sudo -u "$LAB_USER" ssh-keygen -q -t ed25519 -N '' -C "$u@lab28" \
          -f "$BASE/cles/$u"
      fi
    done
    echo "   clés de test : $BASE/cles/{alice,bruno,eve}[.pub] (E28.9, D28)"
    ;;
  web)
    install -d -o "$LAB_USER" -g "$LAB_USER" -m 700 "$BASE/ancienne-cle"
    CLE="$BASE/ancienne-cle/id_sauvegarde"
    ETAT=/var/lib/lab28
    install -d -m 700 "$ETAT"
    if [ ! -f "$ETAT/ancienne-cle.fp" ]; then
      sudo -u "$LAB_USER" ssh-keygen -q -t ed25519 -N '' \
        -C sauvegarde-legacy -f "$CLE"
      AK="$LAB_HOME/.ssh/authorized_keys"
      install -d -o "$LAB_USER" -g "$LAB_USER" -m 700 "$LAB_HOME/.ssh"
      cat "$CLE.pub" >> "$AK"
      chown "$LAB_USER": "$AK"; chmod 600 "$AK"
      ssh-keygen -lf "$CLE.pub" | awk '{print $2}' > "$ETAT/ancienne-cle.fp"
      echo "   ancienne clé de sauvegarde posée et autorisée pour $LAB_USER" \
           "(L28.4, étape 6)"
    fi
    ;;
esac

# ---------------------------------------------------------------------
# 3. Bilan des prérequis
# ---------------------------------------------------------------------
echo
echo "== Prérequis Kerberos / FreeIPA =="
AVERT=0
ok()    { printf '  [ OK ] %s\n' "$1"; }
avert() { printf '  [AVERT] %s\n' "$1"; AVERT=$((AVERT + 1)); }

# nom pleinement qualifié (obligatoire sur le serveur ; ipa-client-install
# --hostname le pose sur les clients)
if [ "$(hostname)" = "$FQDN" ]; then
  ok "nom pleinement qualifié : $FQDN"
elif [ "$role" = serveur ]; then
  avert "le nom n'est pas $FQDN : sudo hostnamectl set-hostname $FQDN"
else
  ok "nom court ($COURT) : ipa-client-install --hostname=$FQDN le corrigera"
fi
[ -f /etc/cloud/cloud.cfg.d/99-fqdn.cfg ] \
  && ok "cloud-init ne réécrira pas le nom (preserve_hostname)" \
  || avert "cloud-init peut remettre le nom court au démarrage : echo" \
"'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-fqdn.cfg"

# résolution directe : pas une adresse de boucle locale
DIR=$(getent ahostsv4 "$FQDN" | awk 'NR==1{print $1}')
case "$DIR" in
  "$IP") ok "$FQDN se résout en $IP" ;;
  127.*) avert "$FQDN se résout en $DIR (boucle locale) : corrige /etc/hosts" ;;
  "")    avert "$FQDN ne se résout pas : /etc/hosts ou dnsmasq du nœud" ;;
  *)     avert "$FQDN se résout en $DIR au lieu de $IP" ;;
esac

# résolution inverse
INV=$(getent hosts "$IP" | awk '{print $2}')
[ "$INV" = "$FQDN" ] \
  && ok "résolution inverse : $IP -> $INV" \
  || avert "résolution inverse de $IP : « ${INV:-rien} » au lieu de $FQDN"

# le serveur, vu par tous
SRV=$(getent ahostsv4 "$SERVEUR" | awk 'NR==1{print $1}')
[ "$SRV" = 10.10.10.13 ] \
  && ok "$SERVEUR se résout en 10.10.10.13" \
  || avert "$SERVEUR se résout en « ${SRV:-rien} »"

# mDNS : avec mdns4_minimal, les noms en .local partent en multicast
if grep -Eq '^hosts:.*mdns' /etc/nsswitch.conf; then
  avert "nsswitch.conf interroge mDNS pour les noms en .local : retire" \
"mdns4_minimal de la ligne hosts (ou évite .local en production)"
else
  ok "pas de mDNS dans la résolution des noms (.local sans surprise)"
fi

# heure synchronisée
if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; then
  ok "horloge synchronisée (Kerberos tolère 5 minutes d'écart)"
else
  avert "horloge non synchronisée : systemctl enable --now chrony" \
"(chronyd sur Rocky), puis chronyc tracking"
fi

# mémoire du serveur
if [ "$role" = serveur ]; then
  MEM=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  [ "$MEM" -ge 3400 ] \
    && ok "mémoire : $MEM Mo" \
    || avert "mémoire : $MEM Mo ; FreeIPA veut 4 Go (qm set 9004 --memory 4096)"
fi

# le serveur répond-il déjà ? (information, pas une erreur avant L28.1)
if [ "$role" != serveur ]; then
  if timeout 2 bash -c "</dev/tcp/$SERVEUR/88" 2>/dev/null; then
    ok "le KDC de $SERVEUR répond (88/tcp)"
  else
    echo "  [info] le KDC de $SERVEUR ne répond pas encore (normal avant L28.1)"
  fi
fi

echo
if [ "$AVERT" -eq 0 ]; then
  echo "Prérequis réunis : tu peux commencer."
else
  echo "$AVERT avertissement(s) : corrige-les AVANT d'installer quoi que ce soit."
fi
