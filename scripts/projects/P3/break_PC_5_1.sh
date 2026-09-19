#!/usr/bin/env bash
# break_PC_5_1.sh — ticket PC.5.1 (lab-db) : demande de changement.
# Ne casse rien : dépose le contexte de la demande de compte restreint.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_5_1; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
# Rien à casser. On s'assure juste que la base est là.
sudo -u postgres psql -tAqc "select 1 from pg_database where datname='factura'" \
  | grep -q 1 || { echo "base factura absente : lance setup_P3.sh (rôle db)" >&2
                   exit 1; }
cat <<'EOF'

Demande déposée : le cabinet d'audit « Revizor » a besoin d'un accès en
LECTURE SEULE à la base factura pour la durée de la mission (2 semaines),
depuis lab-adm uniquement. Créer le compte au moindre privilège.
EOF
