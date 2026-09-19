#!/usr/bin/env bash
# check_M21_05.sh [vX.Y.Z] — vérifie le défi D21 (chaîne de release)
# À lancer sur lab-ops, en tant que mathieu. Version par défaut : v1.0.0.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
VER="${1:-v1.0.0}"
echo "== Vérification D21 ($VER) =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab21"
API=http://10.10.10.14:3000/api/v1
TOKEN=$(tr -d '[:space:]' < "$BASE/.gitea-token" 2>/dev/null || true)
REPO="$API/repos/mathieu/factura"
REG=http://10.10.10.14:5000
REGAUTH='mathieu:Factura-Reg-2026'
DEPOT="$BASE/factura"
api() { curl -s -m 10 -H "Authorization: token $TOKEN" "$@"; }
dig() { curl -sI -m 5 -u "$REGAUTH" \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  "$REG/v2/factura/manifests/$1" | grep -i docker-content-digest \
  | tr -d '\r' | awk '{print $2}'; }

# --- 1. tag Git et image promue ----------------------------------------------
git -C "$DEPOT" fetch -q --tags origin 2>/dev/null
SHA=$(git -C "$DEPOT" rev-parse --short=12 "$VER^{commit}" 2>/dev/null)
[ -n "$SHA" ] && ok "tag Git $VER → $SHA" || ko "tag Git $VER absent (git tag -a $VER && git push origin $VER)"
git -C "$DEPOT" branch -r --contains "$VER" 2>/dev/null | grep -q 'origin/main' \
  && ok "$VER pointe sur un commit de main" || ko "$VER ne pointe pas sur main"
DV=$(dig "$VER"); DS=$(dig "${SHA:-x}"); DM=$(dig "${VER%.*}")
[ -n "$DV" ] && ok "image factura:$VER dans le registre" \
  || ko "pas d'image taguée $VER (job promote)"
[ -n "$DV" ] && [ "$DV" = "$DS" ] && ok "digest $VER == digest $SHA (pas de rebuild)" \
  || ko "digest de $VER différent de celui de $SHA : l'image a été reconstruite ?"
[ -n "$DM" ] && [ "$DM" = "$DV" ] && ok "tag mineur ${VER%.*} sur le même digest" \
  || ko "tag ${VER%.*} absent ou sur un autre digest"

# --- 2. changelog et release --------------------------------------------------
CL=$(api "$REPO/raw/CHANGELOG.md")
printf '%s' "$CL" | grep -q "^## $VER" && ok "CHANGELOG.md sur main contient ## $VER" \
  || ko "CHANGELOG.md sur main sans section ## $VER (commit du pipeline ?)"
LASTMSG=$(git -C "$DEPOT" log -1 --format=%s origin/main 2>/dev/null)
printf '%s' "$LASTMSG" | grep -qiE '\[(skip ci|ci skip|no ci|skip actions|actions skip)\]' \
  && ok "dernier commit de main marqué pour ne pas redéclencher ci" \
  || note "dernier commit de main : « $LASTMSG » (le commit du changelog doit contenir [skip ci])"
R=$(api "$REPO/releases/tags/$VER")
if printf '%s' "$R" | grep -q '"tag_name"'; then
  ok "release Gitea $VER existe"
  printf '%s' "$R" | grep -q 'sha256:' && ok "la release mentionne le digest de l'image" \
    || ko "la release doit citer le digest sha256 de l'image"
else
  ko "release Gitea $VER absente (POST /releases)"
fi

# --- 3. workflows -----------------------------------------------------------
WR=$(api "$REPO/raw/.gitea/workflows/release.yaml")
printf '%s' "$WR" | python3 - <<'EOF' && ok "release.yaml : déclenché sur tags v*, jobs guard/promote/changelog/release" \
  || ko "release.yaml : attendu on.push.tags v*, jobs guard, promote, changelog, release"
import sys, yaml
w = yaml.safe_load(sys.stdin); on = w.get("on") or w.get(True)
assert any(t.startswith("v") for t in on["push"]["tags"]) and set(on) == {"push"}
assert {"guard", "promote", "changelog", "release"} <= set(w["jobs"])
assert "docker build" not in str(w["jobs"]["promote"]["steps"])
EOF
WP=$(api "$REPO/raw/.gitea/workflows/promote.yaml")
printf '%s' "$WP" | python3 - <<'EOF' && ok "promote.yaml : workflow_dispatch, inputs version+confirm, gardé par actor" \
  || ko "promote.yaml : attendu workflow_dispatch avec inputs version et confirm, if sur gitea.actor"
import sys, yaml
w = yaml.safe_load(sys.stdin); on = w.get("on") or w.get(True)
i = on["workflow_dispatch"]["inputs"]
assert "version" in i and "confirm" in i
assert any("actor" in str(j.get("if", "")) for j in w["jobs"].values())
EOF

# --- 4. scripts et rapport ------------------------------------------------
[ -x "$DEPOT/scripts/changelog.sh" ] && ok "scripts/changelog.sh exécutable" \
  || ko "scripts/changelog.sh absent ou non exécutable"
RC="$DEPOT/scripts/release-check.sh"
if [ -x "$RC" ]; then
  if bash "$RC" "$VER" >/dev/null 2>&1; then ok "release-check.sh $VER sort en 0"
  else ko "release-check.sh $VER sort en échec : lis son rapport"; fi
else
  ko "scripts/release-check.sh absent"
fi
[ -s "$BASE/rapports/release.md" ] && ok "rapports/release.md présent" \
  || ko "rapports/release.md absent"
grep -qiE 'dora|lead time|MTTR' "$BASE/rapports/release.md" 2>/dev/null \
  && ok "release.md contient les métriques DORA" \
  || ko "release.md doit inclure les métriques DORA (dora.sh)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
