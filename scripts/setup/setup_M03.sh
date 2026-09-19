#!/usr/bin/env bash
# setup_M03.sh — prépare le terrain du module 03 (permissions, ACL, droits spéciaux)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab03"
WEB=/var/www/factura
SRV=/srv/factura
ETC=/etc/factura

echo "== Préparation du module 03 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 1. Groupes et compte de service
# ---------------------------------------------------------------------
groupadd -f facturation
groupadd -f webdev

# compte webdev : un "auditeur" / dev, membre de son propre groupe
if ! getent passwd webdev >/dev/null; then
  useradd -m -s /bin/bash -g webdev webdev
fi
# le compte de service facturation : sans shell de login
if ! getent passwd facturation >/dev/null; then
  useradd -r -s /usr/sbin/nologin -g facturation facturation
fi
# l'apprenant appartient au groupe facturation (partage de L3.1)
id -nG "$LAB_USER" | tr ' ' '\n' | grep -qx facturation || \
  usermod -aG facturation "$LAB_USER"
# www-data doit exister (nginx) ; sinon on le crée pour que le lab tienne
getent passwd www-data >/dev/null || useradd -r -s /usr/sbin/nologin www-data

# ---------------------------------------------------------------------
# 2. Bac à sable de l'apprenant ~/lab03
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,rapports,secrets,mixte,lecture,partage}

# mixte : des .sh et des .txt pour E3.3 (chmod récursif par type)
mkdir -p "$BASE/mixte"/{scripts,docs}
printf '#!/bin/sh\necho hello\n' > "$BASE/mixte/scripts/run.sh"
printf '#!/bin/sh\necho deploy\n' > "$BASE/mixte/scripts/deploy.sh"
printf 'notes de version\n'       > "$BASE/mixte/docs/CHANGELOG.txt"
printf 'guide utilisateur\n'      > "$BASE/mixte/docs/GUIDE.txt"
# on part d'un état sale : tout en 777, pour que E3.3 ait du sens
chmod -R 777 "$BASE/mixte"

# lecture : E3.4 (x sans r)
printf 'contenu connu\n' > "$BASE/lecture/connu.txt"
printf 'autre fichier\n' > "$BASE/lecture/autre.txt"
chmod 555 "$BASE/lecture"

# secrets : E3.15 (durcissement clé SSH)
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n(fictive)\n' \
  > "$BASE/secrets/id_ed25519"
printf 'Host lab-web\n  User mathieu\n' > "$BASE/secrets/config"
chmod 644 "$BASE/secrets" "$BASE/secrets/id_ed25519" "$BASE/secrets/config"

# fichiers pour chattr (E3.12, E3.13)
printf 'clé=valeur\n' > "$BASE/immuable.conf"
: > "$BASE/audit.log"

# ---------------------------------------------------------------------
# 3. Arborescence web servie par nginx (L3.1 web, BF3.1)
# ---------------------------------------------------------------------
mkdir -p "$WEB"/{css,img}
cat > "$WEB/index.html" <<'EOF'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>Factura</title><link rel="stylesheet" href="css/style.css"></head>
<body><h1>Factura — frontal</h1><p>Page servie par nginx.</p></body></html>
EOF
printf 'body{font-family:sans-serif}\n' > "$WEB/css/style.css"
printf 'page interne\n'                 > "$WEB/interne.html"
# état de départ propre : 755 répertoires, 644 fichiers, www-data
find "$WEB" -type d -exec chmod 755 {} +
find "$WEB" -type f -exec chmod 644 {} +
chown -R www-data:www-data "$WEB"

# configuration nginx minimale (si nginx est présent)
if command -v nginx >/dev/null 2>&1; then
  cat > /etc/nginx/sites-available/factura <<'EOF'
server {
    listen 80 default_server;
    root /var/www/factura;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
EOF
  ln -sf /etc/nginx/sites-available/factura \
        /etc/nginx/sites-enabled/factura
  rm -f /etc/nginx/sites-enabled/default
  if [ -d /run/systemd/system ]; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || \
      systemctl restart nginx 2>/dev/null || true
  fi
else
  echo "  note : nginx n'est pas installé (voir §3.1) — BF3.1 le suppose présent"
fi

# ---------------------------------------------------------------------
# 4. Conf, secrets et exports du service (L3.1, L3.2, D3)
# ---------------------------------------------------------------------
mkdir -p "$ETC/secrets" "$SRV"/{exports,incoming}

cat > "$ETC/factura.conf" <<'EOF'
# configuration factura
listen = 0.0.0.0:80
data_dir = /srv/factura
log_level = info
EOF
printf 'token=REMPLACER_EN_PROD\n' > "$ETC/secrets/api.token"
# état de départ VOLONTAIREMENT trop large (le Défi doit les resserrer)
chmod 644 "$ETC/factura.conf"
chmod 755 "$ETC/secrets"
chmod 644 "$ETC/secrets/api.token"
chown -R root:root "$ETC"

# exports : répertoire de groupe, mais SANS SGID ni ACL au départ (L3.1 à faire)
chgrp facturation "$SRV/exports" "$SRV/incoming"
chmod 770 "$SRV/exports" "$SRV/incoming"
printf 'id;client;montant\n1;ACME;1240.00\n' > "$SRV/exports/rapport.csv"
chown "$LAB_USER":facturation "$SRV/exports/rapport.csv"
chmod 640 "$SRV/exports/rapport.csv"

# ---------------------------------------------------------------------
# 5. Binaire SUID suspect (L3.3) et API à binder < 1024 (L3.4)
# ---------------------------------------------------------------------
cat > /usr/local/bin/factura-backup <<'EOF'
#!/usr/bin/env bash
# factura-backup — simulacre de sauvegarde. Appelle tar SANS chemin absolu :
# c'est précisément ce qui rend un SUID root exploitable (PATH hijacking).
tar -czf /tmp/factura-backup.tgz /srv/factura 2>/dev/null
echo "sauvegarde effectuée"
EOF
chmod 755 /usr/local/bin/factura-backup
chown root:root /usr/local/bin/factura-backup
# on pose le SUID root injustifié : c'est l'anomalie à trouver en L3.3
chmod u+s /usr/local/bin/factura-backup

# petite "API" qui tente de binder un port : réussit selon les privilèges.
# IMPORTANT : ce doit être un VRAI binaire (ELF), pas un script : les
# capabilities de fichier ne s'appliquent PAS à un script interprété
# (le noyau les évaluerait sur l'interpréteur, pas sur le script). On le
# compile donc en C ; setcap n'aurait aucun effet sur un .py ou un .sh.
SRC=$(mktemp --suffix=.c)
cat > "$SRC" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
int main(int argc, char **argv) {
    int port = 8080;
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "--port") && i + 1 < argc)
            port = atoi(argv[++i]);
    int s = socket(AF_INET, SOCK_STREAM, 0);
    int on = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = INADDR_ANY;
    a.sin_port = htons(port);
    if (bind(s, (struct sockaddr *)&a, sizeof(a)) < 0) {
        perror("bind");
        return 13;
    }
    listen(s, 1);
    printf("factura-api en écoute sur le port %d\n", port);
    fflush(stdout);
    pause();
    return 0;
}
EOF
if command -v gcc >/dev/null 2>&1; then
  gcc -O2 -o /usr/local/bin/factura-api "$SRC"
else
  # repli : binaire absent de compilateur, on pose un script qui explique.
  # (setcap n'y fonctionnera pas : installer gcc pour le lab L3.4)
  cat > /usr/local/bin/factura-api <<'EOF'
#!/bin/sh
echo "factura-api : gcc manquait au setup, recompile le binaire (voir §3.1)" >&2
exit 1
EOF
fi
rm -f "$SRC"
chmod 755 /usr/local/bin/factura-api
chown root:root /usr/local/bin/factura-api
# on retire toute capability résiduelle : L3.4 doit la poser lui-même
if command -v setcap >/dev/null 2>&1; then
  setcap -r /usr/local/bin/factura-api 2>/dev/null || true
fi

# ---------------------------------------------------------------------
# 6. Propriétaires finaux du bac à sable
# ---------------------------------------------------------------------
chown -R "$LAB_USER":"$LAB_USER" "$BASE"
# secrets et lecture gardent leurs modes volontairement "sales" pour les exos
chmod 644 "$BASE/secrets/id_ed25519" 2>/dev/null || true

# avertissement si un outil manque
for p in getfacl setfacl chattr lsattr getcap setcap namei; do
  command -v "$p" >/dev/null 2>&1 || \
    echo "  note : $p n'est pas installé (voir §3.1)"
done

cat <<EOF

Prêt. Points d'entrée :
  $BASE/mixte           arbo .sh/.txt en 777 à normaliser (E3.3)
  $BASE/lecture         répertoire pour x-sans-r (E3.4)
  $BASE/secrets         clé fictive à durcir (E3.15)
  $BASE/immuable.conf   pour chattr +i (E3.12)
  $WEB                  racine nginx servie (BF3.1)
  $SRV/exports          dépôt de groupe à équiper de SGID+ACL (L3.1, BF3.2)
  $ETC                  conf + secrets trop larges à resserrer (D3)
  /usr/local/bin/factura-backup   SUID root suspect (L3.3)
  /usr/local/bin/factura-api      API à faire binder le port 80 (L3.4)
EOF
