CREATE SCHEMA IF NOT EXISTS gold;

-- Feitentabel: documenten met publicatiegegevens
-- Alleen document_type = 'Metadata': per versie bestaat ook een 'Metadataowms'-rij met dezelfde datum
CREATE OR REPLACE TABLE gold.fact_document_publicatie AS
SELECT
    d.id AS document_id,
    d.soort,
    m.document_type,
    d.organisatie,
    d.datum,
    m.publicatie_datum AS publicatiedatum,
    DATE_DIFF('day', d.datum, m.publicatie_datum) AS dagen_tot_publicatie,
    v.bestandsgrootte,
    v.versienummer
FROM silver.document d
LEFT JOIN silver.document_versie v ON d.huidige_document_versie_id = v.id
LEFT JOIN silver.document_publicatie_metadata m
    ON m.document_versie_id = v.id AND m.document_type = 'Metadata';

-- Feitentabel: bronvermeldingen
CREATE OR REPLACE TABLE gold.fact_bronvermelding AS
SELECT
    b.document_id,
    b.bron_document_id,
    d.soort AS document_soort,
    s.soort AS bron_document_soort,
    b.relatie_gewijzigd_op
FROM silver.document_bron_document b
LEFT JOIN silver.document d ON b.document_id = d.id
LEFT JOIN silver.document s ON b.bron_document_id = s.id;

-- Dim tabellen
CREATE OR REPLACE TABLE gold.dim_documentsoort AS
SELECT DISTINCT soort FROM silver.document WHERE soort IS NOT NULL;

CREATE OR REPLACE TABLE gold.dim_documenttype AS
SELECT DISTINCT document_type FROM gold.fact_document_publicatie WHERE document_type IS NOT NULL;

CREATE OR REPLACE TABLE gold.dim_organisatie AS
SELECT DISTINCT organisatie FROM silver.document WHERE organisatie IS NOT NULL;

CREATE OR REPLACE TABLE gold.dim_document AS
SELECT id AS document_id, titel FROM silver.document;

CREATE OR REPLACE TABLE gold.dim_tijd AS
SELECT
    CAST(d AS DATE) AS datum,
    YEAR(d) AS jaar,
    MONTH(d) AS maand,
    DAY(d) AS dag,
    QUARTER(d) AS kwartaal,
    WEEKOFYEAR(d) AS weeknummer,
    DAYNAME(d) AS dagnaam,
    ISODOW(d) AS dagnr
FROM (
    SELECT UNNEST(GENERATE_SERIES(min_d, max_d, INTERVAL 1 DAY)) AS d
    FROM (
        SELECT
            CAST(LEAST(MIN(datum), MIN(publicatiedatum)) AS TIMESTAMP) AS min_d,
            CAST(GREATEST(MAX(datum), MAX(publicatiedatum)) AS TIMESTAMP) AS max_d
        FROM gold.fact_document_publicatie
    )
);