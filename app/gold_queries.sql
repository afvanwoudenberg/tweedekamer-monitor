-- Stermodel: persoon, contactgegevens, fractie en fractiezetels
-- Elke query begint met "-- name: <tabelnaam>"; export_gold.py slaat het resultaat op als <tabelnaam>.csv
-- Bron: silver-laag van tweedekamer.duckdb
-- Onbekende waarden: sleutel -1 ('Onbekend'), zodat feiten nooit naar NULL verwijzen.


-- ======================================================================
-- DIMENSIES
-- ======================================================================

-- name: dim_persoon
SELECT
    CAST(id AS VARCHAR)              AS persoon_id,
    nummer,
    titels,
    voornamen,
    tussenvoegsel,
    achternaam,
    roepnaam,
    geslacht,
    initialen,
    functie,
    fractielabel,
    CAST(geboortedatum    AS DATE)   AS geboortedatum,
    CAST(overlijdensdatum AS DATE)   AS overlijdensdatum
FROM silver.persoon
UNION ALL BY NAME
SELECT '-1' AS persoon_id, 'Onbekend' AS achternaam;


-- name: dim_fractie
SELECT
    CAST(id AS VARCHAR)              AS fractie_id,
    nummer,
    afkorting,
    naam_nl,
    naam_en,
    aantal_zetels,
    aantal_stemmen,
    CAST(datum_actief   AS DATE)     AS datum_actief,
    CAST(datum_inactief AS DATE)     AS datum_inactief,
    logo_url
FROM silver.fractie
UNION ALL BY NAME
SELECT '-1' AS fractie_id, 'Onbekend' AS naam_nl, 'Unknown' AS naam_en;


-- name: dim_kanaal
SELECT
    dense_rank() OVER (ORDER BY soort) AS channel_key,
    soort                              AS kanaal
FROM (
    SELECT DISTINCT soort
    FROM silver.persoon_contactinformatie
    WHERE soort IS NOT NULL
)
UNION ALL BY NAME
SELECT -1 AS channel_key, 'Onbekend' AS kanaal;


-- name: dim_soort
SELECT
    dense_rank() OVER (ORDER BY soort, waarde, gewicht) AS soort_id,
    waarde,
    soort,
    gewicht
FROM (
    SELECT DISTINCT waarde, soort, gewicht
    FROM silver.persoon_contactinformatie
)
UNION ALL BY NAME
SELECT -1 AS soort_id, 'Onbekend' AS waarde, 'Onbekend' AS soort;


-- name: dim_datum
WITH bounds AS (
    SELECT min(d) AS d_min, max(d) AS d_max
    FROM (
        SELECT CAST(gewijzigd_op AS DATE) AS d FROM silver.persoon_contactinformatie
        UNION ALL
        SELECT CAST(van          AS DATE) AS d FROM silver.fractie_zetel_persoon
        UNION ALL
        SELECT CAST(tot_en_met   AS DATE) AS d FROM silver.fractie_zetel_persoon
        UNION ALL
        SELECT current_date AS d
    )
    WHERE d IS NOT NULL
)
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER) AS date_key,
    CAST(d AS DATE)                        AS calendar_date,
    strftime(d, '%Y-%m')                   AS month,
    year(d)                                AS year
FROM bounds,
     generate_series(d_min, d_max, INTERVAL 1 DAY) AS t(d)
UNION ALL BY NAME
SELECT -1 AS date_key, 'Onbekend' AS month
UNION ALL BY NAME
SELECT 99991231 AS date_key, 'Nog actief' AS month;   -- tot_en_met is leeg: zetel loopt nog


-- ======================================================================
-- FEITENTABELLEN
-- ======================================================================

-- name: fact_contactgegevens_persoon
-- Grain: één rij per contactgegeven van een persoon.
WITH kanaal AS (
    SELECT dense_rank() OVER (ORDER BY soort) AS channel_key, soort AS kanaal
    FROM (SELECT DISTINCT soort FROM silver.persoon_contactinformatie WHERE soort IS NOT NULL)
),
soort AS (
    SELECT dense_rank() OVER (ORDER BY soort, waarde, gewicht) AS soort_id, waarde, soort, gewicht
    FROM (SELECT DISTINCT waarde, soort, gewicht FROM silver.persoon_contactinformatie)
)
SELECT
    row_number() OVER (ORDER BY c.gewijzigd_op DESC NULLS LAST, c.persoon_id) AS contactgegeven_persoon_key,
    COALESCE(CAST(p.id AS VARCHAR), '-1')                                      AS persoon_id,
    COALESCE(CAST(strftime(CAST(c.gewijzigd_op AS DATE), '%Y%m%d') AS INTEGER), -1) AS date_key,
    COALESCE(k.channel_key, -1)                                                AS channel_key,
    COALESCE(s.soort_id, -1)                                                   AS soort_id,
    1                                                                          AS contact_count
FROM silver.persoon_contactinformatie c
LEFT JOIN silver.persoon p ON p.id = c.persoon_id
LEFT JOIN kanaal k         ON k.kanaal = c.soort
LEFT JOIN soort s          ON s.soort   IS NOT DISTINCT FROM c.soort
                          AND s.waarde  IS NOT DISTINCT FROM c.waarde
                          AND s.gewicht IS NOT DISTINCT FROM c.gewicht
ORDER BY date_key DESC;


-- name: fact_fractie_zetel_persoon
-- Grain: één rij per persoon op een fractiezetel, per periode (van t/m tot_en_met).
-- tot_en_met leeg = zetel loopt nog: date_key 99991231, aantal_dagen telt tot vandaag.
SELECT
    row_number() OVER (ORDER BY zp.van DESC NULLS LAST, zp.id)                  AS fractie_zetel_persoon_key,
    COALESCE(CAST(p.id AS VARCHAR), '-1')                                       AS persoon_id,
    COALESCE(CAST(f.id AS VARCHAR), '-1')                                       AS fractie_id,
    COALESCE(CAST(strftime(CAST(zp.van AS DATE), '%Y%m%d') AS INTEGER), -1)    AS van_date_key,
    CASE WHEN zp.tot_en_met IS NULL THEN 99991231
         ELSE CAST(strftime(CAST(zp.tot_en_met AS DATE), '%Y%m%d') AS INTEGER)
    END                                                                         AS tot_en_met_date_key,
    CAST(z.id AS VARCHAR)                                                       AS fractie_zetel_id,  -- degenerate dimension
    z.gewicht                                                                   AS zetel_gewicht,     -- degenerate dimension
    zp.functie                                                                  AS functie,           -- degenerate dimension
    date_diff('day', CAST(zp.van AS DATE),
              COALESCE(CAST(zp.tot_en_met AS DATE), current_date))              AS aantal_dagen,
    1                                                                           AS zetel_count
FROM silver.fractie_zetel_persoon zp
LEFT JOIN silver.fractie_zetel z ON z.id = zp.fractie_zetel_id
LEFT JOIN silver.fractie f       ON f.id = z.fractie_id
LEFT JOIN silver.persoon p       ON p.id = zp.persoon_id
ORDER BY van_date_key DESC;
