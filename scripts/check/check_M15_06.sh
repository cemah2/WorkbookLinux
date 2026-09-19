#!/usr/bin/env bash
# check_M15_06.sh — vérifie le défi D15 (dossier d'exploitation) sur lab-adm
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D15 =="
B="$HOME/lab15"

# --- configurations versionnées ------------------------------------------
for f in conf/lab-web conf/lab-db; do
  [ -d "$B/$f" ] && [ "$(ls "$B/$f" | wc -l)" -ge 2 ] && ok "$f : $(ls "$B/$f" | wc -l) fichiers" \
    || ko "$B/$f absent ou presque vide"
done
NOHDR=0
for f in "$B"/conf/*/*; do
  [ -f "$f" ] || continue
  head -4 "$f" | grep -qiE 'r[ôo]le' && head -4 "$f" | grep -qiE 'h[ôo]te' || NOHDR=$((NOHDR+1))
done
[ "$NOHDR" = 0 ] && ok "en-tête rôle/hôte/date sur chaque fichier" \
  || ko "$NOHDR fichier(s) sans en-tête rôle/hôte/date"
ls "$B"/conf/lab-web/ 2>/dev/null | grep -qi nginx && ok "vhost nginx présent" || ko "vhost nginx absent de conf/lab-web"
ls "$B"/conf/lab-db/ 2>/dev/null | grep -q pg_hba && ok "pg_hba.conf présent" || ko "pg_hba.conf absent de conf/lab-db"
ls "$B"/conf/lab-db/ 2>/dev/null | grep -qi redis && ok "redis.conf.diff présent" || ko "redis.conf.diff absent"

# --- script de conformité -----------------------------------------------
V="$B/bin/verif-services.sh"
if [ -x "$V" ]; then
  ok "verif-services.sh exécutable"
  head -1 "$V" | grep -q '^#!/usr/bin/env bash' && ok "shebang env bash" || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$V" && ok "set -euo pipefail" || ko "set -euo pipefail absent"
  bash -n "$V" && ok "syntaxe bash valide" || ko "erreur de syntaxe (bash -n)"
  for k in 'nginx -t' 'pg_hba' 'maxmemory' 'idle in transaction' 'sha256' 'swap'; do
    grep -qi -- "$k" "$V" && ok "contrôle « $k » présent" || ko "contrôle « $k » absent du script"
  done
  OUT="$(timeout 180 bash "$V" 2>&1)"; RC=$?
  [ "$RC" = 0 ] && ok "verif-services.sh sort en 0" \
    || ko "verif-services.sh sort en $RC : $(grep -c FAIL <<<"$OUT") FAIL"
  [ "$(grep -c '\[ OK \]' <<<"$OUT")" -ge 15 ] && ok "au moins 15 points vérifiés" \
    || ko "moins de 15 points [ OK ] : le script est incomplet"
else
  ko "$V absent ou non exécutable"
fi

# --- runbook --------------------------------------------------------------
RB="$B/rapports/runbook-services.md"
if [ -f "$RB" ]; then
  [ "$(wc -l < "$RB")" -ge 120 ] && ok "runbook >= 120 lignes" || ko "runbook trop court ($(wc -l < "$RB") lignes)"
  for k in 'reload' 'ordre' '502' '504' 'pg_hba' 'too many connections|max_connections' 'OOM' 'vide' 'pg_restore' 'recovery_target|PITR' 'rotation' 'ACL SETUSER|ALTER ROLE'; do
    grep -qiE -- "$k" "$RB" && ok "runbook : « $k »" || ko "runbook : « $k » manquant"
  done
  grep -q '\[ OK \]' "$RB" && ok "sortie de verif-services.sh collée" || ko "la preuve (sortie du script) manque"
else ko "runbook $RB absent"; fi

E="$B/rapports/entretien.md"
if [ -f "$E" ]; then
  for k in nginx postgres redis; do grep -qi "$k" "$E" && ok "fiche entretien : $k" || ko "fiche entretien : $k absent"; done
else ko "fiche $E absente"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
