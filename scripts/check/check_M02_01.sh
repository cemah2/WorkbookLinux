#!/usr/bin/env bash
# check_M02_01.sh — vérifie le lab L2.1 (rangement FHS de factura)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L2.1 =="

# --- 1. binaires dans /opt ----------------------------------------------
for b in facturad facturactl; do
  if [ -x "/opt/factura/bin/$b" ]; then
    ok "/opt/factura/bin/$b est présent et exécutable"
  else
    ko "/opt/factura/bin/$b manquant ou non exécutable (chmod +x)"
  fi
done

# --- 2. facturactl appelable sans chemin, par un lien -------------------
LIEN=/usr/local/bin/facturactl
if [ -L "$LIEN" ]; then
  cible=$(readlink -f "$LIEN")
  if [ "$cible" = "/opt/factura/bin/facturactl" ]; then
    ok "$LIEN est un lien symbolique vers /opt/factura/bin/facturactl"
  else
    ko "$LIEN pointe vers $cible au lieu de /opt/factura/bin/facturactl"
  fi
elif [ -e "$LIEN" ]; then
  ko "$LIEN existe mais c'est une copie : l'énoncé demande un lien (ln -s)"
else
  ko "facturactl n'est pas appelable sans chemin (lien dans /usr/local/bin)"
fi

# --- 3. configuration ----------------------------------------------------
if [ -f /etc/factura/factura.conf ]; then
  ok "/etc/factura/factura.conf existe"
  grep -q '^listen' /etc/factura/factura.conf 2>/dev/null \
    && ok "la configuration livrée a bien été reprise" \
    || ko "/etc/factura/factura.conf ne contient pas la conf livrée"
else
  ko "la configuration n'est pas dans /etc/factura/ (FHS : conf statique)"
fi

# --- 4. état, journaux, données servies ---------------------------------
[ -f /var/lib/factura/factura.db ] \
  && ok "/var/lib/factura/factura.db : état persistant au bon endroit" \
  || ko "la base doit vivre dans /var/lib/factura/ (état variable de l'appli)"

[ -d /var/log/factura ] \
  && ok "/var/log/factura existe" \
  || ko "les journaux vont dans /var/log/factura/"

if compgen -G "/srv/factura/exports/*.csv" >/dev/null; then
  ok "les exports CSV sont dans /srv/factura/exports/"
  prop=$(stat -c %U /srv/factura/exports/*.csv 2>/dev/null | head -1)
  [ "$prop" = "www-data" ] \
    && ok "les exports appartiennent à www-data" \
    || ko "les exports appartiennent à $prop, nginx doit pouvoir les servir"
else
  ko "aucun CSV dans /srv/factura/exports/ (données servies : /srv)"
fi

# --- 5. unité systemd ----------------------------------------------------
UNIT=/etc/systemd/system/factura.service
if [ -f "$UNIT" ]; then
  ok "$UNIT est installée (unité locale : /etc/systemd/system)"
  grep -q '^RuntimeDirectory=factura' "$UNIT" \
    && ok "RuntimeDirectory=factura : /run/factura est géré par systemd" \
    || ko "l'unité doit déclarer RuntimeDirectory=factura (pas de mkdir /run)"
else
  ko "unité factura.service absente de /etc/systemd/system/"
fi

# --- 6. service actif et /run peuplé ------------------------------------
if [ -d /run/systemd/system ]; then
  if systemctl is-active --quiet factura.service; then
    ok "factura.service est actif"
  else
    ko "factura.service n'est pas actif (systemctl status factura)"
  fi
  if [ -f /run/factura/facturad.pid ]; then
    ok "/run/factura/facturad.pid existe"
  else
    ko "pas de pid dans /run/factura (RuntimeDirectory + redémarrage)"
  fi
else
  note "systemd n'est pas en service ici : étapes 6 et 7 non vérifiables"
fi

# --- 7. rien ne traîne au mauvais endroit -------------------------------
sale=0
for f in /usr/bin/facturad /usr/bin/facturactl /usr/sbin/facturad; do
  [ -e "$f" ] && { ko "$f : /usr/bin est réservé au gestionnaire de paquets";
                   sale=1; }
done
[ "$sale" -eq 0 ] && ok "aucun binaire de l'appli dans /usr/bin ni /usr/sbin"

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
if compgen -G "$HOMEDIR/factura*" >/dev/null; then
  ko "il reste une installation dans $HOMEDIR (une appli ne vit pas \
dans un home)"
else
  ok "rien n'est installé dans le répertoire personnel"
fi

# --- 8. rapport ----------------------------------------------------------
RAP="$HOMEDIR/lab02/rapports/fhs-factura.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 8 ]; then
  ok "le rapport fhs-factura.md est rédigé"
else
  ko "rapport ~/lab02/rapports/fhs-factura.md absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
