#!/usr/bin/env bash
# check_PC_2_3.sh — vérifie le ticket PC.2.3 (sauvegardes vides)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.2.3 =="
SAUV=/root/.breakfix-backup; ID=PC_2_3
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
S=/usr/local/sbin/factura-backup
DEST=/var/backups/factura

# 1. une sauvegarde réelle produit une archive pleine
if systemctl start factura-backup.service 2>/dev/null || bash "$S" >/dev/null 2>&1; then
  ok "factura-backup.service s'exécute sans erreur"
else
  ko "factura-backup.service échoue (journalctl -u factura-backup)"
fi
DER=$(ls -1t "$DEST"/factura-*.tar.gz 2>/dev/null | head -1)
if [ -n "$DER" ]; then
  NB=$(tar -tzf "$DER" 2>/dev/null | grep -c -v '/$')
  [ "$NB" -ge 40 ] && ok "dernière archive : $NB fichiers ($DER)" \
    || ko "dernière archive : $NB fichier(s) seulement (tar -tzf $DER)"
else
  ko "aucune archive dans $DEST"
fi

# 2. quand la source disparaît, la sauvegarde doit ÉCHOUER, pas « réussir »
T=$(mktemp -d)
mount --bind "$T" /srv/factura/data
if bash "$S" >/dev/null 2>&1; then
  ko "source vide : le script rend 0 (une archive vide est un succès pour lui)"
else
  ok "source vide : le script rend un code d'erreur"
fi
umount /srv/factura/data; rmdir "$T"
ls -1t "$DEST"/factura-*.tar.gz 2>/dev/null | head -1 | while read -r a; do
  n=$(tar -tzf "$a" 2>/dev/null | grep -c -v '/$')
  [ "$n" -ge 40 ] || rm -f "$a"    # nettoyage de l'archive du test
done

# 3. le timer est toujours en place
systemctl is-enabled -q factura-backup.timer 2>/dev/null \
  && ok "factura-backup.timer activé" || ko "factura-backup.timer n'est plus activé"

# 4. les archives vides du passé ont été traitées (supprimées ou signalées)
VIDES=$(for a in "$DEST"/factura-*.tar.gz; do
          [ -f "$a" ] || continue
          [ "$(tar -tzf "$a" 2>/dev/null | grep -c -v '/$')" -lt 1 ] && echo "$a"
        done | wc -l)
[ "$VIDES" -eq 0 ] && ok "plus d'archive vide dans $DEST" \
  || ko "$VIDES archive(s) vide(s) encore présentes (elles trompent une restauration)"

# 5. prévention : un contrôle de restauration/contenu existe
if grep -qE 'tar -t|tar -tz|gzip -t|wc -c|-s "|size|taille' "$S"; then
  ok "le script vérifie le contenu ou la taille de l'archive"
else
  ko "le script ne vérifie pas son résultat (tar -tzf, taille minimale…)"
fi

[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
