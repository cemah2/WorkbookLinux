-- Schéma Factura v2 (exécuté au premier démarrage de PostgreSQL)
CREATE TABLE IF NOT EXISTS factures (
  id          SERIAL PRIMARY KEY,
  client      TEXT NOT NULL,
  montant_ht  NUMERIC(12,2) NOT NULL,
  montant_ttc NUMERIC(12,2) NOT NULL,
  statut      TEXT NOT NULL DEFAULT 'nouvelle',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS factures_statut_idx ON factures (statut);
INSERT INTO factures (client, montant_ht, montant_ttc, statut)
SELECT 'Client demo ' || g, 100 * g, 120 * g, 'traitee'
FROM generate_series(1, 5) AS g
WHERE NOT EXISTS (SELECT 1 FROM factures);
