#!/usr/bin/env bash
# setup_M19_perf.sh — dépose le script « lent » du lab L19.6 et ses données
# À lancer avec sudo sur lab-web, après setup_M19.sh. Idempotent : la copie
# de référence (/opt/vitrine/perf) est réécrite, la copie de travail de
# l'apprenant (~/lab19/perf) n'est PAS écrasée si elle existe déjà.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

REF=/opt/vitrine/perf
BASE="$LAB_HOME/lab19/perf"
mkdir -p "$REF" "$BASE" "$LAB_HOME/lab19/rapports"

# ---------------------------------------------------------------------
# 1. Le script à profiler (volontairement lent : recherche linéaire)
# ---------------------------------------------------------------------
cat > "$REF/rapport-tva.py" <<'PYEOF'
#!/usr/bin/env python3
"""rapport-tva.py — TVA due par client à partir de factures.csv.

Usage : rapport-tva.py [factures.csv] [clients.csv]
Sortie : une ligne par client (nom, total HT, TVA due), triée par nom.
Ce script est le sujet du lab L19.6 : il est lent, et c'est voulu.
"""
import csv
import sys


def charger_clients(chemin):
    with open(chemin, newline="") as f:
        return [dict(ligne) for ligne in csv.DictReader(f)]


def charger_factures(chemin):
    with open(chemin, newline="") as f:
        return [dict(ligne) for ligne in csv.DictReader(f)]


def chercher_client(clients, ident):
    """Retrouve un client par identifiant."""
    for client in clients:
        if client["id"] == ident:
            return client
    raise KeyError(ident)


def taux_tva(categorie):
    return {"normal": 0.20, "reduit": 0.055, "inter": 0.10}[categorie]


def calculer(clients, factures):
    totaux = {}
    for facture in factures:
        client = chercher_client(clients, facture["client"])
        montant = float(facture["montant_ht"])
        tva = montant * taux_tva(facture["categorie"])
        nom = client["nom"]
        ht, due = totaux.get(nom, (0.0, 0.0))
        totaux[nom] = (ht + montant, due + tva)
    return totaux


def main():
    fact = sys.argv[1] if len(sys.argv) > 1 else "factures.csv"
    cli = sys.argv[2] if len(sys.argv) > 2 else "clients.csv"
    clients = charger_clients(cli)
    factures = charger_factures(fact)
    totaux = calculer(clients, factures)
    for nom in sorted(totaux):
        ht, due = totaux[nom]
        print("%-12s %12.2f %10.2f" % (nom, ht, due))


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------
# 2. Les données (déterministes : même graine, même fichier)
# ---------------------------------------------------------------------
python3 - "$REF" <<'PYEOF'
import csv
import random
import sys

ref = sys.argv[1]
random.seed(19)
nb_clients, nb_factures = 6000, 40000
with open(f"{ref}/clients.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "nom"])
    for i in range(nb_clients):
        w.writerow(["C%05d" % i, "client%05d" % i])
with open(f"{ref}/factures.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["num", "client", "montant_ht", "categorie"])
    for i in range(nb_factures):
        w.writerow(["F%06d" % i, "C%05d" % random.randrange(nb_clients),
                    "%.2f" % random.uniform(10, 5000),
                    random.choice(["normal", "reduit", "inter"])])
PYEOF
chmod 0755 "$REF/rapport-tva.py"
chmod 0644 "$REF"/*.csv
chown -R root:root "$REF"

# empreinte de la sortie attendue (contrat du lab)
( cd "$REF" && python3 rapport-tva.py | md5sum | cut -d' ' -f1 ) \
  > "$REF/sortie.md5"

# ---------------------------------------------------------------------
# 3. Copie de travail de l'apprenant (jamais écrasée)
# ---------------------------------------------------------------------
for f in rapport-tva.py factures.csv clients.csv; do
  [ -e "$BASE/$f" ] || cp "$REF/$f" "$BASE/$f"
done
chown -R "$LAB_USER:$LAB_USER" "$LAB_HOME/lab19"

command -v perf >/dev/null 2>&1 \
  || echo "  note : perf absent — sudo apt install -y linux-tools-\$(uname -r)"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' \
  || echo "  note : python3 < 3.12, -X perf indisponible (cProfile reste)"

cat <<EOF

Prêt.
  $BASE/rapport-tva.py     script à profiler (copie de travail)
  $BASE/factures.csv       40 000 factures
  $BASE/clients.csv        6 000 clients
  $REF/                    copie de référence + sortie.md5

Essai : cd $BASE && time python3 rapport-tva.py | tail -3
EOF
