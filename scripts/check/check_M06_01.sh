#!/usr/bin/env bash
# check_M06_01.sh — vérifie le lab L6.1 (reprise du vhost sous vim)
# On vérifie le CONTENU FINAL du fichier, jamais la méthode employée.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L6.1 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
CONF="$HOMEDIR/lab06/edition/factura.conf"
COPIE=/etc/factura/frontal.conf.nouveau

[ -f "$CONF" ] || { ko "$CONF introuvable (relance setup_M06.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. server_name du bloc actif ---------------------------------------
if grep -Eq '^[[:space:]]*server_name[[:space:]]+"?factura\.lab\.local"?;' \
     "$CONF"; then
  ok "server_name vaut factura.lab.local"
else
  ko "server_name n'a pas été repris (attendu : factura.lab.local)"
fi
if grep -q 'ancien-frontal.example.org' "$CONF"; then
  ko "l'ancien server_name ancien-frontal.example.org est toujours là"
else
  ok "l'ancien server_name a disparu"
fi

# --- 2. migration /opt -> /srv dans la partie active ---------------------
# règle : toute ligne ACTIVE (non commentée) ne doit plus contenir /opt/
RESTE=$(grep -n '/opt/' "$CONF" | grep -vE '^[0-9]+:[[:space:]]*#' | wc -l)
if [ "$RESTE" -eq 0 ]; then
  ok "plus aucun /opt/ sur une ligne active"
else
  ko "$RESTE ligne(s) active(s) contiennent encore /opt/ (grep -n /opt/ $CONF)"
fi
if grep -q '/srv/factura/public' "$CONF"; then
  ok "les chemins actifs pointent vers /srv/factura"
else
  ko "aucun /srv/factura/public : la migration de chemins n'a pas eu lieu"
fi

# --- 3. bloc hérité commenté ET intact -----------------------------------
LEGACY_TOTAL=$(grep -c '/opt/legacy' "$CONF")
LEGACY_COM=$(grep '/opt/legacy' "$CONF" | grep -cE '^[[:space:]]*#')
if [ "$LEGACY_TOTAL" -ge 4 ] && [ "$LEGACY_TOTAL" -eq "$LEGACY_COM" ]; then
  ok "le bloc hérité a gardé ses chemins /opt/legacy, tous commentés"
else
  ko "le bloc hérité doit rester en /opt/legacy et être entièrement commenté \
($LEGACY_COM/$LEGACY_TOTAL lignes commentées)"
fi
for MOTIF in 'fastcgi_pass' 'admin-2019' 'legacy.example.org'; do
  LIG=$(grep -n -- "$MOTIF" "$CONF" | head -1)
  if [ -z "$LIG" ]; then
    ko "la ligne contenant $MOTIF a disparu : le bloc devait être commenté, \
pas supprimé"
  elif printf '%s' "$LIG" | grep -qE '^[0-9]+:[[:space:]]*#'; then
    ok "la ligne $MOTIF est commentée"
  else
    ko "la ligne $MOTIF n'est pas commentée"
  fi
done

# --- 4. ligne de revue datée --------------------------------------------
if grep -qE '^#.*revu.*(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}' "$CONF"; then
  ok "la ligne de revue datée est présente"
else
  ko "pas de ligne '# revu le <date> par ... sur <hote>' (:0r !date ...)"
fi

# --- 5. directive ajoutée dans le bloc actif -----------------------------
if grep -Eq '^[[:space:]]*client_max_body_size[[:space:]]+32m;' "$CONF"; then
  ok "client_max_body_size 32m; ajouté et actif"
else
  ko "client_max_body_size 32m; absent ou commenté dans le bloc actif"
fi

# --- 6. plus de doubles lignes vides -------------------------------------
DBL=$(awk 'BEGIN{v=0;n=0} /^[[:space:]]*$/{if(v)n++; v=1; next} {v=0} \
           END{print n}' "$CONF")
if [ "$DBL" -eq 0 ]; then
  ok "aucune paire de lignes vides consécutives"
else
  ko "$DBL ligne(s) vide(s) en double subsistent (:%s/\\n\\{3,}/\\r\\r/e)"
fi

# --- 7. report vers /etc, sans relancer vim ------------------------------
if [ -f "$COPIE" ]; then
  ok "$COPIE existe"
  if cmp -s "$CONF" "$COPIE"; then
    ok "le contenu de $COPIE est identique au fichier de travail"
  else
    ko "$COPIE diffère du fichier de travail (diff $CONF $COPIE)"
  fi
  OWN=$(stat -c '%U' "$COPIE")
  [ "$OWN" = root ] && ok "$COPIE appartient à root" || \
    note "$COPIE appartient à $OWN : acceptable, mais tee l'aurait créé en root"
else
  ko "$COPIE absent (:w !sudo tee /etc/factura/frontal.conf.nouveau)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
