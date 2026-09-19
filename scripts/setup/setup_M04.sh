#!/usr/bin/env bash
# setup_M04.sh — prépare le terrain du module 04 (utilisateurs, groupes, sudo)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab04"
APP=/opt/factura

echo "== Préparation du module 04 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 1. Groupes du lab
# ---------------------------------------------------------------------
for g in factura deploy astreinte; do
  groupadd -f "$g"
done

# groupe d'administration : sudo (Ubuntu) ou wheel (Rocky)
ADMGRP=sudo
getent group sudo >/dev/null || ADMGRP=wheel
getent group "$ADMGRP" >/dev/null || groupadd "$ADMGRP"

# ---------------------------------------------------------------------
# 2. Comptes humains du lab
# ---------------------------------------------------------------------
# sophie : dev, groupe PRIMAIRE factura (piège de Q4.15), secondaire deploy
if ! getent passwd sophie >/dev/null; then
  useradd -m -s /bin/bash -g factura -G deploy \
          -c "Sophie Perrin - Dev" sophie
  echo 'sophie:Lab04!sophie' | chpasswd
fi

# karim : ops, membre de sudo/deploy/factura — cible de BF4.2 et BF4.3
if ! getent passwd karim >/dev/null; then
  useradd -m -U -s /bin/bash -G "$ADMGRP",deploy,factura \
          -c "Karim Aziz - Ops" karim
  echo 'karim:Lab04!karim' | chpasswd
fi
# on garantit l'état de départ même après un passage de break_M04_03.sh
usermod -aG "$ADMGRP",deploy,factura karim >/dev/null 2>&1 || true
usermod -s /bin/bash karim >/dev/null 2>&1 || true
chage -E -1 -M 90 -m 1 -W 14 -I 7 karim
passwd -q -u karim >/dev/null 2>&1 || true

# pcontrat : prestataire, compte à durée limitée (E4.10, L4.4)
if ! getent passwd pcontrat >/dev/null; then
  useradd -m -U -s /bin/bash -c "Prestataire externe" pcontrat
  echo 'pcontrat:Lab04!presta' | chpasswd
fi
chage -m 7 -M 60 -W 14 -I 10 -E "$(date -d '+90 days' +%F)" pcontrat

# ---------------------------------------------------------------------
# 3. LE compte de service mal créé (L4.2)
#    UID d'humain, shell bash, home dans /home, membre de sudo,
#    mot de passe connu : tout ce qu'il ne faut pas faire.
# ---------------------------------------------------------------------
if ! getent passwd facturasvc >/dev/null; then
  useradd -m -U -s /bin/bash -c "Service factura (a corriger)" facturasvc
fi

# usermod refuse de toucher à l'UID ou au home d'un compte dont un processus
# tourne : on arrête d'abord le faux démon, on le relancera en fin de section.
pkill -u facturasvc >/dev/null 2>&1 || true
sleep 1

# état de départ volontairement non conforme, réappliqué à chaque setup
# (ce qui rend le lab L4.2 rejouable sans rollback de snapshot)
usermod -s /bin/bash facturasvc >/dev/null 2>&1 || true
usermod -aG "$ADMGRP" facturasvc >/dev/null 2>&1 || true
echo 'facturasvc:MotDePasseDuWiki2024' | chpasswd
if [ "$(id -u facturasvc)" -lt 1000 ]; then
  libre=$( { getent passwd | cut -d: -f3; getent group | cut -d: -f3; } \
           | sort -n -u | awk 'BEGIN{n=1500} {if($1==n) n++} END{print n}')
  usermod -u "$libre" facturasvc >/dev/null 2>&1 || true
  groupmod -g "$libre" facturasvc >/dev/null 2>&1 || true
fi
if [ "$(getent passwd facturasvc | cut -d: -f6)" != /home/facturasvc ]; then
  mkdir -p /home/facturasvc
  usermod -d /home/facturasvc facturasvc >/dev/null 2>&1 || true
fi
mkdir -p /home/facturasvc
chown -R facturasvc:facturasvc /home/facturasvc
rm -rf /var/lib/facturasvc

# ---------------------------------------------------------------------
# 4. L'application servie par ce compte (/opt/factura)
# ---------------------------------------------------------------------
mkdir -p "$APP"/{bin,etc,data}
cat > "$APP/etc/factura.conf" <<'EOF'
# configuration factura
listen   = 0.0.0.0:8080
data_dir = /opt/factura/data
log_level = info
EOF
cat > "$APP/bin/factura-purge" <<'EOF'
#!/usr/bin/env bash
# purge des fichiers temporaires de factura (chemins figés : pas d'argument)
set -euo pipefail
find /opt/factura/data -maxdepth 1 -type f -name '*.tmp' -mtime +1 -delete
echo "purge effectuée"
EOF
chmod 755 "$APP/bin/factura-purge"
chown -R root:root "$APP"
chgrp factura "$APP/etc/factura.conf" "$APP/data"
chmod 640 "$APP/etc/factura.conf"
chmod 770 "$APP/data"
# le service a besoin de lire sa conf : il est dans le groupe factura
id -nG facturasvc | tr ' ' '\n' | grep -qx factura || \
  usermod -aG factura facturasvc
printf 'cache\n' > "$APP/data/vieux.tmp"

# quelques fichiers hors du home, propriété du compte de service :
# ils deviendront orphelins au changement d'UID (étape 4 de L4.2)
mkdir -p /var/log/factura
: > /var/log/factura/app.log
chown facturasvc:facturasvc /var/log/factura /var/log/factura/app.log

# un processus qui tourne sous ce compte, pour que L4.2 ait un enjeu :
# le "service" est un simple veilleur, mais il est bien lancé sous facturasvc
cat > "$APP/bin/factura-daemon" <<'EOF'
#!/usr/bin/env bash
# simulacre de démon factura : il ne fait que rester en vie
exec sleep 86400
EOF
chmod 755 "$APP/bin/factura-daemon"
if ! pgrep -u facturasvc -f factura-daemon >/dev/null 2>&1; then
  setsid runuser -u facturasvc -- "$APP/bin/factura-daemon" \
    >/dev/null 2>&1 </dev/null &
  disown >/dev/null 2>&1 || true
  sleep 1
fi

# ---------------------------------------------------------------------
# 5. Règle sudo héritée, à trouver pendant le Défi D4
# ---------------------------------------------------------------------
cat > /etc/sudoers.d/50-legacy <<'EOF'
# Demandé en 2024 par l'équipe factura pour éditer la configuration.
# (revue de privilèges : cette règle est-elle acceptable ?)
%factura ALL=(ALL) NOPASSWD: /usr/bin/vim /opt/factura/etc/factura.conf
EOF
chown root:root /etc/sudoers.d/50-legacy
chmod 0440 /etc/sudoers.d/50-legacy
visudo -c >/dev/null || echo "  ATTENTION : visudo -c signale un problème" >&2

# ---------------------------------------------------------------------
# 6. Bac à sable de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,rapports}
cat > "$BASE/arrivees.csv" <<'EOF'
lucie;Lucie Fabre - Dev;factura
hugo;Hugo Meyer - Dev;factura
nadia;Nadia Belkacem - SRE;deploy
EOF
chown -R "$LAB_USER":"$LAB_USER" "$BASE"
chmod 700 "$BASE/rapports"

# sauvegarde de la pile PAM avant que L4.4 n'y touche
[ -d /root/.m04-backup/pam.d ] || {
  mkdir -p /root/.m04-backup
  cp -a /etc/pam.d /root/.m04-backup/pam.d
  cp -a /etc/login.defs /root/.m04-backup/login.defs
}

# avertissement si un outil du module manque
for p in useradd usermod chage passwd gpasswd visudo getent faillock; do
  command -v "$p" >/dev/null 2>&1 || echo "  note : $p absent (voir §4.1)"
done
[ -e /usr/lib/x86_64-linux-gnu/security/pam_pwquality.so ] || \
  echo "  note : pam_pwquality absent — apt install libpam-pwquality (L4.4)"

cat <<EOF

Prêt. Points d'entrée :
  $BASE/arrivees.csv        les trois arrivants de L4.1
  $BASE/rapports/           tes livrables (mode 700)
  facturasvc                compte de service à remettre en conformité (L4.2)
  $APP                      l'application servie par ce compte
  /etc/sudoers.d/50-legacy  règle héritée à auditer (D4)
  sophie / karim / pcontrat comptes de travail du module

Sauvegarde de /etc/pam.d et /etc/login.defs : /root/.m04-backup/
EOF
