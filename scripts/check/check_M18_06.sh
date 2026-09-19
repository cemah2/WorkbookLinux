#!/usr/bin/env bash
# check_M18_06.sh — vérifie le défi D18 (audit-securite.sh + rapport)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D18 =="

LAB_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
S="$LAB_HOME/lab18/bin/audit-securite.sh"

[ -f "$S" ] || { ko "$S est absent"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
ok "le script existe"
[ -x "$S" ] && ok "il est exécutable" || ko "il n'est pas exécutable \
(chmod +x)"

head -1 "$S" | grep -q '^#!/usr/bin/env bash' \
  && ok "shebang conforme" \
  || ko "shebang attendu : #!/usr/bin/env bash"
grep -qE '^set -[euo]+' "$S" \
  && ok "le script pose des options strictes" \
  || ko "aucune ligne « set -uo pipefail »"

# --- 1. il ne modifie rien --------------------------------------------
suspect=""
for cmd in 'sysctl -w' 'systemctl start' 'systemctl stop' \
           'systemctl enable' 'systemctl disable' 'systemctl restart' \
           'setsebool' 'setenforce' 'ufw allow' 'ufw deny' 'ufw enable' \
           'firewall-cmd --add' 'apt-get install' 'dnf install' \
           'semanage' 'chmod ' 'chown '; do
  # on ignore les commentaires et les chaînes de message (verdict, echo,
  # printf) : « ufw enable » dans un conseil affiché n'est pas une action
  grep -n "$cmd" "$S" \
    | grep -vE ':\s*#|verdict |note |ko |ok |echo |printf ' \
    | grep -q . && suspect="$suspect [$cmd]"
done
[ -z "$suspect" ] \
  && ok "aucune commande de modification détectée" \
  || ko "le script semble MODIFIER le système :$suspect — un outil \
d'audit lit, il n'écrit pas"

# --- 2. exécution : séparation stdout / stderr -------------------------
OUT=$(mktemp); ERR=$(mktemp)
"$S" >"$OUT" 2>"$ERR"; RC=$?
case "$RC" in
  0|1|2) ok "code retour $RC conforme au contrat (0/1/2)" ;;
  *) ko "code retour $RC hors contrat" ;;
esac

[ -s "$OUT" ] && ok "le rapport part bien sur stdout" \
              || ko "stdout est vide"
head -1 "$OUT" | grep -q '^# ' \
  && ok "le rapport commence par un titre Markdown" \
  || ko "stdout ne ressemble pas à du Markdown (première ligne : \
$(head -1 "$OUT"))"
grep -qiE '\[[0-9:]+\]|trace|diagnostic' "$ERR" \
  && ok "la trace de diagnostic part sur stderr" \
  || note "stderr est vide : vérifie que la trace ne pollue pas stdout"

# --- 3. les sections obligatoires --------------------------------------
manquantes=""
verif_section() {   # verif_section <libellé> <motif ERE>
  grep -qiE "$2" "$OUT" || manquantes="$manquantes $1"
}
verif_section pare-feu  'pare-?feu|firewall'
verif_section ecoute    'coute|listen|socket'
verif_section MAC       'MAC|SELinux|AppArmor'
verif_section comptes   'omptes|UID 0'
verif_section maj       'mise[s]? à jour|correctif|update'
verif_section sysctl    'sysctl|noyau|kernel'
verif_section suid      'SUID'
verif_section tls       'TLS|certificat'
verif_section fail2ban  'fail2ban'
verif_section synthese  'synth|score'
[ -z "$manquantes" ] \
  && ok "les dix rubriques attendues sont présentes" \
  || ko "rubriques absentes du rapport :$manquantes"

# --- 4. verdicts et score ---------------------------------------------
for v in OK AVERTISSEMENT CRITIQUE; do
  grep -q "$v" "$OUT" || note "aucun verdict « $v » dans ce rapport \
(normal si la machine est conforme)"
done
grep -qE 'Score *: *[0-9]+' "$OUT" \
  && ok "le rapport affiche un score chiffré" \
  || ko "aucun score sur 100 dans le rapport"
grep -qE '^\|' "$OUT" \
  && ok "le rapport contient un tableau de synthèse" \
  || ko "pas de tableau de synthèse Markdown"

# --- 5. cohérence code retour / contenu --------------------------------
if grep -q 'CRITIQUE' "$OUT" && [ "$RC" -ne 2 ]; then
  ko "le rapport contient un CRITIQUE mais le code retour est $RC"
elif ! grep -q 'CRITIQUE' "$OUT" && [ "$RC" -eq 2 ]; then
  ko "code retour 2 sans aucun CRITIQUE dans le rapport"
else
  ok "le code retour est cohérent avec le contenu du rapport"
fi

# --- 6. idempotence : deux exécutions, même verdict global -------------
"$S" >/dev/null 2>&1; RC2=$?
[ "$RC" -eq "$RC2" ] \
  && ok "deux exécutions consécutives donnent le même verdict" \
  || ko "le verdict change entre deux exécutions : le script modifie \
l'état qu'il mesure"

# --- 7. le livrable ----------------------------------------------------
R="$LAB_HOME/lab18/rapport-T3.md"
if [ -s "$R" ]; then
  n=$(grep -c '^# Audit' "$R")
  [ "${n:-0}" -ge 2 ] \
    && ok "rapport-T3.md agrège $n machines" \
    || ko "rapport-T3.md ne contient que $n rapport(s) : le défi en \
demande cinq"
  head -20 "$R" | grep -qiE 'synth|priorit|action' \
    && ok "le rapport s'ouvre sur une synthèse" \
    || ko "pas de synthèse en tête de rapport-T3.md (point 6)"
else
  ko "~/lab18/rapport-T3.md absent"
fi

rm -f "$OUT" "$ERR"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
