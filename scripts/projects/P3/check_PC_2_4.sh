#!/usr/bin/env bash
# check_PC_2_4.sh — vérifie le ticket PC.2.4 (purge planifiée des exports)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.2.4 =="
SAUV=/root/.breakfix-backup; ID=PC_2_4
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
E=/srv/factura/exports

# 1. un timer systemd (pas un cron) nommé purge, hebdomadaire le dimanche
T=$(systemctl list-unit-files --type=timer --no-legend 2>/dev/null \
    | awk '/purge|export/ {print $1}' | head -1)
if [ -n "$T" ]; then
  ok "timer trouvé : $T"
  systemctl is-enabled -q "$T" && ok "$T est activé" || ko "$T n'est pas activé"
  CAL=$(systemctl show "$T" -p TimersCalendar --value 2>/dev/null)
  echo "$CAL" | grep -qiE 'Sun|dim' && ok "planifié le dimanche ($CAL)" \
    || ko "le timer n'est pas planifié le dimanche : $CAL"
  SVC=${T%.timer}.service
else
  ko "aucun timer *purge* ou *export* (systemctl list-timers --all)"; SVC=""
fi

# 2. exécution réelle : on remet un jeu de fichiers connu, on lance le service
for j in 2 45; do
  f="$E/export-$(date -d "$j days ago" +%Y%m%d).csv"
  printf 'x\n' > "$f"; touch -d "$j days ago" "$f"
done
f="$E/export-$(date -d '120 days ago' +%Y%m%d)-legal.csv"
printf 'x\n' > "$f"; touch -d '120 days ago' "$f"
mkdir -p "$E/archives-legales"; printf 'bilan\n' > "$E/archives-legales/bilan-2025.csv"
touch -d '300 days ago' "$E/archives-legales/bilan-2025.csv"
if [ -n "$SVC" ]; then
  systemctl start "$SVC" >/dev/null 2>&1 && ok "$SVC s'exécute" \
    || ko "$SVC échoue (journalctl -u $SVC)"
fi
[ -f "$E/export-$(date -d '2 days ago' +%Y%m%d).csv" ] \
  && ok "export récent conservé" || ko "un export de 2 jours a été supprimé"
[ ! -f "$E/export-$(date -d '45 days ago' +%Y%m%d).csv" ] \
  && ok "export de 45 jours purgé" || ko "l'export de 45 jours est toujours là"
[ -f "$E/export-$(date -d '120 days ago' +%Y%m%d)-legal.csv" ] \
  && ok "export *-legal.csv conservé" || ko "un fichier *-legal.csv a été supprimé"
[ -f "$E/archives-legales/bilan-2025.csv" ] \
  && ok "archives-legales/ intact" || ko "archives-legales/ a été touché"
[ -f "$E/README.txt" ] && ok "README.txt (non CSV) conservé" \
  || ko "README.txt supprimé : la purge doit se limiter aux *.csv"

# 3. la purge journalise ce qu'elle supprime
if [ -n "$SVC" ] && journalctl -u "$SVC" --since '-5 min' --no-pager 2>/dev/null \
     | grep -qiE 'supprim|purg|removed|deleted'; then
  ok "les suppressions sont journalisées"
else
  ko "aucune trace des fichiers supprimés dans journalctl -u $SVC"
fi

# 4. un mode simulation existe
SCR=$(systemctl show "$SVC" -p ExecStart --value 2>/dev/null \
      | grep -oE 'path=[^ ;]+' | head -1 | cut -d= -f2)
if [ -n "$SCR" ] && grep -qE 'dry-run|simul' "$SCR" 2>/dev/null; then
  ok "le script propose un mode --dry-run"
else
  ko "pas de mode --dry-run dans le script de purge ($SCR)"
fi

[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
