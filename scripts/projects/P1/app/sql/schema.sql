-- Factura — schéma de la base (projet A du workbook)
-- À exécuter dans la base « factura », connecté en tant que factura_app :
--   psql -h 127.0.0.1 -U factura_app -d factura -f schema.sql
-- Idempotent : rejouable sans effet de bord.

CREATE SEQUENCE IF NOT EXISTS invoice_number_seq START 1000;

CREATE TABLE IF NOT EXISTS invoices (
    id            bigserial PRIMARY KEY,
    number        text        NOT NULL UNIQUE,
    customer      text        NOT NULL,
    amount_cents  integer     NOT NULL CHECK (amount_cents >= 0),
    currency      char(3)     NOT NULL DEFAULT 'EUR',
    status        text        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'exported', 'error')),
    pdf_path      text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    exported_at   timestamptz
);

CREATE INDEX IF NOT EXISTS invoices_status_idx ON invoices (status);
CREATE INDEX IF NOT EXISTS invoices_created_idx ON invoices (created_at);

-- Numéro de facture : FAC-<année>-<compteur sur 6 chiffres>
CREATE OR REPLACE FUNCTION next_invoice_number() RETURNS text
LANGUAGE sql AS $$
    SELECT 'FAC-' || to_char(now(), 'YYYY') || '-'
           || lpad(nextval('invoice_number_seq')::text, 6, '0');
$$;
