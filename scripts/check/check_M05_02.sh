#!/usr/bin/env bash
# check_M05_02.sh — vérifie le lab L5.2 (réconciliation CMDB / API / supervision)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L5.2 =="

BASE="$HOME/lab05"
PARC="$BASE/rapports/parc-complet.csv"
ECA="$BASE/rapports/ecarts-parc.txt"

[ -f "$BASE/serveurs.csv" ] || { ko "jeu de données absent (setup_M05.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. le fichier consolidé -------------------------------------------
if [ -s "$PARC" ]; then
  ok "rapports/parc-complet.csv existe"
else
  ko "rapports/parc-complet.csv absent ou vide (étape 4)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

entete=$(head -1 "$PARC" | tr -d ' \r')
att="hostname,env,role,site,datacenter,cout_eur,disque_pct,supervise"
[ "$entete" = "$att" ] \
  && ok "l'en-tête est conforme" \
  || ko "en-tête attendu : $att (obtenu : $entete)"

n=$(tail -n +2 "$PARC" | grep -c .)
[ "$n" -eq 60 ] \
  && ok "60 lignes de données" \
  || ko "$n lignes de données au lieu de 60 (l'en-tête compte-t-il en double ?)"

# --- 2. le contenu doit être juste --------------------------------------
sup_non=$(awk -F, 'NR > 1 && $8 == "non"' "$PARC" | wc -l)
[ "$sup_non" -eq 8 ] \
  && ok "8 hôtes marqués non supervisés" \
  || ko "$sup_non hôtes 'non' au lieu de 8 (comm -23 sur des fichiers TRIÉS)"

for h in api-dev-16 db-pro-33 proxy-pro-17 worker-pro-24; do
  v=$(awk -F, -v h="$h" '$1 == h { print $8 }' "$PARC")
  [ "$v" = "non" ] && ok "$h est bien marqué non supervisé" \
                   || ko "$h devrait être 'non' (obtenu : '${v:-absent}')"
done

d=$(awk -F, '$1 == "web-pro-12" { print $7 }' "$PARC")
[ "$d" = "97" ] \
  && ok "disque_pct de web-pro-12 repris du JSON (97)" \
  || ko "disque_pct de web-pro-12 vaut '${d:-vide}' au lieu de 97 (jq)"

dc=$(awk -F, '$1 == "api-dev-01" { print $5 }' "$PARC")
[ "$dc" = "DC-LYS-1" ] \
  && ok "datacenter repris de sites.csv (api-dev-01 -> DC-LYS-1)" \
  || ko "datacenter de api-dev-01 vaut '${dc:-vide}' au lieu de DC-LYS-1"

total=$(awk -F, 'NR > 1 { s += $6 } END { printf "%.2f", s }' "$PARC")
[ "$total" = "14998.40" ] \
  && ok "coût total cohérent : $total EUR" \
  || ko "coût total = $total au lieu de 14998.40 (colonne 6 mal reprise ?)"

ns=$(awk -F, 'NR > 1 && $8 == "non" { s += $6 } END { printf "%.2f", s }' "$PARC")
[ "$ns" = "1872.00" ] \
  && ok "coût des non supervisés cohérent : $ns EUR" \
  || ko "coût des non supervisés = $ns au lieu de 1872.00"

# --- 3. le rapport d'écarts ---------------------------------------------
if [ -s "$ECA" ]; then
  ok "rapports/ecarts-parc.txt existe"
  manque=0
  for h in api-dev-16 web-pro-50 vpn-pro-91 nas-pro-94; do
    grep -q "$h" "$ECA" || { manque=1; note "$h absent du rapport d'écarts"; }
  done
  [ "$manque" -eq 0 ] \
    && ok "les deux listes d'écarts figurent dans le rapport" \
    || ko "au moins un hôte en écart manque (comm -23 ET comm -13)"
  for h in cache-pre-21 proxy-dev-38 proxy-dev-59; do
    grep -q "$h" "$ECA" || note "$h (agent inactif) absent du rapport"
  done
  grep -q 'web-pro-12' "$ECA" \
    && ok "les disques pleins sont signalés" \
    || ko "les hôtes à plus de 85 % de disque ne sont pas listés (étape 3)"
else
  ko "rapports/ecarts-parc.txt absent ou vide (étape 7)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
