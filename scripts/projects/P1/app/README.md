# Factura — sources de l'application (projet A)

Ces fichiers sont déposés par `setup_P1.sh` dans `/usr/local/src/factura/`
sur chaque VM. **Rien n'est installé** : les copier au bon endroit, créer les
comptes, les unités systemd et la configuration est le travail du projet.

```
api/factura_api.py        API Flask (Gunicorn, port 8000 local sur lab-web)
worker/factura_worker.py  worker d'export PDF (lab-web)
sql/schema.sql            schéma PostgreSQL (lab-db)
sql/seed.sql              5 factures de démonstration
www/                      front statique servi par nginx (lab-web)
tools/factura-smoke.sh    test de fumée (crée des factures, attend l'export)
tools/factura-webhook.py  récepteur d'alertes local (lab-ops, port 9999)
requirements.txt          dépendances Python
```

Variables d'environnement lues par l'API et le worker : voir l'en-tête de
chaque fichier Python.
