#!/usr/bin/env bash
# check_M17_04.sh — vérifie le lab L17.4 (certificat + OnFailure)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L17.4 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : lab inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab17/rapports/alerte.md"
CHK=/opt/factura/bin/factura-cert-check.sh
CRT=/etc/factura/tls/portail.crt
ALOG=/var/log/factura/alertes.log

v() { systemctl show -p "$2" --value "$1" 2>/dev/null; }

# --- 1. le script de vérification -------------------------------------
if [ -x "$CHK" ]; then
  ok "$CHK existe et est exécutable"
  grep -q 'checkend' "$CHK" \
    && ok "utilise openssl x509 -checkend" \
    || ko "l'énoncé demande openssl x509 -checkend, pas un calcul de date \
maison"
  "$CHK" "$CRT" 1 >/tmp/.m14_04.a 2>&1; R1=$?
  "$CHK" "$CRT" 3650 >/tmp/.m14_04.b 2>&1; R2=$?
  [ "$R1" -eq 0 ] \
    && ok "seuil 1 jour : code 0 (certificat encore valide)" \
    || ko "seuil 1 jour : code $R1, on attend 0 (voir /tmp/.m14_04.a)"
  [ "$R2" -eq 1 ] \
    && ok "seuil 3650 jours : code 1 (expiration détectée)" \
    || ko "seuil 3650 jours : code $R2, on attend 1 (voir /tmp/.m14_04.b)"
  [ -s /tmp/.m14_04.b ] \
    && ok "un message est produit dans le cas d'échec" \
    || ko "aucun message en cas d'échec : l'énoncé demande un message clair \
dans les deux cas"
else
  ko "$CHK absent ou non exécutable"
fi

# --- 2. service + timer ------------------------------------------------
if systemctl cat factura-cert.service >/dev/null 2>&1; then
  ok "factura-cert.service existe"
  [ "$(v factura-cert.service Type)" = oneshot ] \
    && ok "Type=oneshot" \
    || ko "Type=$(v factura-cert.service Type), oneshot attendu"
  v factura-cert.service ExecStart | grep -q 'factura-cert-check' \
    && ok "ExecStart appelle le script de vérification" \
    || ko "ExecStart n'appelle pas $CHK"
else
  ko "factura-cert.service introuvable"
fi

if systemctl cat factura-cert.timer >/dev/null 2>&1; then
  ok "factura-cert.timer existe"
  v factura-cert.timer TimersCalendar | grep -q '07:00' \
    && ok "OnCalendar à 07:00" \
    || ko "OnCalendar=$(v factura-cert.timer TimersCalendar), 07:00 attendu"
  ACC=$(v factura-cert.timer AccuracyUSec)
  if [ -n "$ACC" ] && [ "$ACC" -ge 3600000000 ] 2>/dev/null; then
    ok "AccuracySec d'une heure ou plus ($ACC µs)"
  else
    ko "AccuracySec=$ACC : l'énoncé demande une tolérance d'une heure \
(AccuracySec=1h)"
  fi
  [ "$(systemctl is-enabled factura-cert.timer 2>/dev/null)" = enabled ] \
    && ok "factura-cert.timer est enabled" \
    || ko "factura-cert.timer n'est pas activé"
else
  ko "factura-cert.timer introuvable"
fi

# --- 3. l'unité modèle d'alerte ---------------------------------------
if systemctl cat 'factura-alerte@.service' >/dev/null 2>&1; then
  ok "unité modèle factura-alerte@.service présente"
  systemctl cat 'factura-alerte@.service' 2>/dev/null | grep -q '%i' \
    && ok "l'unité modèle exploite le paramètre %i" \
    || ko "l'unité modèle n'utilise pas %i : elle ne saura pas de quelle \
unité l'échec provient"
else
  ko "factura-alerte@.service introuvable (unité modèle, avec un @ avant \
le point)"
fi

OF=$(v factura-cert.service OnFailure)
if echo "$OF" | grep -q 'factura-alerte@'; then
  ok "OnFailure= branché sur l'unité d'alerte ($OF)"
else
  ko "OnFailure= absent ou mal branché sur factura-cert.service (valeur : \
« $OF ») — point 4"
fi

# --- 4. le chemin d'échec a réellement été emprunté -------------------
if [ -s "$ALOG" ]; then
  ok "$ALOG contient des alertes"
  grep -q 'factura-cert' "$ALOG" \
    && ok "une alerte nomme factura-cert.service" \
    || ko "aucune alerte concernant factura-cert : le chemin d'échec n'a \
pas été testé (point 5)"
else
  ko "$ALOG vide : aucune alerte n'a jamais été produite"
fi

# --- 5. test dynamique : on provoque un échec et on regarde -----------
echo "  -- test dynamique du chemin d'échec --"
AV=$(wc -l < "$ALOG" 2>/dev/null || echo 0)
cat > /run/.m14_04_test.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/opt/factura/bin/factura-cert-check.sh \
  /etc/factura/tls/portail.crt 3650
EOF
mkdir -p /run/systemd/system/factura-cert.service.d
cp /run/.m14_04_test.conf \
   /run/systemd/system/factura-cert.service.d/zz-test.conf
systemctl daemon-reload
systemctl start factura-cert.service >/dev/null 2>&1
sleep 3
AP=$(wc -l < "$ALOG" 2>/dev/null || echo 0)
rm -rf /run/systemd/system/factura-cert.service.d /run/.m14_04_test.conf
systemctl daemon-reload
systemctl reset-failed factura-cert.service >/dev/null 2>&1
[ "$AP" -gt "$AV" ] \
  && ok "un échec provoqué déclenche bien une nouvelle alerte" \
  || ko "un échec provoqué n'a produit aucune alerte : vérifie OnFailure= \
et que factura-alerte@ écrit bien dans $ALOG"

# --- 6. le rapport écrit ----------------------------------------------
if [ -s "$RAP" ]; then
  ok "rapport alerte.md présent"
  grep -qiE 'systemd|unité|unite|hors' "$RAP" \
    && ok "point 6 : le rapport explique le lancement hors systemd" \
    || ko "le rapport n'explique pas pourquoi OnFailure ne joue pas quand \
on lance le script à la main"
  grep -qiE 'alerte.*(échou|echou|fail)|boucle|récursi|recursi' "$RAP" \
    && ok "point 6 : le cas de l'unité d'alerte en échec est traité" \
    || ko "le rapport ne dit pas ce qui se passe si l'unité d'alerte \
échoue elle-même"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
