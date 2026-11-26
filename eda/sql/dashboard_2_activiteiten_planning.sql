
SELECT
    r.id AS reservering_id,
    a.id AS activiteit_id,
    a.datum AS datum,
    a.soort AS activiteitssoort,
    a.onderwerp AS activiteit,
    a.status AS status,
    a.besloten AS besloten,
    z.naam AS vergaderzaal

FROM silver.reservering AS r

-- Koppel iedere reservering aan een activiteit
LEFT JOIN silver.activiteit AS a
    ON r.activiteit_id = a.id

-- Koppel iedere reservering aan een vergaderzaal
LEFT JOIN silver.zaal AS z
    ON r.zaal_id = z.id

-- Sorteer de gegevens op datum
ORDER BY a.datum
