-- gold_model.sql (DuckDB) - sterontwerp Politieke Loopbaan Data Warehouse
-- Draaien vanuit de hoofdmap van de repo, op een verbinding waarop de EDA-database is gekoppeld:
--     ATTACH 'tweedekamer.duckdb' AS src (READ_ONLY)
-- gold_export.py doet dit automatisch. Silver wordt nooit aangepast, de gold-tabellen worden in het geheugen gebouwd.
-- Staging: vijf kleine CSV's in staging/, gemaakt in het EDA-notebook (regex-indeling van opleiding en loopbaan, plaatsmatching).
-- Volgorde: staging, dimensies, feiten, en als laatste dim_persoon (die gebruikt de feiten voor tellingen en niveau)
-- Let op: gebruik geen puntkomma's in commentaar of tekst, het script wordt op een puntkomma gesplitst.
-- Geeft een join een type-fout (UUID tegen tekst)? Cast dan beide kanten met CAST(x AS VARCHAR).

-- ============================ STAGING ============================
CREATE OR REPLACE TEMP VIEW stg_correcties AS SELECT * FROM read_csv_auto('staging/stg_correcties.csv', header = true);
-- stg_plaats: de statusteksten uit Python worden hier teruggebracht tot vijf vaste waarden
CREATE OR REPLACE TEMP VIEW stg_plaats AS
SELECT id,
       geboorte_gemeentecode,
       woon_gemeentecode,
       CASE WHEN plaats_status IS NULL THEN 'niet bepaald'
            WHEN plaats_status LIKE 'gematcht%' THEN 'gematcht'
            WHEN plaats_status LIKE 'geen plaats%' OR plaats_status = 'niet ingevuld' THEN 'niet ingevuld'
            WHEN plaats_status LIKE 'niet eenduidig%' THEN 'niet eenduidig'
            ELSE 'niet gevonden' END AS geboorte_status,
       CASE WHEN woon_status IS NULL THEN 'niet bepaald'
            WHEN woon_status LIKE 'gematcht%' THEN 'gematcht'
            WHEN woon_status LIKE 'geen plaats%' OR woon_status = 'niet ingevuld' THEN 'niet ingevuld'
            WHEN woon_status LIKE 'niet eenduidig%' THEN 'niet eenduidig'
            ELSE 'niet gevonden' END AS woon_status
FROM read_csv_auto('staging/stg_plaats.csv', header = true);
CREATE OR REPLACE TEMP VIEW stg_onderwijs  AS SELECT * FROM read_csv_auto('staging/stg_onderwijs.csv', header = true);
CREATE OR REPLACE TEMP VIEW stg_loopbaan   AS SELECT * FROM read_csv_auto('staging/stg_loopbaan.csv', header = true);
CREATE OR REPLACE TEMP VIEW stg_cbs        AS SELECT * FROM read_csv_auto('staging/stg_cbs.csv', header = true);

CREATE SCHEMA IF NOT EXISTS gold;



-- ============================ DIMENSIES ============================

-- grain: een gemeente (indeling 1 januari 2026), uit CBS-tabel 86312NED
CREATE OR REPLACE TABLE gold.dim_gemeente AS
SELECT DISTINCT trim(Code_3) AS gemeentecode,
                trim(Naam_2) AS gemeente,
                trim(Code_5) AS provinciecode,
                trim(Naam_4) AS provincie,
                trim(Naam_6) AS landsdeel
FROM stg_cbs;


-- grain: een opleidingsniveau (rang alleen voor niveaus die meetellen voor het hoogste voltooide niveau)
CREATE OR REPLACE TABLE gold.dim_opleidingsniveau AS
SELECT * FROM (VALUES
    ('basisonderwijs', 0,    'Basisonderwijs'),
    ('vo',             1,    'Voortgezet onderwijs'),
    ('mbo',            2,    'MBO'),
    ('hbo',            3,    'HBO'),
    ('wo',             4,    'WO'),
    ('promotie',       5,    'Promotie'),
    ('cursus',         NULL, 'Cursus of training (telt niet mee)'),
    ('niet_ingedeeld', NULL, 'Niet ingedeeld'),
    ('onbekend',       NULL, 'Onbekend')
) AS t(niveau, rang, omschrijving);


-- grain: een sector. De vlaggen leggen vast wat meetelt als werk buiten de politiek
CREATE OR REPLACE TABLE gold.dim_sector AS
SELECT sector, binnen_politiek, onduidelijk,
       (NOT binnen_politiek AND sector NOT IN ('onbekend', 'niet_ingedeeld')) AS telt_buiten_bovengrens,
       (NOT binnen_politiek AND NOT onduidelijk AND sector NOT IN ('onbekend', 'niet_ingedeeld')) AS telt_buiten_zeker
FROM (VALUES
    ('kamerlidmaatschap',                          TRUE,  FALSE),
    ('politiek_ondersteuning',                     TRUE,  FALSE),
    ('politiek_bestuur',                           TRUE,  FALSE),
    ('media_communicatie',                         FALSE, FALSE),
    ('juridisch',                                  FALSE, FALSE),
    ('onderwijs_wetenschap',                       FALSE, FALSE),
    ('zorg',                                       FALSE, FALSE),
    ('overheid',                                   FALSE, FALSE),
    ('maatschappelijk',                            FALSE, FALSE),
    ('veiligheid_defensie',                        FALSE, FALSE),
    ('bedrijfsleven en overige organisaties',      FALSE, FALSE),
    ('bestuur_toezicht_onvoldoende_sectorcontext', FALSE, TRUE),
    ('overig_onvoldoende_sectorcontext',           FALSE, TRUE),
    ('onbekend',                                   FALSE, FALSE),
    ('niet_ingedeeld',                             FALSE, FALSE)
) AS t(sector, binnen_politiek, onduidelijk);


-- grain: een fractie (partij)
CREATE OR REPLACE TABLE gold.dim_fractie AS
SELECT id AS fractie_id, afkorting, naam_nl
FROM src.silver.fractie;


-- grain: een kalenderjaar
CREATE OR REPLACE TABLE gold.dim_jaar AS
SELECT y AS jaar, (y // 10) * 10 AS decennium
FROM range(1750, 2031) AS t(y);


-- ============================ FEITEN ============================

-- grain: een opleidingsrij
CREATE OR REPLACE TABLE gold.fact_opleiding AS
SELECT o.id AS opleiding_id,
       o.persoon_id,
       s.categorie AS niveau,
       s.bron AS niveau_bron,
       s.status AS voltooid_status,
       (s.status = 'voltooid') AS is_voltooid,
       year(TRY_CAST(o.van AS DATE)) AS jaar_van,
       year(TRY_CAST(o.tot_en_met AS DATE)) AS jaar_tot,
       o.instelling
FROM src.silver.persoon_onderwijs o
JOIN stg_onderwijs s ON s.id = o.id
WHERE o.persoon_id IN (SELECT id FROM src.silver.persoon);


-- grain: een loopbaanrij
CREATE OR REPLACE TABLE gold.fact_loopbaan AS
SELECT l.id AS loopbaan_id,
       l.persoon_id,
       s.sector,
       year(TRY_CAST(l.van AS DATE)) AS jaar_van,
       year(TRY_CAST(l.tot_en_met AS DATE)) AS jaar_tot,
       l.functie,
       l.werkgever
FROM src.silver.persoon_loopbaan l
JOIN stg_loopbaan s ON s.id = l.id
WHERE l.persoon_id IN (SELECT id FROM src.silver.persoon);


-- ============================ DIM_PERSOON ============================

-- grain: een persoon. Bevat ook de afgeleide kenmerken (leeftijd, fractie, opleiding, loopbaan, geografie en dekkingsvlaggen)
-- Handmatige correcties komen uit stg_correcties en gelden alleen waar de bron leeg is
-- Peildatum voor leeftijd_nu: 2026-10-08
CREATE OR REPLACE TABLE gold.dim_persoon AS
WITH basis AS (
    SELECT p.id AS persoon_id,
           p.achternaam, p.tussenvoegsel, p.roepnaam, p.initialen,
           p.geslacht, p.functie,
           COALESCE(TRY_CAST(p.geboortedatum AS DATE), TRY_CAST(c.geboortedatum AS DATE)) AS geboortedatum,
           TRY_CAST(p.overlijdensdatum AS DATE) AS overlijdensdatum,
           (c.persoon_id IS NOT NULL) AS handmatig_aangevuld
    FROM src.silver.persoon p
    LEFT JOIN stg_correcties c ON c.persoon_id = p.id
), periode AS (
    SELECT fzp.persoon_id,
           f.id AS fractie_id,
           year(TRY_CAST(fzp.van AS DATE)) AS start_jaar,
           ROW_NUMBER() OVER (PARTITION BY fzp.persoon_id
                              ORDER BY fzp.van ASC, fzp.tot_en_met ASC NULLS LAST) AS rn_eerste,
           ROW_NUMBER() OVER (PARTITION BY fzp.persoon_id
                              ORDER BY fzp.van DESC, fzp.tot_en_met DESC NULLS FIRST) AS rn_laatste
    FROM src.silver.fractie_zetel_persoon fzp
    JOIN src.silver.fractie_zetel fz ON fz.id = fzp.fractie_zetel_id
    JOIN src.silver.fractie f ON f.id = fz.fractie_id
    WHERE fzp.persoon_id IN (SELECT id FROM src.silver.persoon)
), eerste AS (
    SELECT persoon_id, fractie_id, start_jaar FROM periode WHERE rn_eerste = 1
), laatste AS (
    SELECT persoon_id, fractie_id FROM periode WHERE rn_laatste = 1
), opl AS (
    SELECT persoon_id, count(*) AS n_opleidingen
    FROM gold.fact_opleiding GROUP BY persoon_id
), hoogste AS (
    SELECT persoon_id, niveau, niveau_bron
    FROM (
        SELECT o.persoon_id, o.niveau, o.niveau_bron,
               ROW_NUMBER() OVER (PARTITION BY o.persoon_id
                                  ORDER BY n.rang DESC, (o.niveau_bron = 'tekst') DESC, o.opleiding_id) AS rn
        FROM gold.fact_opleiding o
        JOIN gold.dim_opleidingsniveau n ON n.niveau = o.niveau
        WHERE o.is_voltooid AND n.rang IS NOT NULL
    ) WHERE rn = 1
), lb AS (
    SELECT l.persoon_id,
           count(*) AS n_loopbaanrijen,
           sum(CASE WHEN s.telt_buiten_bovengrens THEN 1 ELSE 0 END) AS n_buiten_politiek,
           sum(CASE WHEN s.telt_buiten_zeker THEN 1 ELSE 0 END) AS n_buiten_zeker
    FROM gold.fact_loopbaan l
    JOIN gold.dim_sector s ON s.sector = l.sector
    GROUP BY l.persoon_id
)
SELECT b.persoon_id,
       trim(concat_ws(' ', COALESCE(b.roepnaam, b.initialen), b.tussenvoegsel, b.achternaam)) AS naam,
       b.geslacht,
       b.functie,
       (b.functie = 'Eerste Kamerlid') AS is_eerste_kamerlid,
       b.geboortedatum,
       year(b.geboortedatum) AS geboortejaar,
       (year(b.geboortedatum) // 10) * 10 AS geboortedecennium,
       b.overlijdensdatum,
       b.handmatig_aangevuld,
       CASE WHEN b.overlijdensdatum IS NOT NULL THEN 'overleden (datum bekend)'
            WHEN b.geboortedatum IS NULL THEN 'onbekend (geen geboortedatum)'
            WHEN year(b.geboortedatum) >= 1930 THEN 'aangenomen in leven'
            ELSE 'onbekend' END AS levensstatus,
       CASE WHEN b.functie = 'Tweede Kamerlid' AND b.geboortedatum IS NOT NULL
            THEN round(date_diff('day', b.geboortedatum, DATE '2026-10-08') / 365.25, 1) END AS leeftijd_nu,
       e.start_jaar AS start_jaar_fractie,
       e.start_jaar - year(b.geboortedatum) AS leeftijd_aantreden,
       (e.persoon_id IS NOT NULL) AS heeft_fractie,
       e.fractie_id AS fractie_eerste_id,
       la.fractie_id AS fractie_laatste_id,
       COALESCE(o.n_opleidingen, 0) AS n_opleidingen,
       h.niveau AS opleiding_hoogste,
       h.niveau_bron AS opleiding_hoogste_bron,
       CASE WHEN h.niveau IS NOT NULL THEN 'niveau bepaald'
            WHEN COALESCE(o.n_opleidingen, 0) > 0 THEN 'geregistreerd, geen voltooid niveau af te leiden'
            ELSE 'geen opleiding geregistreerd' END AS opleiding_status,
       COALESCE(lb.n_loopbaanrijen, 0) AS n_loopbaanrijen,
       COALESCE(lb.n_buiten_politiek, 0) AS n_buiten_politiek,
       COALESCE(lb.n_buiten_zeker, 0) AS n_buiten_zeker,
       sp.geboorte_gemeentecode,
       sp.geboorte_status,
       sp.woon_gemeentecode,
       sp.woon_status,
       (b.geboortedatum IS NOT NULL) AS heeft_geboortedatum,
       (sp.geboorte_status NOT IN ('niet ingevuld', 'niet bepaald')) AS heeft_geboorteplaats,
       (sp.woon_status NOT IN ('niet ingevuld', 'niet bepaald')) AS heeft_woonplaats,
       (COALESCE(o.n_opleidingen, 0) > 0) AS heeft_opleidingsrij,
       (COALESCE(lb.n_loopbaanrijen, 0) > 0) AS heeft_loopbaanrij
FROM basis b
LEFT JOIN eerste e   ON e.persoon_id  = b.persoon_id
LEFT JOIN laatste la ON la.persoon_id = b.persoon_id
LEFT JOIN opl o      ON o.persoon_id  = b.persoon_id
LEFT JOIN hoogste h  ON h.persoon_id  = b.persoon_id
LEFT JOIN lb         ON lb.persoon_id = b.persoon_id
LEFT JOIN stg_plaats sp ON sp.id = b.persoon_id;