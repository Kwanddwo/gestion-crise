CREATE TABLE IF NOT EXISTS clients (id serial PRIMARY KEY, nom text, email text, ville text);
INSERT INTO clients (nom, email, ville)
SELECT 'Client ' || g, 'client' || g || '@example.test', (ARRAY['Paris','Lyon','Lille','Nantes'])[1 + g % 4]
FROM generate_series(1, 50) g
WHERE NOT EXISTS (SELECT 1 FROM clients);
GRANT SELECT ON clients TO api;
