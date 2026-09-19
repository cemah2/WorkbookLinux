#!/usr/bin/env bash
# setup_M18.sh — prépare le terrain du module 18 (sécurité, durcissement)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
#
# Ce script NE configure AUCUN pare-feu, N'active AUCUNE jail fail2ban et
# NE touche PAS au mode SELinux : tout cela est le travail du module.
# Il fournit la matière : journaux d'attaque, base de référence SUID,
# contenu web, dossier d'incident à analyser, arborescence de PKI.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab18"
. /etc/os-release
case "$ID" in
  ubuntu|debian)              FAMILLE=deb ;;
  rocky|rhel|centos|almalinux) FAMILLE=rpm ;;
  *)                          FAMILLE=inconnu ;;
esac

echo "== Préparation du module 18 =="
echo "   utilisateur  : $LAB_USER"
echo "   distribution : $PRETTY_NAME ($FAMILLE)"
echo "   base         : $BASE"

mkdir -p "$BASE"/{logs,pki,bin,backup,incident}

# ---------------------------------------------------------------------
# 1. Journal d'authentification d'attaque  (E18.11)
# ---------------------------------------------------------------------
AUTHLOG="$BASE/logs/auth-attaque.log"
if [ ! -s "$AUTHLOG" ]; then
  {
    h=1; p=2000
    for ip in 203.0.113.44 198.51.100.7 192.0.2.19 203.0.113.91; do
      for u in root admin oracle postgres ubuntu test git jenkins; do
        for n in 1 2 3 4; do
          printf 'Sep 17 %02d:%02d:%02d lab-web sshd[%d]: Failed password'\
' for invalid user %s from %s port %d ssh2\n' \
            $(( h % 24 )) $(( (n * 7 + h) % 60 )) $(( (n * 13) % 60 )) \
            $p "$u" "$ip" $(( 40000 + p % 20000 ))
          p=$(( p + 1 ))
        done
        h=$(( h + 1 ))
      done
    done
    for n in 1 2 3 4; do
      printf 'Sep 17 04:%02d:%02d lab-web sshd[%d]: Failed password for'\
' mathieu from 203.0.113.44 port %d ssh2\n' \
        $(( n * 3 )) $(( n * 11 )) $(( p + n )) $(( 51000 + n ))
    done
    for n in 1 2 3 4 5 6 7 8 9 10; do
      printf 'Sep 17 %02d:%02d:01 lab-web sshd[%d]: Accepted publickey'\
' for mathieu from 10.10.10.10 port %d ssh2: RSA SHA256:8f2Jd0\n' \
        $(( 7 + n )) $(( n * 5 )) $(( 3000 + n )) $(( 52000 + n ))
      printf 'Sep 17 %02d:%02d:02 lab-web sshd[%d]: pam_unix(sshd:session):'\
' session opened for user mathieu(uid=1000) by (uid=0)\n' \
        $(( 7 + n )) $(( n * 5 )) $(( 3000 + n ))
      printf 'Sep 17 %02d:%02d:59 lab-web CRON[%d]: pam_unix(cron:session):'\
' session closed for user root\n' \
        $(( 7 + n )) $(( n * 5 )) $(( 3100 + n ))
    done
  } | sort -k1,3 > "$AUTHLOG"
  chown "$LAB_USER": "$AUTHLOG"
  echo "   journal SSH d'attaque : $AUTHLOG ($(wc -l < "$AUTHLOG") lignes)"
fi

# ---------------------------------------------------------------------
# 2. Journal nginx de scan  (L18.2)
# ---------------------------------------------------------------------
SCANLOG="$BASE/logs/acces-scan.log"
if [ ! -s "$SCANLOG" ]; then
  {
    m=0
    for ip in 203.0.113.44 198.51.100.7 192.0.2.19; do
      for chemin in /wp-login.php /.env /admin.php /phpmyadmin/index.php \
                    /.git/config /wp-admin/ /vendor/phpunit/phpunit.xml \
                    /config.json; do
        for n in 1 2 3 4; do
          case "$chemin" in
            /wp-admin/|/vendor/*|/config.json) code=404; meth=GET ;;
            /.git/config) code=403; meth=GET ;;
            /phpmyadmin/*) code=404; meth=POST ;;
            *) code=404; meth=GET ;;
          esac
          printf '%s - - [17/Sep/2026:%02d:%02d:%02d +0200] "%s %s'\
' HTTP/1.1" %d 162 "-" "Mozilla/5.0 (compatible; scanbot/1.0)"\n' \
            "$ip" $(( (m / 60) % 24 )) $(( m % 60 )) $(( (m * 7) % 60 )) \
            "$meth" "$chemin" "$code"
          m=$(( m + 1 ))
        done
      done
    done
    for n in $(seq 1 48); do
      printf '10.10.10.10 - - [17/Sep/2026:%02d:%02d:%02d +0200] "GET'\
' /index.html HTTP/1.1" 200 1024 "-" "curl/8.5.0"\n' \
        $(( n % 24 )) $(( (n * 3) % 60 )) $(( (n * 11) % 60 ))
      printf '10.10.10.14 - - [17/Sep/2026:%02d:%02d:%02d +0200] "GET'\
' /sante HTTP/1.1" 200 12 "-" "Prometheus/2.51"\n' \
        $(( n % 24 )) $(( (n * 5) % 60 )) $(( (n * 13) % 60 ))
    done
  } > "$SCANLOG"
  chown "$LAB_USER": "$SCANLOG"
  echo "   journal nginx de scan : $SCANLOG ($(wc -l < "$SCANLOG") lignes)"
fi

# ---------------------------------------------------------------------
# 3. Base de référence SUID/SGID  (L18.5, D18, QO18.9)
# ---------------------------------------------------------------------
BASELINE="$BASE/baseline-suid.txt"
if [ ! -s "$BASELINE" ]; then
  find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null \
    | sort > "$BASELINE"
  chown "$LAB_USER": "$BASELINE"
  echo "   base SUID/SGID        : $BASELINE \
($(wc -l < "$BASELINE") binaires)"
fi

# ---------------------------------------------------------------------
# 4. Contenu web à servir  (L18.3, L18.4, BF18.2, BF18.3)
# ---------------------------------------------------------------------
if [ "$FAMILLE" = rpm ]; then DOCROOT=/usr/share/nginx/html
else DOCROOT=/var/www/html; fi
mkdir -p "$DOCROOT"
[ -f "$DOCROOT/index.html" ] || cat > "$DOCROOT/index.html" <<'EOF'
<!doctype html><html lang="fr"><meta charset="utf-8">
<title>Application du lab</title>
<h1>Application du lab — module 18</h1>
<p>Si tu lis ceci en HTTPS avec un cadenas valide, L18.4 est bouclé.</p>
EOF
[ -f "$DOCROOT/sante" ] || echo 'ok' > "$DOCROOT/sante"
echo "   racine web            : $DOCROOT"

# ---------------------------------------------------------------------
# 5. Secrets mal rangés, à corriger  (L18.5, D18)
# ---------------------------------------------------------------------
mkdir -p /opt/labsec
if [ ! -f /opt/labsec/.env ]; then
  cat > /opt/labsec/.env <<'EOF'
# Fichier d'environnement de l'application de démonstration.
# Les droits de ce fichier sont volontairement mauvais : c'est un
# exercice. Le mot de passe ci-dessous est bidon.
APP_ENV=production
DB_HOST=10.10.10.12
DB_USER=factura
DB_PASSWORD=Ch4ngeM01-EnProd
API_TOKEN=lab18-jeton-de-demonstration-sans-valeur
EOF
  chmod 0644 /opt/labsec/.env          # 0644 : c'est le problème à voir
fi

# ---------------------------------------------------------------------
# 6. Dossier d'incident à analyser  (QO18.9)
#    Ce sont des COPIES de sorties, aucune machine n'est compromise.
# ---------------------------------------------------------------------
INC="$BASE/incident"
if [ ! -s "$INC/ps-aux.txt" ]; then
  cat > "$INC/ps-aux.txt" <<'EOF'
USER   PID %CPU %MEM    VSZ   RSS TTY  STAT START   TIME COMMAND
root     1  0.0  0.4 168300 12040 ?    Ss   Sep15   0:21 /sbin/init
postgres 918 0.0 2.1 220100 43120 ?    Ss   Sep15   0:44 postgres: main
postgres 2481 12.3 0.3  22140  6280 ?  Ssl  03:12   6:02 [kworker/u8:2]
www-data 1204 0.0 0.8  59200 16400 ?   S    Sep16   0:03 nginx: worker
EOF
  cat > "$INC/proc-2481.txt" <<'EOF'
# ls -l /proc/2481/
lrwxrwxrwx 1 root root 0 Sep 18 03:12 cwd -> /tmp
lrwxrwxrwx 1 root root 0 Sep 18 03:12 exe -> /tmp/.x (deleted)
-r--r--r-- 1 root root 0 Sep 18 03:12 cmdline
# tr '\0' ' ' < /proc/2481/cmdline
[kworker/u8:2]
# ss -tunp | grep 2481
tcp ESTAB 0 0 10.10.10.12:44112 198.51.100.7:443 users:(("x",pid=2481))
EOF
  cat > "$INC/auth-extrait.log" <<'EOF'
Sep 18 03:11:47 lab-db sshd[2470]: Accepted password for postgres from
 198.51.100.7 port 51188 ssh2
Sep 18 03:11:47 lab-db sshd[2470]: pam_unix(sshd:session): session opened
 for user postgres(uid=114) by (uid=0)
Sep 18 03:12:03 lab-db sudo:  postgres : TTY=pts/1 ; PWD=/tmp ;
 USER=root ; COMMAND=/usr/bin/crontab -e
Sep 18 03:12:58 lab-db useradd[2495]: new user: name=svc-backup, UID=0,
 GID=0, home=/var/tmp/.svc, shell=/bin/bash
EOF
  cat > "$INC/README.md" <<'EOF'
# Dossier d'incident — matière pour QO18.9

Ces fichiers sont des copies de sorties prélevées sur une machine
(fictive) suspectée de compromission. Aucune machine du lab n'est
réellement touchée.

À toi de dire : quels sont les signaux, dans quel ordre tu les traites,
ce que tu préserves avant d'agir, et ce que tu conclus sur la
persistance mise en place par l'attaquant.
EOF
  chown -R "$LAB_USER": "$INC"
  echo "   dossier d'incident    : $INC"
fi

# ---------------------------------------------------------------------
# 7. Répertoire de la PKI et hôte applicatif
# ---------------------------------------------------------------------
chmod 0700 "$BASE/pki"
grep -q 'app.lab.local' /etc/hosts || \
  echo '10.10.10.11 app.lab.local lab-web.lab.local' >> /etc/hosts

chown -R "$LAB_USER": "$BASE"

# ---------------------------------------------------------------------
# 8. Contrôles de présence des outils (informatif, non bloquant)
# ---------------------------------------------------------------------
manquants=""
for outil in openssl nft ss find awk; do
  command -v "$outil" >/dev/null 2>&1 || manquants="$manquants $outil"
done
if [ "$FAMILLE" = deb ]; then
  for outil in ufw fail2ban-client aa-status; do
    command -v "$outil" >/dev/null 2>&1 || manquants="$manquants $outil"
  done
else
  for outil in firewall-cmd semanage getenforce; do
    command -v "$outil" >/dev/null 2>&1 || manquants="$manquants $outil"
  done
fi
[ -z "$manquants" ] || {
  echo
  echo "   ATTENTION — outils absents :$manquants"
  echo "   (voir la liste de paquets du §18.1)"; }

echo
echo "Terrain prêt. Aucun pare-feu activé, aucune jail créée :"
echo "c'est le travail du module."
