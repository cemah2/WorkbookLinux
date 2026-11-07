#!/usr/bin/env bash
# setup_M07.sh — prépare le terrain du module 07 (scripting bash)
# Se lance sans sudo (ou avec : le contenu reste la propriété de l'apprenant).
# Idempotent : relançable sans effet de bord.
set -euo pipefail

# lancé avec sudo : on travaille pour l'utilisateur d'origine ; sans sudo :
# pour l'utilisateur courant.
if [ "$(id -u)" -eq 0 ]; then
  LAB_USER="${SUDO_USER:-root}"
else
  LAB_USER="$(id -un)"
fi
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab07"

echo "== Préparation du module 07 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 1. Arborescence de travail
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,data,logs,archives,conf,rapports,casse,var,depot}

# ---------------------------------------------------------------------
# 2. Jeux de données
# ---------------------------------------------------------------------

# inventaire.csv : séparateur ';', un champ contenant des espaces,
# une ligne à champ surnuméraire, et PAS de saut de ligne final (volontaire).
{
  printf 'hote;ip;role;env\n'
  printf 'lab-adm;10.10.10.10;bastion;prod\n'
  printf 'lab-web;10.10.10.11;frontal web;prod\n'
  printf 'lab-db;10.10.10.12;base de donnees;prod\n'
  printf 'lab-rhel;10.10.10.13;recette rhel;recette\n'
  printf 'lab-ops;10.10.10.14;ci;outillage\n'
  printf 'web-02;10.10.10.21;frontal web;recette\n'
  printf 'web-03;10.10.10.22;frontal web;dev\n'
  printf 'db-02;10.10.10.23;base de donnees;recette\n'
  printf 'cache-01;10.10.10.31;cache;prod;a-decommissionner\n'
  printf 'runner-01;10.10.10.32;ci;outillage'
} > "$BASE/data/inventaire.csv"

# serveurs.txt : idem, dernière ligne sans \n final
{
  printf 'lab-web\nlab-db\nlab-ops\nweb-02\nweb-03\ndb-02\n'
  printf 'runner-01'
} > "$BASE/data/serveurs.txt"

# seuils.conf : fichier clé=valeur à lire en while read
cat > "$BASE/conf/seuils.conf" <<'EOF'
# seuils de supervision factura
disque_max=85
charge_max=4.00
erreurs_max=25
retention_jours=7
EOF

cat > "$BASE/conf/factura.conf" <<'EOF'
# configuration factura
listen = 0.0.0.0:80
data_dir = /srv/factura
log_level = info
EOF

# ---------------------------------------------------------------------
# 3. Journaux applicatifs (pour les comptages et la purge)
# ---------------------------------------------------------------------
gen_log() {
  local f="$1" jour="$2" nb_err="$3" i
  : > "$f"
  for ((i = 1; i <= 40; i++)); do
    printf '%s 08:%02d:%02d INFO  requete /api/v1/factures id=%d\n' \
      "$jour" "$((i % 60))" "$((i * 7 % 60))" "$((1000 + i))" >> "$f"
  done
  for ((i = 1; i <= nb_err; i++)); do
    printf '%s 09:%02d:%02d ERROR timeout backend=db-0%d essai=%d\n' \
      "$jour" "$((i % 60))" "$((i * 3 % 60))" "$((i % 2 + 1))" "$i" >> "$f"
  done
  for ((i = 1; i <= 5; i++)); do
    printf '%s 10:%02d:00 WARN  cache miss cle=session-%d\n' \
      "$jour" "$((i * 4))" "$i" >> "$f"
  done
}

gen_log "$BASE/logs/app-2026-09-12.log" 2026-09-12 12
gen_log "$BASE/logs/app-2026-09-13.log" 2026-09-13 3
gen_log "$BASE/logs/app-2026-09-14.log" 2026-09-14 31
gen_log "$BASE/logs/app-2026-09-15.log" 2026-09-15 7
gen_log "$BASE/logs/app-2026-09-16.log" 2026-09-16 44
gen_log "$BASE/logs/app-2026-09-17.log" 2026-09-17 9
gen_log "$BASE/logs/app-2026-09-18.log" 2026-09-18 2
# nom hostile : espace dans le nom, c'est le révélateur du word splitting
gen_log "$BASE/logs/rapport final.log" 2026-09-11 6

# ---------------------------------------------------------------------
# 4. Archives à purger (dates de modification étalées)
# ---------------------------------------------------------------------
mk_archive() {
  local nom="$1" jours="$2"
  printf 'archive factice %s\n' "$nom" > "$BASE/archives/$nom"
  touch -d "$jours days ago" "$BASE/archives/$nom"
}

mk_archive 'factura-2026-08-20.tar.gz' 29
mk_archive 'factura-2026-08-27.tar.gz' 22
mk_archive 'factura-2026-09-03.tar.gz' 15
mk_archive 'factura-2026-09-10.tar.gz' 8
mk_archive 'factura-2026-09-14.tar.gz' 4
mk_archive 'factura-2026-09-17.tar.gz' 1
mk_archive 'export final.tar.gz' 20

# ---------------------------------------------------------------------
# 5. Dépôt à sauvegarder (source du défi D7)
# ---------------------------------------------------------------------
mkdir -p "$BASE/depot"/{etc,srv}
printf 'token=REMPLACER_EN_PROD\n' > "$BASE/depot/etc/api.token"
printf 'listen=8080\nworkers=4\n'  > "$BASE/depot/etc/app.conf"
printf 'id;client;montant\n1;ACME;1240.00\n' > "$BASE/depot/srv/rapport.csv"
head -c 200000 /dev/urandom > "$BASE/depot/srv/blob.bin"

# ---------------------------------------------------------------------
# 6. Scripts de départ (permissions et modes d'exécution, E7.1 à E7.3)
# ---------------------------------------------------------------------
cat > "$BASE/bin/bonjour.sh" <<'EOF'
#!/usr/bin/env bash
# script volontairement livré SANS le bit d'exécution
echo "bonjour depuis $0, pid $$, shell $BASH"
EOF
chmod 644 "$BASE/bin/bonjour.sh"

cat > "$BASE/bin/portee.sh" <<'EOF'
#!/usr/bin/env bash
# sert à comparer ./portee.sh, bash portee.sh et source portee.sh
MARQUEUR="pose par portee.sh"
cd /tmp || exit 1
echo "pid=$$  pwd=$PWD  MARQUEUR=$MARQUEUR"
EOF
chmod 755 "$BASE/bin/portee.sh"

# ---------------------------------------------------------------------
# 7. Scripts buggés fournis pour les exercices guidés de relecture
# ---------------------------------------------------------------------
cat > "$BASE/casse/compte-erreurs.sh" <<'EOF'
#!/bin/bash
# compte-erreurs.sh — compte les ERROR de chaque journal.
# Écrit tel quel par un stagiaire. Cinq défauts au moins.
DIR=$1
for f in `ls $DIR`
do
  n=`grep -c ERROR $DIR/$f`
  if [ $n > 10 ]; then
    echo "$f : beaucoup d'erreurs ($n)"
  fi
done
EOF
chmod 755 "$BASE/casse/compte-erreurs.sh"

cat > "$BASE/casse/menage.sh" <<'EOF'
#!/bin/bash
# menage.sh — supprime le contenu d'un sous-répertoire de travail.
CIBLE=$1
cd /tmp/travail
rm -rf $CIBLE/*
echo "menage fait"
EOF
chmod 755 "$BASE/casse/menage.sh"

# ---------------------------------------------------------------------
# 8. Emplacement des verrous
# ---------------------------------------------------------------------
mkdir -p "$BASE/var/run"

# ---------------------------------------------------------------------
# 9. Propriétaire final
# ---------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ "$LAB_USER" != root ]; then
  chown -R "$LAB_USER":"$LAB_USER" "$BASE"
fi

command -v shellcheck >/dev/null 2>&1 || \
  echo "  note : shellcheck n'est pas installé (voir §7.1)"
command -v flock >/dev/null 2>&1 || \
  echo "  note : flock manque (paquet util-linux)"

cat <<EOF

Prêt. Points d'entrée :
  $BASE/bin/bonjour.sh      script sans bit d'exécution (E7.1)
  $BASE/bin/portee.sh       ./ vs bash vs source (E7.2)
  $BASE/data/inventaire.csv CSV ';' sans saut de ligne final (E7.9, L7.2)
  $BASE/data/serveurs.txt   liste sans saut de ligne final (E7.8)
  $BASE/logs/               journaux + un nom avec espace (E7.12, L7.1)
  $BASE/archives/           archives datées à purger (L7.3, D7)
  $BASE/conf/seuils.conf    clé=valeur à parser (E7.10)
  $BASE/casse/              scripts à relire et corriger (E7.15, E7.16)
  $BASE/depot/              arborescence à sauvegarder (D7)
EOF
