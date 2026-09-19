#!/usr/bin/env bash
# setup_M06.sh — prépare le terrain du module 06
#   (vim, archives tar, compression, rsync, transfert)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab06"
ED="$BASE/edition"
SRC="$BASE/arbo/factura"
ETC=/etc/factura

echo "== Préparation du module 06 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# On repart d'un état connu pour les deux zones que les exercices abîment :
# les fichiers à éditer et l'arborescence source. Les répertoires de travail
# (archives, sauvegardes, restauration) sont conservés : le défi y livre.
rm -rf "$ED" "$BASE/arbo"
mkdir -p "$ED" "$SRC" "$BASE/archives" "$BASE/depot" \
         "$BASE/restauration" "$BASE/backup"

# =====================================================================
# 1. Fichiers à éditer sous vim  (~/lab06/edition)
# =====================================================================

# --- 1.1 notes.txt : 120 lignes numérotées (déplacements, marques) ----
{
  echo "# Journal d'exploitation — plateforme Factura"
  echo "# Une ligne par événement. Ne pas réordonner."
  for i in $(seq 3 120); do
    printf 'ligne %03d — evenement routine sur lab-web, rien a signaler\n' "$i"
  done
} > "$ED/notes.txt"
# quelques ancres repérables pour les exercices de recherche
sed -i '42s/.*/ligne 042 — INCIDENT INC-4471 bascule du frontal/' \
  "$ED/notes.txt"
sed -i '87s/.*/ligne 087 — INCIDENT INC-4488 saturation du disque/' \
  "$ED/notes.txt"
sed -i '113s/.*/ligne 113 — INCIDENT INC-4501 certificat expire/' \
  "$ED/notes.txt"

# --- 1.2 factura.conf : vhost à retravailler (visuel bloc, ci", :%s) --
cat > "$ED/factura.conf" <<'EOF'
# vhost factura — repris tel quel de l'ancien serveur
# NE PAS RECHARGER NGINX AVANT RELECTURE

upstream factura_app {
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
}


server {
    listen 80;
    server_name "ancien-frontal.example.org";

    root /opt/factura/public;
    index index.html;

    access_log /opt/factura/logs/access.log;
    error_log  /opt/factura/logs/error.log;

    location / {
        try_files $uri $uri/ @app;
    }

    location @app {
        proxy_pass http://factura_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /static/ {
        alias /opt/factura/public/static/;
        expires 7d;
    }
}



# --- bloc hérité de la plateforme 2019, plus servi ---
server {
    listen 8081;
    server_name legacy.example.org;
    root /opt/legacy/public;
    index index.php;
    access_log /opt/legacy/logs/access.log;
    error_log  /opt/legacy/logs/error.log;
    client_max_body_size 64m;
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
    location /admin-2019/ {
        allow 10.10.10.0/24;
        deny all;
    }
    location /exports/ {
        alias /opt/legacy/exports/;
        autoindex on;
    }
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

# --- 1.3 app.log : journal bruité (:g, :v, :sort) --------------------
{
  for i in $(seq 1 60); do
    printf '2026-09-17T04:%02d:11 DEBUG worker=%d cache hit key=u%03d\n' \
      "$((i % 60))" "$((i % 4))" "$i"
    if [ $((i % 7)) -eq 0 ]; then
      printf '2026-09-17T04:%02d:12 ERROR worker=%d db timeout after 5000ms\n' \
        "$((i % 60))" "$((i % 4))"
    fi
    if [ $((i % 5)) -eq 0 ]; then
      printf '2026-09-17T04:%02d:13 WARN  worker=%d pool 90%% utilise\n' \
        "$((i % 60))" "$((i % 4))"
    fi
    printf '2026-09-17T04:%02d:14 INFO  worker=%d requete traitee en %dms\n' \
      "$((i % 60))" "$((i % 4))" "$((20 + i))"
  done
  # doublons stricts : le tri-dédoublonnage de L6.2 doit avoir du grain
  for _ in 1 2 3 4 5; do
    printf '2026-09-17T04:07:12 ERROR worker=3 db timeout after 5000ms\n'
  done
} > "$ED/app.log"

# --- 1.4 inventaire.csv : colonnes à compléter (visuel bloc, :g) -----
{
  echo "hote;role;ip"
  echo "lab-adm;bastion;10.10.10.10"
  echo "lab-web;frontal;10.10.10.11"
  echo "lab-db;base;10.10.10.12"
  echo "lab-rhel;rhel;10.10.10.13"
  echo "lab-ops;ci;10.10.10.14"
  for i in $(seq 1 24); do
    printf 'app-%02d;worker;10.10.20.%d\n' "$i" "$((100 + i))"
  done
} > "$ED/inventaire.csv"

# --- 1.5 deploy.sh : chemins à migrer (:%s avec plages) --------------
cat > "$ED/deploy.sh" <<'EOF'
#!/usr/bin/env bash
# deploy.sh — déploiement factura (version historique, chemins /opt)
set -euo pipefail

APP_DIR=/opt/factura
CONF_DIR=/opt/factura/conf
LOG_DIR=/opt/factura/logs
RELEASE="$1"

echo "déploiement de $RELEASE dans /opt/factura"

# --- commentaire : ne pas modifier les chemins ci-dessous en phase 1 ---
# historique : /opt/factura était monté sur un NFS jusqu'en 2024
# la migration vers /srv/factura est planifiée mais pas faite
# ---------------------------------------------------------------------

mkdir -p "$APP_DIR/releases/$RELEASE"
tar -xzf "/opt/factura/livraisons/$RELEASE.tar.gz" \
    -C "$APP_DIR/releases/$RELEASE"

ln -sfn "$APP_DIR/releases/$RELEASE" /opt/factura/current
cp "$CONF_DIR/factura.conf" "$APP_DIR/current/conf/factura.conf"

echo "redemarrage"
systemctl restart factura.service
echo "log : $LOG_DIR/deploy.log"
EOF
chmod 755 "$ED/deploy.sh"

# --- 1.6 snippet.yaml : bloc indenté pour l'exercice de collage ------
cat > "$ED/snippet.yaml" <<'EOF'
services:
  factura:
    image: registry.lab.local/factura:1.4.2
    environment:
      - APP_ENV=production
      - DB_HOST=10.10.10.12
    volumes:
      - /srv/factura/conf:/app/conf:ro
    deploy:
      resources:
        limits:
          memory: 512M
EOF

# --- 1.7 fichier de conf root : cible de  :w !sudo tee %  ------------
mkdir -p "$ETC"
cat > "$ETC/frontal.conf" <<'EOF'
# /etc/factura/frontal.conf — propriété de root, 644
listen = 0.0.0.0:8080
data_dir = /srv/factura
log_level = info
workers = 2
EOF
chown root:root "$ETC/frontal.conf"
chmod 644 "$ETC/frontal.conf"

# =====================================================================
# 2. Arborescence à archiver  (~/lab06/arbo/factura)
# =====================================================================
mkdir -p "$SRC"/{app/{src,tests},conf/secrets,logs,uploads,var/cache} \
         "$SRC/node_modules"

for i in $(seq 1 30); do
  printf 'def handler_%02d(req):\n    return {"ok": True, "id": %d}\n' \
    "$i" "$i" > "$SRC/app/src/mod_$(printf '%02d' "$i").py"
done
for i in $(seq 1 10); do
  printf 'def test_%02d():\n    assert True\n' "$i" \
    > "$SRC/app/tests/test_$(printf '%02d' "$i").py"
done

cat > "$SRC/conf/factura.conf" <<'EOF'
listen = 0.0.0.0:8080
data_dir = /srv/factura
log_level = info
EOF
printf 'token=8f3c9a1e-prod-ne-pas-diffuser\n' \
  > "$SRC/conf/secrets/api.token"
# root:<groupe du lab> 640 : lisible par l'apprenant (donc archivable sans
# sudo), mais dont le PROPRIÉTAIRE root ne pourra être restitué qu'en root.
chown root:"$LAB_USER" "$SRC/conf/secrets/api.token"
chmod 640 "$SRC/conf/secrets/api.token"

# journaux : du volume compressible, pour comparer les compresseurs
CHUNK=$(mktemp)
for f in access error applicatif; do
  for i in $(seq 1 2000); do
    printf '2026-09-17 04:00:%02d factura %s message repetitif numero %d\n' \
      "$((i % 60))" "$f" "$i"
  done > "$CHUNK"
  : > "$SRC/logs/$f.log"
  for _ in $(seq 1 10); do cat "$CHUNK" >> "$SRC/logs/$f.log"; done
done
rm -f "$CHUNK"

# node_modules et var/cache : le bruit qu'on exclut des archives
for i in $(seq 1 60); do
  d="$SRC/node_modules/paquet-$(printf '%02d' "$i")"
  mkdir -p "$d"
  printf '{"name":"paquet-%02d","version":"1.0.%d"}\n' "$i" "$i" \
    > "$d/package.json"
  head -c 4096 /dev/urandom > "$d/index.min.js"
done
for i in $(seq 1 40); do
  head -c 8192 /dev/urandom > "$SRC/var/cache/frag-$i.bin"
done

# uploads : binaires incompressibles + un lien symbolique (piège de tar -h)
for i in $(seq 1 5); do
  head -c 1048576 /dev/urandom > "$SRC/uploads/piece-$i.bin"
done
ln -sfn ../conf/factura.conf "$SRC/uploads/conf-courante.conf"

# =====================================================================
# 3. Archive de référence + variante corrompue (intégrité)
# =====================================================================
ARCH="$BASE/archives"
tar -czf "$ARCH/livraison-2026-09-12.tar.gz" \
    -C "$BASE/arbo" factura/app factura/conf factura/uploads
( cd "$ARCH" && sha256sum livraison-2026-09-12.tar.gz \
    > livraison-2026-09-12.tar.gz.sha256 )
# copie tronquée : gzip -t doit hurler, la somme doit diverger
cp "$ARCH/livraison-2026-09-12.tar.gz" "$ARCH/livraison-recue.tar.gz"
SZ=$(stat -c %s "$ARCH/livraison-recue.tar.gz")
truncate -s $((SZ - 4096)) "$ARCH/livraison-recue.tar.gz"
cp "$ARCH/livraison-2026-09-12.tar.gz.sha256" \
   "$ARCH/livraison-recue.tar.gz.sha256"
sed -i 's/livraison-2026-09-12.tar.gz/livraison-recue.tar.gz/' \
  "$ARCH/livraison-recue.tar.gz.sha256"

# =====================================================================
# 4. Propriétaires
# =====================================================================
chown -R "$LAB_USER":"$LAB_USER" "$BASE"
# on repose le secret en root : il fait partie de l'exercice (tar -p)
chown root:"$LAB_USER" "$SRC/conf/secrets/api.token"
chmod 640 "$SRC/conf/secrets/api.token"
chmod 750 "$SRC/conf/secrets"
chown "$LAB_USER":"$LAB_USER" "$SRC/conf/secrets"

# =====================================================================
# 5. Outils manquants
# =====================================================================
for p in vim tar gzip bzip2 xz zstd zip unzip cpio rsync split \
         sha256sum ssh; do
  command -v "$p" >/dev/null 2>&1 || \
    echo "  note : $p n'est pas installé (voir §6.1)"
done

cat <<EOF

Prêt. Points d'entrée :
  $ED/notes.txt         120 lignes (déplacements, marques)
  $ED/factura.conf      vhost à retravailler (visuel bloc, :%s)
  $ED/app.log           journal bruité (:g, :v)
  $ED/inventaire.csv    colonnes à compléter
  $ED/deploy.sh         chemins /opt à migrer vers /srv
  $ED/snippet.yaml      bloc indenté pour le collage
  $ETC/frontal.conf     appartient à root (:w !sudo tee %)
  $SRC                  arborescence à archiver
  $ARCH                 archive de référence + copie tronquée
  $BASE/depot           destination rsync locale
  $BASE/backup          racine des sauvegardes --link-dest
  $BASE/restauration    bac à sable de restauration
EOF
