#!/usr/bin/env bash
# break_M27_04.sh — panne BF27.4 : un except nu qui renvoie un faux OK
# Dépose ~/lab27/bf4/verif-site.py et sa liste de sites.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab27"
BF="$BASE/bf4"
mkdir -p /root/.breakfix-backup

rm -rf "$BF"
mkdir -p "$BF"
cat > "$BF/sites.txt" <<'EOF'
http://10.10.10.11/
http://10.10.10.14:3000/
http://10.10.10.11:8099/
http://10.10.10.99/
EOF

cat > "$BF/verif-site.py" <<'EOF'
#!/usr/bin/env python3
"""verif-site.py — vérifie que les sites de sites.txt répondent.
Sort en 0 si tout va bien, 2 sinon."""
import sys
import urllib.request


def verifier(url):
    try:
        with urllib.request.urlopen(url, timeout=2) as rep:
            if rep.status != 200:
                print(f"KO {url} : {rep.status}")
                sys.exit(2)
            print(f"OK {url}")
    except:
        pass
    return True


with open(sys.argv[1]) as f:
    urls = [l.strip() for l in f if l.strip()]

for url in urls:
    verifier(url)

print("tous les sites OK")
sys.exit(0)
EOF
chmod 755 "$BF/verif-site.py"
chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : "$BF/verif-site.py $BF/sites.txt" termine sur
"tous les sites OK" avec le code 0, alors que deux des quatre URL ne
répondent pas. La supervision qui l'appelle n'a jamais alerté.
EOF
