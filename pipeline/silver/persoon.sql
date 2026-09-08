-- target: silver_persoon

USE CATALOG workspace;
USE SCHEMA tweedekamer;

CREATE TABLE IF NOT EXISTS silver_persoon (
  id STRING NOT NULL COMMENT 'Uniek identificatienummer (GUID) van een Persoon.',
  nummer INT COMMENT 'Intern identificatienummer van een Persoon.',
  titels STRING COMMENT 'Titels van een Persoon.',
  initialen STRING COMMENT 'Initialen van een Persoon.',
  tussenvoegsel STRING COMMENT 'Tussenvoegsel van een Persoon.',
  achternaam STRING COMMENT 'Achternaam van een Persoon.',
  voornamen STRING COMMENT 'Voornamen van een Persoon.',
  roepnaam STRING COMMENT 'Roepnaam van een Persoon.',
  geslacht STRING COMMENT 'Geslacht van een Persoon (bijv. man, vrouw).',
  functie STRING COMMENT 'Functie die een Persoon uitoefent (bijv. Tweede Kamerlid, Eerste Kamerlid).',
  geboortedatum DATE COMMENT 'Geboortedatum van een Persoon.',
  geboorteplaats STRING COMMENT 'Geboorteplaats van een Persoon.',
  geboorteland STRING COMMENT 'Geboorteland van een Persoon.',
  overlijdensdatum DATE COMMENT 'Overlijdensdatum van een Persoon.',
  overlijdensplaats STRING COMMENT 'Overlijdensplaats van een Persoon.',
  woonplaats STRING COMMENT 'Woonplaats van een Persoon.',
  land STRING COMMENT 'Land waar een persoon verblijft.',
  fractielabel STRING COMMENT 'Fractie waartoe een Persoon behoort. Wordt alleen gevuld als de waarde van functie = Eerste Kamerlid.',
  content_type STRING COMMENT 'Bestandsformaat van de portretfoto van een Persoon.',
  content_length INT COMMENT 'Bestandsgrootte van de portretfoto van een Persoon.',
  enclosure_link STRING COMMENT 'URL naar de portretfoto.',
  gewijzigd_op TIMESTAMP COMMENT 'Datum en tijd waarop het bronsysteem een Persoon heeft aangemaakt of aangepast.',
  api_gewijzigd_op TIMESTAMP COMMENT 'Datum en tijd waarop de toevoeging of laatste wijziging van een Persoon zichtbaar is geworden in het gegevensmagazijn.',
  verwijderd BOOLEAN COMMENT 'Geeft aan of een Persoon is verwijderd.',
  ingested_at TIMESTAMP COMMENT 'Tijdstip waarop het record is ingelezen en opgeslagen.',
  CONSTRAINT pk_silver_persoon PRIMARY KEY (id)
)
USING DELTA
COMMENT 'Tabel met opgeschoonde en gededupliceerde persoonsgegevens.';

-- Helper function to extract @nil fields safely
CREATE OR REPLACE TEMPORARY FUNCTION clean_nil(v VARIANT)
RETURNS VARIANT
RETURN CASE 
  WHEN v:['@nil'] IS NOT NULL THEN NULL 
  ELSE v 
END;

MERGE INTO silver_persoon AS target
USING (
  SELECT
    entry:content:persoon['@id']::STRING AS id,
    entry:content:persoon:nummer::INT AS nummer,
    clean_nil(entry:content:persoon:titels)::STRING AS titels,
    clean_nil(entry:content:persoon:initialen)::STRING AS initialen,
    clean_nil(entry:content:persoon:tussenvoegsel)::STRING AS tussenvoegsel,
    clean_nil(entry:content:persoon:achternaam)::STRING AS achternaam,
    clean_nil(entry:content:persoon:voornamen)::STRING AS voornamen,
    clean_nil(entry:content:persoon:roepnaam)::STRING AS roepnaam,
    clean_nil(entry:content:persoon:geslacht)::STRING AS geslacht,
    clean_nil(entry:content:persoon:functie)::STRING AS functie,
    clean_nil(entry:content:persoon:geboortedatum)::DATE AS geboortedatum,
    clean_nil(entry:content:persoon:geboorteplaats)::STRING AS geboorteplaats,
    clean_nil(entry:content:persoon:geboorteland)::STRING AS geboorteland,
    clean_nil(entry:content:persoon:overlijdensdatum)::DATE AS overlijdensdatum,
    clean_nil(entry:content:persoon:overlijdensplaats)::STRING AS overlijdensplaats,
    clean_nil(entry:content:persoon:woonplaats)::STRING AS woonplaats,
    clean_nil(entry:content:persoon:land)::STRING AS land,
    clean_nil(entry:content:persoon:fractielabel)::STRING AS fractielabel,
    entry:content:persoon:['@contentType']::STRING AS content_type,
    entry:content:persoon:['@contentLength']::INT AS content_length,
    get(FILTER(entry:link::ARRAY<VARIANT>, x -> x:['@rel']::STRING = 'enclosure'), 0):['@href']::STRING AS enclosure_link,
    clean_nil(entry:content:persoon:['@bijgewerkt'])::TIMESTAMP AS gewijzigd_op,
    clean_nil(entry:updated)::TIMESTAMP AS api_gewijzigd_op,
    clean_nil(entry:content:persoon:['@verwijderd'])::BOOLEAN AS verwijderd,
    ingested_at
  FROM bronze_opendata_api
  WHERE entry:category:['@term']::STRING = 'persoon'
  -- Watermark filter: scans only newly ingested raw XML records
  AND ingested_at > COALESCE(
    (SELECT MAX(ingested_at) FROM silver_persoon), 
    '1900-01-01'::TIMESTAMP
  )
  -- Window function to remove duplicates
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY 
      entry:content:persoon['@id']::STRING
    ORDER BY 
      clean_nil(entry:content:persoon:['@bijgewerkt'])::TIMESTAMP DESC NULLS LAST,
      clean_nil(entry:updated)::TIMESTAMP DESC NULLS LAST,
      ingested_at DESC
  ) = 1
 ) AS source
ON target.id = source.id
-- Remove from Silver if marked as deleted in API
WHEN MATCHED AND source.verwijderd = TRUE THEN DELETE
-- Update active Silver records when mutations arrive
WHEN MATCHED AND (source.verwijderd = FALSE OR source.verwijderd IS NULL) THEN UPDATE SET *
-- Insert new person records
WHEN NOT MATCHED AND (source.verwijderd = FALSE OR source.verwijderd IS NULL) THEN INSERT *;

