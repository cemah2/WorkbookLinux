#!/usr/bin/env bash
# setup_M30.sh — prépare le terrain du module 30 (sauvegarde, reprise)
# À lancer avec sudo sur lab-web, lab-db et lab-ops. Idempotent.
#
# Ce script NE configure AUCUNE sauvegarde : c'est le travail du module.
# Il fournit la matière : base lab30 et table témoin (lab-db), comptes et
# répertoires du serveur de sauvegarde (lab-ops), contenu web (lab-web).
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

role=inconnu
for a in $(hostname -I); do
  case "$a" in
    10.10.10.11) role=web ;;
    10.10.10.12) role=db ;;
    10.10.10.14) role=ops ;;
  esac
done
echo "== Préparation du module 30 =="
echo "   machine : $(hostname -s), rôle : $role"
[ "$role" != inconnu ] || { echo "   pas une VM du module 30 (lab-web, lab-db, lab-ops)" >&2; exit 1; }
install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$LAB_HOME/lab30"

case "$role" in
# ---------------------------------------------------------------------------
web)
  install -d -m 755 /var/www/lab30
  if [ ! -f /var/www/lab30/index.html ]; then
    cat > /var/www/lab30/index.html <<'EOF'
<!doctype html><title>lab30</title><h1>Contenu à sauvegarder (module 30)</h1>
EOF
    for i in $(seq 1 20); do
      printf 'Document %02d du module 30, généré le %s\n' "$i" "$(date -I)" \
        > "/var/www/lab30/doc-$i.txt"
    done
    install -d -m 755 /var/www/lab30/cache
    head -c 2M /dev/urandom > /var/www/lab30/cache/a-ne-pas-sauvegarder.bin
    echo "   contenu : /var/www/lab30 (dont un cache à exclure)"
  fi
  ;;
# ---------------------------------------------------------------------------
db)
  command -v psql >/dev/null || { echo "PostgreSQL absent : module 15 d'abord" >&2; exit 1; }
  systemctl is-active -q postgresql@16-main || {
    echo "le cluster 16/main ne tourne pas" >&2; exit 1; }
  psql_() { sudo -u postgres psql -v ON_ERROR_STOP=1 -qAt "$@"; }
  if [ "$(psql_ -c "SELECT 1 FROM pg_database WHERE datname='lab30'")" != 1 ]; then
    psql_ -c "CREATE DATABASE lab30"
  fi
  psql_ -d lab30 <<'SQL'
CREATE TABLE IF NOT EXISTS factures (
  id       integer PRIMARY KEY,
  client   text NOT NULL,
  montant  numeric(10,2) NOT NULL,
  emise_le date NOT NULL
);
INSERT INTO factures
  SELECT g, 'client-' || (g % 97), round((random() * 900 + 100)::numeric, 2),
         date '2026-01-01' + (g % 300)
  FROM generate_series(1, 1000) g
  ON CONFLICT (id) DO NOTHING;
CREATE SCHEMA IF NOT EXISTS pra;
CREATE TABLE IF NOT EXISTS pra.temoin (
  t    timestamptz NOT NULL DEFAULT now(),
  hote text NOT NULL DEFAULT 'lab-db'
);
SQL
  cat > /etc/systemd/system/lab30-temoin.service <<'EOF'
[Unit]
Description=Ligne témoin pour mesurer le RPO (module 30)
After=postgresql@16-main.service

[Service]
Type=oneshot
User=postgres
ExecStart=/usr/bin/psql -qAt -d lab30 -c "INSERT INTO pra.temoin DEFAULT VALUES"
EOF
  cat > /etc/systemd/system/lab30-temoin.timer <<'EOF'
[Unit]
Description=Ligne témoin chaque minute (module 30)

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now lab30-temoin.timer >/dev/null 2>&1
  echo "   base lab30 : $(psql_ -d lab30 -c 'SELECT count(*) FROM factures') factures,"\
       "témoin chaque minute (lab30-temoin.timer)"
  ;;
# ---------------------------------------------------------------------------
ops)
  for u in restic borg pgwal; do
    if ! id "$u" >/dev/null 2>&1; then
      sh=/bin/bash; [ "$u" = restic ] && sh=/usr/sbin/nologin
      useradd --create-home --shell "$sh" "$u"
      passwd -l "$u" >/dev/null
    fi
    install -d -o "$u" -g "$u" -m 700 "/home/$u/.ssh"
  done
  install -d -o root   -g root   -m 755 /srv/restic       # racine de prison chroot
  install -d -o borg   -g borg   -m 700 /srv/borg
  install -d -o pgwal  -g pgwal  -m 750 /srv/pgwal
  install -d -o root   -g root   -m 755 /srv/pgbase
  echo "   comptes restic, borg, pgwal (sans mot de passe) et /srv/{restic,borg,pgwal,pgbase}"
  command -v rrsync >/dev/null && echo "   rrsync : $(command -v rrsync)" \
    || echo "   ATTENTION : rrsync introuvable (paquet rsync récent requis)"
  ;;
esac

# --- bilan ---------------------------------------------------------------------
echo
echo "== Prérequis =="
AV=0
avert() { printf '  [AVERT] %s\n' "$1"; AV=$((AV + 1)); }
ok()    { printf '  [ OK ] %s\n' "$1"; }
for h in lab-ops lab-db lab-web; do
  getent hosts "$h.lab.local" >/dev/null && ok "$h.lab.local se résout" \
    || avert "$h.lab.local ne se résout pas"
done
libre=$(df -Pm / | awk 'NR==2{print $4}')
[ "$libre" -ge 3000 ] && ok "espace libre sur / : $libre Mo" \
                      || avert "espace libre sur / : $libre Mo (3 Go conseillés)"
echo
[ "$AV" -eq 0 ] && echo "Prérequis réunis." || echo "$AV avertissement(s) à corriger."
