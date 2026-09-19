#!/usr/bin/env bash
# setup_M17.sh — prépare le terrain du module 17
#                (cron, at, anacron, timers systemd)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
#
# Ce script NE crée AUCUNE tâche planifiée « propre » : les écrire est le
# travail du module. Il installe l'application factura, un certificat qui
# expire bientôt, le bac à sable de l'apprenant, et le fatras de tâches
# héritées que L17.1 doit inventorier.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab17"
BIN=/opt/factura/bin
ETC=/etc/factura
LOGD=/var/log/factura
DATA=/srv/factura/data
BACK=/srv/factura/backups
ETAT=/srv/factura/etat
STATE=/var/lib/factura

echo "== Préparation du module 17 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 1. Compte de service, répertoires
# ---------------------------------------------------------------------
groupadd -f factura
if ! getent passwd factura >/dev/null; then
  useradd -r -g factura -d /srv/factura -s /usr/sbin/nologin factura
fi

mkdir -p "$BIN" "$ETC/tls" "$LOGD" "$DATA" "$BACK" "$ETAT" "$STATE"
mkdir -p "$BASE"/{bin,logs,rapports,unites,sauv}
chown -R factura:factura "$LOGD" /srv/factura "$STATE"
chmod 0755 /opt/factura "$BIN" "$ETC" /srv/factura "$DATA" "$BACK" "$ETAT"
chmod 0775 "$LOGD"
chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# jeu de données à sauvegarder
for i in 01 02 03 04 05; do
  f="$DATA/factures-2026-$i.csv"
  [ -f "$f" ] || {
    printf 'id;client;montant\n' > "$f"
    for n in $(seq 1 40); do
      printf 'F%s%04d;client-%02d;%d.00\n' "$i" "$n" \
        $(( n % 12 + 1 )) $(( n * 37 + 100 )) >> "$f"
    done
  }
done
chown -R factura:factura "$DATA"

# compteur de BF17.3 (valeur initiale cohérente)
[ -f "$ETAT/compteur.txt" ] || echo 1000 > "$ETAT/compteur.txt"
chown factura:factura "$ETAT/compteur.txt"

# ---------------------------------------------------------------------
# 2. /usr/local/bin/factura-inventaire
#    Volontairement hors du PATH de cron (/usr/bin:/bin) mais DANS le
#    secure_path de sudo : c'est le ressort de BF17.1 et de E17.5.
# ---------------------------------------------------------------------
cat > /usr/local/bin/factura-inventaire <<'EOF'
#!/usr/bin/env bash
# factura-inventaire — compte les enregistrements du jeu de données.
set -euo pipefail
DIR="${1:-/srv/factura/data}"
n=0
for f in "$DIR"/*.csv; do
  [ -f "$f" ] || continue
  n=$(( n + $(( $(wc -l < "$f") - 1 )) ))
done
printf '%d\n' "$n"
EOF
chmod 0755 /usr/local/bin/factura-inventaire

# ---------------------------------------------------------------------
# 3. Les scripts factura
# ---------------------------------------------------------------------

# 3.1 collecte : dépend de factura-inventaire trouvé via le PATH
cat > "$BIN/factura-collecte.sh" <<'EOF'
#!/usr/bin/env bash
# factura-collecte.sh — collecte périodique (workbook, module 17).
# Appelle factura-inventaire SANS chemin absolu : c'est volontaire,
# le module s'appuie dessus.
set -euo pipefail
LOG="${FACTURA_LOG:-/var/log/factura/collecte.log}"
DATA="${FACTURA_DATA:-/srv/factura/data}"
n=$(factura-inventaire "$DATA")
printf '%s collecte ok : %s enregistrements\n' \
  "$(date '+%F %T')" "$n" >> "$LOG"
EOF

# 3.2 rapport : produit un rapport, écrit sur stdout ET stderr
cat > "$BIN/factura-rapport.sh" <<'EOF'
#!/usr/bin/env bash
# factura-rapport.sh — rapport quotidien (workbook, module 17).
set -euo pipefail
DATA="${FACTURA_DATA:-/srv/factura/data}"
OUT="${FACTURA_RAPPORTS:-/srv/factura/etat}"
mkdir -p "$OUT"
cible="$OUT/rapport-$(date '+%Y%m%d-%H%M%S').txt"
printf 'rapport factura du %s\n' "$(date '+%F %T')" > "$cible"
total=0
for f in "$DATA"/*.csv; do
  [ -f "$f" ] || continue
  l=$(( $(wc -l < "$f") - 1 ))
  printf '  %-28s %4d lignes\n' "$(basename "$f")" "$l" >> "$cible"
  total=$(( total + l ))
done
printf '  TOTAL %d\n' "$total" >> "$cible"
echo "rapport écrit : $cible"
[ "$total" -gt 0 ] || echo "ATTENTION : jeu de données vide" >&2
EOF

# 3.3 lent : occupe le verrou pour les démos de concurrence
cat > "$BIN/factura-lent.sh" <<'EOF'
#!/usr/bin/env bash
# factura-lent.sh [secondes] — simule un traitement long.
set -euo pipefail
d="${1:-30}"
echo "$(date '+%T') début (pid $$, ${d}s)"
sleep "$d"
echo "$(date '+%T') fin (pid $$)"
EOF

# 3.4 compteur : lecture-modification-écriture non atomique.
#     C'est le cœur de BF17.3 : deux exécutions qui se chevauchent
#     perdent un incrément ou écrivent un fichier incohérent.
cat > "$BIN/factura-compteur.sh" <<'EOF'
#!/usr/bin/env bash
# factura-compteur.sh — cumule les factures traitées.
# Lecture, calcul, écriture : trois étapes distinctes, non atomiques.
set -euo pipefail
F="${FACTURA_COMPTEUR:-/srv/factura/etat/compteur.txt}"
LENT="${FACTURA_LENTEUR:-4}"
valeur=$(cat "$F")            # 1. lecture
lot=$(factura-inventaire "${FACTURA_DATA:-/srv/factura/data}")
sleep "$LENT"                 # 2. le traitement réel prendrait ce temps
: > "$F"                      # 3. troncature
sleep 0.2
printf '%d' $(( valeur + lot )) >> "$F"   # 4. écriture
echo "$(date '+%T') compteur : $valeur -> $(( valeur + lot ))"
EOF

chmod 0755 "$BIN"/*.sh
chown root:root "$BIN"/*.sh

# ---------------------------------------------------------------------
# 4. ~/lab17/bin/rapport.sh — le script de E17.5
# ---------------------------------------------------------------------
cat > "$BASE/bin/rapport.sh" <<'EOF'
#!/usr/bin/env bash
# rapport.sh — marche en session, échoue en cron. À toi de dire pourquoi.
set -euo pipefail
echo "PATH vu par le script : $PATH"
n=$(factura-inventaire)
echo "$n enregistrements"
EOF
chmod 0755 "$BASE/bin/rapport.sh"
chown "$LAB_USER":"$LAB_USER" "$BASE/bin/rapport.sh"

# /opt/factura/bin dans le PATH de l'apprenant (session interactive)
PROF="$LAB_HOME/.profile"
if [ -f "$PROF" ] && ! grep -q 'opt/factura/bin' "$PROF"; then
  printf '\n# workbook module 17\nPATH="$PATH:/opt/factura/bin"\n' >> "$PROF"
fi

# ---------------------------------------------------------------------
# 5. Certificat TLS qui expire dans 12 jours (L17.4)
# ---------------------------------------------------------------------
CRT="$ETC/tls/portail.crt"
KEY="$ETC/tls/portail.key"
regen=1
if [ -f "$CRT" ] && openssl x509 -in "$CRT" -noout -checkend 0 >/dev/null 2>&1
then
  regen=0
fi
if [ "$regen" -eq 1 ]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 12 \
      -keyout "$KEY" -out "$CRT" \
      -subj "/CN=portail.lab.local/O=Factura/C=FR" >/dev/null 2>&1
    chmod 0640 "$KEY"; chmod 0644 "$CRT"
    chown root:factura "$KEY" "$CRT"
  else
    echo "  ! openssl absent : certificat non généré (L17.4 inapplicable)" >&2
  fi
fi

# ---------------------------------------------------------------------
# 6. Unité de montage référencée par L17.3 (créée, NI activée NI démarrée)
# ---------------------------------------------------------------------
mkdir -p /var/lib/factura-store
cat > /etc/systemd/system/srv-factura.mount <<'EOF'
# Unité de montage de démonstration (workbook module 17).
# Volontairement NI activée NI démarrée : elle sert uniquement de cible
# à une dépendance d'ordre (After=) dans L17.3.
[Unit]
Description=Stockage factura (demonstration workbook)

[Mount]
What=/var/lib/factura-store
Where=/srv/factura
Type=none
Options=bind

[Install]
WantedBy=local-fs.target
EOF

# ---------------------------------------------------------------------
# 7. Le fatras hérité que L17.1 doit inventorier
# ---------------------------------------------------------------------

# 7.1 crontab de l'utilisateur factura : sortie jetée dans /dev/null
if command -v crontab >/dev/null 2>&1; then
  TMPC=$(mktemp)
  cat > "$TMPC" <<'EOF'
# héritage prestataire — ne pas modifier sans ticket (sic)
MAILTO=""
13 4 * * * /opt/factura/bin/factura-rapport.sh > /dev/null 2>&1
EOF
  crontab -u factura "$TMPC"
  rm -f "$TMPC"
else
  echo "  ! crontab absent : installe le paquet cron (voir §17.1)" >&2
fi

# 7.2 /etc/cron.d bien formé (avec champ utilisateur et PATH)
cat > /etc/cron.d/factura-veille-legacy <<'EOF'
# Tâche héritée : purge des rapports de plus de 30 jours.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
40 5 * * * factura find /srv/factura/etat -name 'rapport-*' -mtime +30 -delete
EOF
chmod 0644 /etc/cron.d/factura-veille-legacy

# 7.3 /etc/cron.d mal formé : pas de champ utilisateur (anomalie L17.1)
cat > /etc/cron.d/factura-archives <<'EOF'
# ANOMALIE VOLONTAIRE (workbook) : il manque le champ utilisateur.
*/30 * * * * /opt/factura/bin/factura-lent.sh 2
EOF
chmod 0644 /etc/cron.d/factura-archives

# 7.4 deux scripts dans cron.daily, dont un que run-parts ignorera
cat > /etc/cron.daily/factura-purge <<'EOF'
#!/bin/sh
# purge quotidienne des journaux de plus de 14 jours
find /var/log/factura -name '*.log.*' -mtime +14 -delete 2>/dev/null
exit 0
EOF
cat > /etc/cron.daily/factura-stats.sh <<'EOF'
#!/bin/sh
# ANOMALIE VOLONTAIRE (workbook) : le nom contient un point, donc
# run-parts ne l'exécutera jamais.
/opt/factura/bin/factura-rapport.sh >> /var/log/factura/stats.log 2>&1
EOF
chmod 0755 /etc/cron.daily/factura-purge /etc/cron.daily/factura-stats.sh

# 7.5 un timer activé dont le service n'existe pas (anomalie L17.1)
cat > /etc/systemd/system/factura-orphelin.timer <<'EOF'
# ANOMALIE VOLONTAIRE (workbook) : ce timer déclenche une unité
# factura-orphelin.service qui n'existe pas.
[Unit]
Description=Timer herite sans service associe

[Timer]
OnCalendar=*-*-* 05:20:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl enable factura-orphelin.timer >/dev/null 2>&1 || true
  systemctl start  factura-orphelin.timer >/dev/null 2>&1 || true
fi

# journaux de départ
touch "$LOGD/collecte.log" "$LOGD/alertes.log"
chown factura:factura "$LOGD"/*.log
chmod 0664 "$LOGD"/*.log

cat <<EOF

Terrain prêt.

  application  : /opt/factura/bin/ (collecte, rapport, lent, compteur)
  utilitaire   : /usr/local/bin/factura-inventaire
  données      : $DATA   sauvegardes : $BACK
  état         : $ETAT   témoin : $STATE
  certificat   : $CRT (expire dans ~12 jours)
  bac à sable  : $BASE

Héritage à inventorier en L17.1 : crontab de « factura »,
/etc/cron.d/factura-*, /etc/cron.daily/factura-*, factura-orphelin.timer.

Rappel : ce script ne crée aucune planification propre, c'est ton travail.
EOF
