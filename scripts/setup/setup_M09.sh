#!/usr/bin/env bash
# setup_M09.sh — prépare le terrain du module 09
#                (paquets, dépôts, clés, épinglage, compilation)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
#
# Ce script NE configure AUCUN dépôt dans /etc/apt ni /etc/yum.repos.d :
# écrire le fichier de source, importer la clé et régler l'épinglage sont
# le travail du module. Il fabrique seulement la matière première :
#
#   * une paire de clés GPG « Depot Lab Interne »  (/root/.lab09/gnupg)
#   * quatre paquets .deb (ou .rpm sous Rocky) construits localement
#   * un dépôt signé, servi en file:// et en http://  (/srv/depot-lab)
#   * une archive de sources à compiler              (~/lab09/sources)
#
# Il fonctionne sans accès internet une fois les paquets d'outillage
# installés (voir §9.1).
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab09"
DEPOT=/srv/depot-lab
ETAT=/root/.lab09
GNUPGHOME="$ETAT/gnupg"
export GNUPGHOME
KEY_UID="Depot Lab Interne <depot@lab.local>"

. /etc/os-release
DISTRO="${ID:-inconnu}"

echo "== Préparation du module 09 =="
echo "   utilisateur : $LAB_USER"
echo "   distribution: $DISTRO ${VERSION_ID:-}"
echo "   dépôt local : $DEPOT"

mkdir -p "$ETAT" "$DEPOT" "$BASE"/{rapports,sources,bin,paquets}
chmod 0700 "$ETAT"

# ---------------------------------------------------------------------
# 1. Clé GPG du dépôt interne (commune aux deux distributions)
# ---------------------------------------------------------------------
command -v gpg >/dev/null 2>&1 || {
  echo "gpg est requis (voir §9.1)" >&2; exit 1; }

if [ ! -d "$GNUPGHOME" ]; then
  mkdir -p "$GNUPGHOME"; chmod 0700 "$GNUPGHOME"
  cat > "$ETAT/key.batch" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: Depot Lab Interne
Name-Email: depot@lab.local
Expire-Date: 0
%commit
EOF
  gpg --batch --quiet --gen-key "$ETAT/key.batch"
  rm -f "$ETAT/key.batch"
fi

KEYID="$(gpg --list-keys --with-colons "$KEY_UID" \
         | awk -F: '/^pub:/ {print $5; exit}')"
[ -n "$KEYID" ] || { echo "clé GPG introuvable" >&2; exit 1; }
echo "   clé du dépôt: $KEYID"

# Deux formats publiés, comme le font les vrais dépôts tiers :
#   .asc  armuré  (Docker, HashiCorp, PostgreSQL…)
#   .gpg  binaire (ce que produit `gpg --dearmor`)
gpg --batch --yes --armor --export "$KEYID" > "$DEPOT/depot-lab.asc"
gpg --batch --yes --export "$KEYID"          > "$ETAT/depot-lab.gpg"
cp -a "$ETAT/depot-lab.gpg" "$BASE/depot-lab.gpg"

# ---------------------------------------------------------------------
# 2a. Branche Debian/Ubuntu
# ---------------------------------------------------------------------
construire_deb() {
  # construire_deb <version> <depends> <postinst_exigeant>
  local ver="$1" dep="${2:-}" exigeant="${3:-non}"
  local nom="outil-lab" d
  if [ -n "$dep" ]; then nom="agent-lab"; fi
  d="$ETAT/build/${nom}-${ver}"
  rm -rf "$d"
  mkdir -p "$d/DEBIAN" "$d/usr/bin" "$d/etc/$nom" \
           "$d/usr/share/doc/$nom"

  {
    printf 'Package: %s\n' "$nom"
    printf 'Version: %s\n' "$ver"
    printf 'Section: utils\nPriority: optional\nArchitecture: all\n'
    if [ -n "$dep" ]; then printf 'Depends: %s\n' "$dep"; fi
    printf 'Maintainer: Equipe Socle <depot@lab.local>\n'
    printf 'Description: Outillage interne du lab (module 09)\n'
    printf ' Paquet construit localement pour les exercices sur la\n'
    printf ' gestion des paquets. Ne fait rien d utile en production.\n'
  } > "$d/DEBIAN/control"

  printf '/etc/%s/%s.conf\n' "$nom" "${nom%%-*}" > "$d/DEBIAN/conffiles"

  printf '#!/bin/sh\necho "%s version %s"\n' "$nom" "$ver" \
    > "$d/usr/bin/$nom"
  chmod 0755 "$d/usr/bin/$nom"

  {
    printf '# %s — configuration locale\n' "$nom"
    printf '# Modifie ce fichier : c est un conffile dpkg.\n'
    printf 'niveau_journal=info\n'
    printf 'version_paquet=%s\n' "$ver"
    case "$ver" in
      1.2.0) printf 'cache_secondes=30\n' ;;
      1.3.0) printf 'cache_secondes=60\nmode_strict=oui\n' ;;
    esac
  } > "$d/etc/$nom/${nom%%-*}.conf"

  if [ "$exigeant" = oui ]; then
    cat > "$d/DEBIAN/postinst" <<'POSTEOF'
#!/bin/sh
set -e
if [ ! -f /etc/outil-lab/licence.key ]; then
  echo "outil-lab: /etc/outil-lab/licence.key manquant" >&2
  exit 1
fi
exit 0
POSTEOF
    chmod 0755 "$d/DEBIAN/postinst"
  fi

  mkdir -p "$ETAT/debs"
  dpkg-deb --build --root-owner-group "$d" \
    "$ETAT/debs/${nom}_${ver}_all.deb" >/dev/null
}

publier_depot_deb() {
  cd "$DEPOT"
  dpkg-scanpackages --multiversion pool /dev/null > Packages 2>/dev/null
  gzip -9 -kf Packages
  python3 - "$DEPOT" <<'PYEOF'
import email.utils, hashlib, os, sys, time
d = sys.argv[1]
fichiers = ["Packages", "Packages.gz"]
l = ["Origin: LabInterne", "Label: LabInterne", "Suite: stable",
     "Codename: stable", "Architectures: amd64 all",
     "Date: " + email.utils.formatdate(time.time(), usegmt=True)]
for algo, entete in (("md5", "MD5Sum"), ("sha256", "SHA256")):
    l.append(entete + ":")
    for f in fichiers:
        p = os.path.join(d, f)
        h = hashlib.new(algo, open(p, "rb").read()).hexdigest()
        l.append(" %s %d %s" % (h, os.path.getsize(p), f))
open(os.path.join(d, "Release"), "w").write("\n".join(l) + "\n")
PYEOF
  gpg --batch --yes --quiet --default-key "$KEYID" \
      --clearsign -o InRelease Release
  gpg --batch --yes --quiet --default-key "$KEYID" \
      --detach-sign --armor -o Release.gpg Release
  cd - >/dev/null
}

preparer_ubuntu() {
  for outil in dpkg-deb dpkg-scanpackages python3; do
    command -v "$outil" >/dev/null 2>&1 || {
      echo "$outil est requis : sudo apt install -y dpkg-dev python3" >&2
      exit 1; }
  done

  rm -rf "$DEPOT/pool" "$ETAT/debs"; mkdir -p "$DEPOT/pool" "$ETAT/debs"
  construire_deb 1.0.0
  construire_deb 1.2.0
  construire_deb 1.3.0 "" oui
  construire_deb 2.0.0 "libmetric3 (>= 3.2)"

  # Le dépôt ne publie que 1.0.0 et 1.2.0 : la version candidate est donc
  # 1.2.0, et l'épinglage de L9.3 a quelque chose à arbitrer.
  # outil-lab 1.3.0 (postinst exigeant) et agent-lab 2.0.0 (dépendance
  # introuvable) restent hors dépôt, dans ~/lab09/paquets : ils servent
  # aux exercices dpkg -i et aux Break & Fix.
  cp -a "$ETAT/debs/outil-lab_1.0.0_all.deb" \
        "$ETAT/debs/outil-lab_1.2.0_all.deb" "$DEPOT/pool/"
  publier_depot_deb

  # Le même dépôt servi en HTTP, pour travailler signed-by sur une URL
  # réaliste. Aucun paquet à installer : python3 suffit.
  cat > /etc/systemd/system/depot-lab.service <<'EOF'
[Unit]
Description=Depot de paquets interne du lab (module 09)
After=network.target

[Service]
Type=exec
ExecStart=/usr/bin/python3 -m http.server 8099 --directory /srv/depot-lab \
          --bind 0.0.0.0
Restart=on-failure
DynamicUser=yes

[Install]
WantedBy=multi-user.target
EOF
  if [ -d /run/systemd/system ]; then
    systemctl daemon-reload
    systemctl enable --now depot-lab.service >/dev/null 2>&1 || \
      echo "  note : depot-lab.service n'a pas démarré, file:// reste OK"
  fi
}

# ---------------------------------------------------------------------
# 2b. Branche RHEL/Rocky
# ---------------------------------------------------------------------
construire_rpm() {
  local ver="$1" nom="${2:-outil-lab}" dep="${3:-}"
  local top="$ETAT/rpmbuild"
  mkdir -p "$top"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  cat > "$top/SPECS/${nom}-${ver}.spec" <<EOF
Name:           $nom
Version:        $ver
Release:        1%{?dist}
Summary:        Outillage interne du lab (module 09)
License:        MIT
BuildArch:      noarch
$( [ -n "$dep" ] && printf 'Requires:       %s\n' "$dep" )

%description
Paquet construit localement pour les exercices sur la gestion des
paquets. Ne fait rien d'utile en production.

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/etc/$nom
printf '#!/bin/sh\necho "$nom version $ver"\n' \\
  > %{buildroot}/usr/bin/$nom
chmod 0755 %{buildroot}/usr/bin/$nom
printf '# $nom - configuration locale\nniveau_journal=info\nversion_paquet=$ver\n' \\
  > %{buildroot}/etc/$nom/${nom%%-*}.conf

%files
/usr/bin/$nom
%config(noreplace) /etc/$nom/${nom%%-*}.conf

%changelog
* Mon Jan 01 2024 Equipe Socle <depot@lab.local> - $ver-1
- Version $ver
EOF
  rpmbuild --quiet --define "_topdir $top" \
    -bb "$top/SPECS/${nom}-${ver}.spec" >/dev/null
  mkdir -p "$ETAT/rpms"
  cp -f "$top"/RPMS/noarch/${nom}-${ver}-1*.rpm "$ETAT/rpms/"
}

preparer_rocky() {
  for outil in rpmbuild createrepo_c rpmsign; do
    command -v "$outil" >/dev/null 2>&1 || {
      echo "$outil est requis :" >&2
      echo "  sudo dnf install -y rpm-build rpm-sign createrepo_c" >&2
      exit 1; }
  done

  rm -rf "$DEPOT/pool" "$ETAT/rpms"; mkdir -p "$DEPOT/pool" "$ETAT/rpms"
  construire_rpm 1.0.0
  construire_rpm 1.2.0
  construire_rpm 2.0.0 agent-lab "libmetric3 >= 3.2"

  cat > /root/.rpmmacros <<EOF
%_gpg_name $KEY_UID
%_gpg_path $GNUPGHOME
%_signature gpg
EOF
  rpmsign --addsign "$ETAT"/rpms/*.rpm >/dev/null 2>&1 || \
    echo "  note : signature des RPM impossible, gpgcheck=0 sera requis"

  # Même logique que sous Ubuntu : agent-lab, qui exige une dépendance
  # introuvable, reste hors dépôt pour les exercices rpm -i.
  cp -a "$ETAT"/rpms/outil-lab-*.rpm "$DEPOT/pool/"

  cp -a "$DEPOT/depot-lab.asc" "$DEPOT/RPM-GPG-KEY-lab"
  createrepo_c --quiet --update "$DEPOT"
  gpg --batch --yes --quiet --default-key "$KEYID" \
      --detach-sign --armor "$DEPOT/repodata/repomd.xml"

  if command -v firewall-cmd >/dev/null 2>&1 \
     && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --add-port=8099/tcp --permanent >/dev/null
    firewall-cmd --reload >/dev/null
  fi
  cat > /etc/systemd/system/depot-lab.service <<'EOF'
[Unit]
Description=Depot de paquets interne du lab (module 09)
After=network.target

[Service]
Type=exec
ExecStart=/usr/bin/python3 -m http.server 8099 --directory /srv/depot-lab \
          --bind 0.0.0.0
Restart=on-failure
DynamicUser=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now depot-lab.service >/dev/null 2>&1 || true
}

case "$DISTRO" in
  ubuntu|debian) preparer_ubuntu ;;
  rocky|rhel|almalinux|centos) preparer_rocky ;;
  *) echo "distribution $DISTRO non gérée par ce script" >&2; exit 1 ;;
esac

chmod -R a+rX "$DEPOT"

# ---------------------------------------------------------------------
# 3. Archive de sources à compiler (E9.x, L9.4)
# ---------------------------------------------------------------------
SRC="$ETAT/build/horodate-1.4"
rm -rf "$SRC"; mkdir -p "$SRC"

cat > "$SRC/horodate.c" <<'CEOF'
/* horodate — affiche l'horodatage courant au format choisi.
 * Programme jouet du module 09 : sert uniquement à illustrer la
 * compilation depuis les sources et le rôle de --prefix.
 */
#include <stdio.h>
#include <string.h>
#include <time.h>

#ifndef HORODATE_VERSION
#define HORODATE_VERSION "1.4"
#endif

int main(int argc, char **argv)
{
    char tampon[128];
    const char *format = "%Y-%m-%d %H:%M:%S";
    time_t maintenant = time(NULL);

    if (argc > 1 && strcmp(argv[1], "--version") == 0) {
        printf("horodate %s\n", HORODATE_VERSION);
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "--iso") == 0)
        format = "%Y-%m-%dT%H:%M:%S%z";

    strftime(tampon, sizeof tampon, format, localtime(&maintenant));
    printf("%s\n", tampon);
    return 0;
}
CEOF

cat > "$SRC/configure" <<'CFGEOF'
#!/bin/sh
# configure — version minimaliste écrite à la main. Les vrais scripts
# autoconf font la même chose : ils testent l'environnement puis
# produisent le Makefile à partir de Makefile.in.
set -e
prefix=/usr/local
bindir=
CC=${CC:-cc}

for arg in "$@"; do
  case "$arg" in
    --prefix=*) prefix="${arg#*=}" ;;
    --bindir=*) bindir="${arg#*=}" ;;
    --help)
      echo "Usage: ./configure [--prefix=DIR] [--bindir=DIR]"
      echo "  --prefix  racine d'installation (defaut: /usr/local)"
      exit 0 ;;
    *) echo "configure: option inconnue: $arg" >&2; exit 1 ;;
  esac
done
: "${bindir:=$prefix/bin}"

printf 'checking for a C compiler... '
if ! command -v "$CC" >/dev/null 2>&1; then
  echo "none"
  echo "configure: error: no acceptable C compiler found in \$PATH" >&2
  exit 1
fi
echo "$CC"

printf 'checking for time.h... '
echo '#include <time.h>' | "$CC" -E - >/dev/null 2>&1 \
  && echo yes || { echo no; exit 1; }

sed -e "s|@prefix@|$prefix|g" \
    -e "s|@bindir@|$bindir|g" \
    -e "s|@CC@|$CC|g" Makefile.in > Makefile

echo "configure: creating Makefile"
echo "  prefix = $prefix"
echo "  bindir = $bindir"
CFGEOF
chmod 0755 "$SRC/configure"

cat > "$SRC/Makefile.in" <<'MKEOF'
prefix  = @prefix@
bindir  = @bindir@
CC      = @CC@
CFLAGS  = -O2 -Wall
DESTDIR =

all: horodate

horodate: horodate.c
	$(CC) $(CFLAGS) -o horodate horodate.c

install: horodate
	install -d $(DESTDIR)$(bindir)
	install -m 0755 horodate $(DESTDIR)$(bindir)/horodate

uninstall:
	rm -f $(DESTDIR)$(bindir)/horodate

clean:
	rm -f horodate

.PHONY: all install uninstall clean
MKEOF

cat > "$SRC/README" <<'RDEOF'
horodate 1.4
============

Construction :

    ./configure --prefix=/usr/local
    make
    sudo make install

Le Makefile respecte DESTDIR : « make install DESTDIR=/tmp/racine »
installe dans une racine factice sans toucher au système. C'est ce que
font tous les outils d'empaquetage.
RDEOF

tar -czf "$BASE/sources/horodate-1.4.tar.gz" \
    -C "$ETAT/build" horodate-1.4

# ---------------------------------------------------------------------
# 4. Copie locale des paquets, pour les exercices dpkg -i / rpm -i
# ---------------------------------------------------------------------
for d in "$ETAT/debs" "$ETAT/rpms"; do
  [ -d "$d" ] && cp -a "$d"/* "$BASE/paquets/"
done
true
chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 5. Avertissements d'outillage
# ---------------------------------------------------------------------
case "$DISTRO" in
  ubuntu|debian)
    for p in gcc make aptitude apt-file unattended-upgrades; do
      dpkg -s "$p" >/dev/null 2>&1 || \
        echo "  note : $p n'est pas installé (voir §9.1)"
    done ;;
  *)
    for p in gcc make dnf-automatic; do
      rpm -q "$p" >/dev/null 2>&1 || \
        echo "  note : $p n'est pas installé (voir §9.1)"
    done ;;
esac

cat <<EOF

Prêt. Points d'entrée :
  $DEPOT/                    dépôt interne signé (pool/, Release, InRelease)
  $DEPOT/depot-lab.asc       clé publique du dépôt, format armuré
  http://127.0.0.1:8099/     le même dépôt servi en HTTP
  $BASE/paquets/             les paquets seuls, pour dpkg -i / rpm -i
  $BASE/sources/horodate-1.4.tar.gz   sources à compiler
  $BASE/rapports/            tes livrables

Ce que le script n'a PAS fait, et qui est le travail du module :
  * déclarer le dépôt dans /etc/apt/sources.list.d (ou /etc/yum.repos.d)
  * installer la clé dans /etc/apt/keyrings (ou rpm --import)
  * écrire le moindre fichier d'épinglage

Vérification rapide :
  ls $DEPOT/pool/
  gpg --show-keys $DEPOT/depot-lab.asc
EOF
