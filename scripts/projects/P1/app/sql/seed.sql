-- Factura — données de démonstration (projet A du workbook)
-- À exécuter APRÈS schema.sql, dans la base « factura ».
-- Ces factures sont créées en attente (pending) mais ne sont PAS dans la
-- file Redis : le worker ne les traitera que si tu les remets en file via
-- POST /invoices/<id>/requeue (voir tools/factura-smoke.sh --requeue).

INSERT INTO invoices (number, customer, amount_cents, currency)
VALUES
    (next_invoice_number(), 'Boulangerie Martin',      12990, 'EUR'),
    (next_invoice_number(), 'Garage Dupont & Fils',    84500, 'EUR'),
    (next_invoice_number(), 'Cabinet Lefevre',         230000, 'EUR'),
    (next_invoice_number(), 'Atelier Bois & Cie',      15750, 'EUR'),
    (next_invoice_number(), 'Pharmacie du Centre',     6120, 'EUR')
ON CONFLICT (number) DO NOTHING;
