#!/usr/bin/env bash
# factura-smoke.sh — test de fumée de l'API Factura.
# Usage : factura-smoke.sh [-u URL] [-n NOMBRE] [--requeue]
#   -u URL      base de l'API (défaut : http://127.0.0.1:8000 ;
#               derrière nginx : https://factura.lab.local/api)
#   -n NOMBRE   nombre de factures à créer (défaut : 3)
#   --requeue   remet en file toutes les factures « pending » ou « error »
#   -k          ignore la vérification TLS (curl -k)
set -euo pipefail

URL="http://127.0.0.1:8000"; N=3; REQUEUE=0; CURL_OPTS=(-sS --max-time 5)
while [ $# -gt 0 ]; do
  case "$1" in
    -u) URL="$2"; shift 2 ;;
    -n) N="$2"; shift 2 ;;
    --requeue) REQUEUE=1; shift ;;
    -k) CURL_OPTS+=(-k); shift ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
URL="${URL%/}"

command -v jq >/dev/null || { echo "jq est requis (apt install jq)" >&2; exit 1; }

echo "== /health"
curl "${CURL_OPTS[@]}" "$URL/health" | jq -c .

if [ "$REQUEUE" -eq 1 ]; then
  echo "== remise en file des factures pending/error"
  curl "${CURL_OPTS[@]}" "$URL/invoices?limit=500" \
    | jq -r '.[] | select(.status != "exported") | .id' \
    | while read -r id; do
        curl "${CURL_OPTS[@]}" -X POST "$URL/invoices/$id/requeue" | jq -c .
      done
fi

CLIENTS=("Boulangerie Martin" "Garage Dupont" "Cabinet Lefevre" \
         "Atelier Bois" "Pharmacie du Centre" "Studio Photo Ravel")
echo "== création de $N facture(s)"
for i in $(seq 1 "$N"); do
  client="${CLIENTS[$((RANDOM % ${#CLIENTS[@]}))]}"
  amount="$((RANDOM % 900 + 20)).$((RANDOM % 90 + 10))"
  curl "${CURL_OPTS[@]}" -X POST -H 'Content-Type: application/json' \
    -d "{\"customer\":\"$client\",\"amount\":$amount}" \
    "$URL/invoices" | jq -c .
done

echo "== attente de l'export (10 s max)"
for _ in $(seq 1 10); do
  sleep 1
  pending=$(curl "${CURL_OPTS[@]}" "$URL/invoices?limit=$N" \
            | jq '[.[] | select(.status == "pending")] | length')
  [ "$pending" -eq 0 ] && break
done
echo "== état des $N dernières factures"
curl "${CURL_OPTS[@]}" "$URL/invoices?limit=$N" \
  | jq -r '.[] | "\(.number)  \(.status)  \(.pdf_path // "-")"'
