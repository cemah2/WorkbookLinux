#!/usr/bin/env bash
# setup_M33.sh — prépare le terrain du module 33 (compilation, paquets, dépôts)
# À lancer avec sudo sur lab-adm, lab-rhel et lab-web. Idempotent.
#
# lab-adm, lab-rhel : archives « amont » de lab33-sante 1.0 et 1.1, squelette
#                     du module noyau du défi, dans ~/lab33/amont/.
# lab-web           : compte « depot », /srv/depot, site nginx sur le port 8033.
# Ne construit AUCUN paquet et ne crée AUCUNE clé : c'est le travail du module.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

role=inconnu
for a in $(hostname -I); do
  case "$a" in
    10.10.10.10) role=adm ;;
    10.10.10.11) role=web ;;
    10.10.10.13) role=rhel ;;
  esac
done
echo "== Préparation du module 33 =="
echo "   machine : $(hostname -s), rôle : $role"
[ "$role" != inconnu ] || { echo "   pas une VM du module 33 (lab-adm, lab-rhel, lab-web)" >&2; exit 1; }

# =============================================================================
# Arborescence amont de lab33-sante, pour une version donnée
# =============================================================================
amont() {   # amont <version> <répertoire de sortie>
  local v=$1 d=$2/lab33-sante-$1
  rm -rf "$d"; mkdir -p "$d/src" "$d/systemd"

  cat > "$d/Makefile" <<EOF
# lab33-sante — Makefile amont
VERSION    = $v
PREFIX    ?= /usr/local
BINDIR    ?= \$(PREFIX)/bin
MANDIR    ?= \$(PREFIX)/share/man
ifeq (\$(PREFIX),/usr)
SYSCONFDIR ?= /etc
else
SYSCONFDIR ?= \$(PREFIX)/etc
endif
UNITDIR    ?= \$(PREFIX)/lib/systemd/system
SYSUSERSDIR ?= \$(PREFIX)/lib/sysusers.d
CFLAGS    ?= -O2 -g -Wall
CPPFLAGS  += -DVERSION=\\"\$(VERSION)\\" -DCONFIG=\\"\$(SYSCONFDIR)/lab33-sante.conf\\"

all: lab33-sante systemd/lab33-sante.service

lab33-sante: src/lab33-sante.c
	\$(CC) \$(CPPFLAGS) \$(CFLAGS) \$(LDFLAGS) -o \$@ \$<

systemd/lab33-sante.service: systemd/lab33-sante.service.in
	sed 's|@BINDIR@|\$(BINDIR)|g' \$< > \$@

check: lab33-sante
	./lab33-sante --version
	printf 'ferme 127.0.0.1 1\n' > test.conf
	! ./lab33-sante -c test.conf > /dev/null
	rm -f test.conf

install: all
	install -D -m 0755 lab33-sante \$(DESTDIR)\$(BINDIR)/lab33-sante
	install -D -m 0644 lab33-sante.conf \$(DESTDIR)\$(SYSCONFDIR)/lab33-sante.conf
	install -D -m 0644 lab33-sante.1 \$(DESTDIR)\$(MANDIR)/man1/lab33-sante.1
	install -D -m 0644 systemd/lab33-sante.service \$(DESTDIR)\$(UNITDIR)/lab33-sante.service
	install -D -m 0644 systemd/lab33-sante.timer \$(DESTDIR)\$(UNITDIR)/lab33-sante.timer
	install -D -m 0644 systemd/lab33-sante.sysusers \$(DESTDIR)\$(SYSUSERSDIR)/lab33-sante.conf

clean:
	rm -f lab33-sante systemd/lab33-sante.service test.conf

.PHONY: all check install clean
EOF

  cat > "$d/src/lab33-sante.c" <<'C'
/* lab33-sante — vérifie que des services TCP répondent.
 * Configuration : une ligne « nom hôte port » par service. */
#include <errno.h>
#include <netdb.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef VERSION
#define VERSION "dev"
#endif
#ifndef CONFIG
#define CONFIG "/etc/lab33-sante.conf"
#endif

static int teste(const char *hote, const char *port, int delai_ms, char *raison, size_t n)
{
    struct addrinfo indices = { 0 }, *res, *a;
    indices.ai_socktype = SOCK_STREAM;
    int e = getaddrinfo(hote, port, &indices, &res);
    if (e) {
        snprintf(raison, n, "%s", gai_strerror(e));
        return -1;
    }
    int ok = -1;
    for (a = res; a && ok; a = a->ai_next) {
        int s = socket(a->ai_family, a->ai_socktype | SOCK_NONBLOCK, a->ai_protocol);
        if (s < 0)
            continue;
        if (connect(s, a->ai_addr, a->ai_addrlen) == 0) {
            ok = 0;
        } else if (errno == EINPROGRESS) {
            struct pollfd p = { .fd = s, .events = POLLOUT };
            if (poll(&p, 1, delai_ms) == 1) {
                int err = 0;
                socklen_t l = sizeof err;
                getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &l);
                if (err == 0)
                    ok = 0;
                else
                    snprintf(raison, n, "%s", strerror(err));
            } else {
                snprintf(raison, n, "délai dépassé");
            }
        } else {
            snprintf(raison, n, "%s", strerror(errno));
        }
        close(s);
    }
    freeaddrinfo(res);
    return ok;
}

int main(int argc, char **argv)
{
    const char *conf = CONFIG;
    int json = 0, delai = 2000;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--version")) {
            printf("lab33-sante %s\n", VERSION);
            return 0;
        } else if (!strcmp(argv[i], "-c") && i + 1 < argc) {
            conf = argv[++i];
#ifdef AVEC_JSON
        } else if (!strcmp(argv[i], "--json")) {
            json = 1;
#endif
        } else {
            fprintf(stderr, "usage : lab33-sante [-c fichier] [--version]\n");
            return 2;
        }
    }
    FILE *f = fopen(conf, "r");
    if (!f) {
        perror(conf);
        return 2;
    }
    char ligne[512], nom[128], hote[256], port[16];
    int ko = 0, total = 0;
    if (json)
        printf("[");
    while (fgets(ligne, sizeof ligne, f)) {
        if (ligne[0] == '#' || ligne[0] == '\n')
            continue;
        if (sscanf(ligne, "delai_ms %d", &delai) == 1)
            continue;
        if (sscanf(ligne, "%127s %255s %15s", nom, hote, port) != 3)
            continue;
        char raison[128] = "";
        int r = teste(hote, port, delai, raison, sizeof raison);
        if (json)
            printf("%s{\"nom\":\"%s\",\"ok\":%s}", total ? "," : "", nom, r == 0 ? "true" : "false");
        else if (r == 0)
            printf("OK %s (%s:%s)\n", nom, hote, port);
        else
            printf("KO %s (%s:%s) : %s\n", nom, hote, port, raison);
        total++;
        ko += r != 0;
    }
    fclose(f);
    if (json)
        printf("]\n");
    else
        printf("%d/%d services joignables\n", total - ko, total);
    return ko ? 1 : 0;
}
C
  # la 1.1 active la sortie JSON
  [ "$v" = 1.0 ] || sed -i 's|^#ifdef AVEC_JSON|#if 1 /* depuis 1.1 */|' "$d/src/lab33-sante.c"

  cat > "$d/lab33-sante.conf" <<'EOF'
# /etc/lab33-sante.conf — services à vérifier, une ligne « nom hôte port »
web   lab-web.lab.local  80
base  lab-db.lab.local   5432
EOF
  [ "$v" = 1.0 ] || cat >> "$d/lab33-sante.conf" <<'EOF'

# délai de connexion en millisecondes (défaut : 2000), depuis la 1.1
# delai_ms 2000
EOF

  cat > "$d/systemd/lab33-sante.service.in" <<'EOF'
[Unit]
Description=lab33-sante : vérification des services TCP
Documentation=man:lab33-sante(1)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=lab33
ExecStart=@BINDIR@/lab33-sante
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
EOF
  cat > "$d/systemd/lab33-sante.timer" <<'EOF'
[Unit]
Description=lab33-sante toutes les 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
  echo 'u lab33 - "lab33-sante" /nonexistent /usr/sbin/nologin' > "$d/systemd/lab33-sante.sysusers"

  cat > "$d/lab33-sante.1" <<EOF
.TH LAB33-SANTE 1 "2026" "lab33-sante $v" "Commandes"
.SH NOM
lab33-sante \- vérifie que des services TCP répondent
.SH SYNOPSIS
.B lab33-sante
[\fB\-c\fR \fIfichier\fR] [\fB\-\-version\fR]
.SH DESCRIPTION
Lit une liste de services (\fInom hôte port\fR) et tente une connexion TCP
vers chacun. Le code de retour vaut 0 si tous répondent, 1 sinon.
.SH FICHIERS
.I /etc/lab33-sante.conf
EOF
  printf 'lab33-sante %s\n\n* %s\n' "$v" \
    "$([ "$v" = 1.0 ] && echo 'Première version.' || echo 'Sortie --json, directive delai_ms.')" \
    > "$d/CHANGELOG"
  cat > "$d/LICENSE" <<'EOF'
MIT License — Copyright (c) 2026 Workbook Linux
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software, to deal in the Software without restriction. THE SOFTWARE IS
PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
EOF
  echo "lab33-sante $v — vérifie que des services TCP répondent. make && make install." > "$d/README"

  # archive reproductible
  tar --sort=name --mtime='2026-01-01 00:00Z' --owner=0 --group=0 --numeric-owner \
      -C "$2" -czf "$2/lab33-sante-$v.tar.gz" "lab33-sante-$v"
  rm -rf "$d"
}

squelette_module() {   # squelette du module noyau du défi
  local d=$1/lab33-compteur
  mkdir -p "$d"
  cat > "$d/lab33_compteur.c" <<'C'
// lab33_compteur — /proc/lab33_compteur renvoie le nombre de lectures (module 33, D33)
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

/* TODO : un compteur atomique, une fonction d'affichage (seq_file),
 *        des proc_ops, la création de l'entrée au chargement et sa
 *        suppression au déchargement. */

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Compteur de lectures de /proc/lab33_compteur");
MODULE_VERSION("1.0");
C
  cat > "$d/Makefile" <<'EOF'
obj-m := lab33_compteur.o
KVER  ?= $(shell uname -r)
KDIR  ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
EOF
}

case "$role" in
  adm|rhel)
    A="$LAB_HOME/lab33/amont"
    install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$LAB_HOME/lab33" "$A" "$LAB_HOME/lab33/defi"
    for v in 1.0 1.1; do
      [ -s "$A/lab33-sante-$v.tar.gz" ] || amont "$v" "$A"
    done
    [ "$role" = adm ] && [ ! -d "$A/lab33-compteur" ] && squelette_module "$A"
    chown -R "$LAB_USER": "$LAB_HOME/lab33"
    echo "   archives amont : $(cd "$A" && ls lab33-sante-*.tar.gz | paste -sd' ' -)"
    ;;
  web)
    if ! id depot >/dev/null 2>&1; then
      useradd --create-home --shell /bin/bash depot && passwd -l depot >/dev/null
    fi
    install -d -o depot -g depot -m 755 /srv/depot
    install -d -o depot -g depot -m 700 /home/depot/.ssh
    command -v nginx >/dev/null || { echo "nginx absent (module 15)" >&2; exit 1; }
    cat > /etc/nginx/sites-available/depot-lab33 <<'EOF'
# Dépôts apt et dnf du module 33 : fichiers statiques déjà signés
server {
    listen 8033;
    server_name lab-web.lab.local;
    root /srv/depot;
    autoindex on;
    location ~ /\. { deny all; }
}
EOF
    ln -sf ../sites-available/depot-lab33 /etc/nginx/sites-enabled/depot-lab33
    nginx -t -q && systemctl reload nginx
    if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
      ufw allow from 10.10.10.0/24 to any port 8033 proto tcp comment 'depot lab33' >/dev/null
    fi
    echo "   /srv/depot (compte depot), nginx sur le port 8033"
    ;;
esac

echo
echo "== Prérequis =="
case "$role" in
  adm)  for c in dpkg-buildpackage lintian reprepro createrepo_c rpmsign gpg dkms; do
          command -v "$c" >/dev/null && echo "  [ OK ] $c" || echo "  [AVERT] $c absent (voir 33.1)"; done ;;
  rhel) for c in rpmbuild rpmdev-setuptree rpmlint gcc; do
          command -v "$c" >/dev/null && echo "  [ OK ] $c" || echo "  [AVERT] $c absent (voir 33.1)"; done ;;
  web)  curl -fsS -o /dev/null http://127.0.0.1:8033/ && echo "  [ OK ] nginx répond sur 8033" \
          || echo "  [AVERT] nginx ne répond pas sur 8033" ;;
esac
