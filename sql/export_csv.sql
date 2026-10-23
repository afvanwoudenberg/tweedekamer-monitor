-- Kleine selectie: ongeveer 1 op de 50 documenten (altijd dezelfde selectie)
CREATE OR REPLACE TEMP TABLE selectie AS
SELECT document_id
FROM gold.fact_document_publicatie
WHERE hash(document_id) % 50 = 0;

-- Feitentabellen
COPY (
    SELECT * FROM gold.fact_document_publicatie
    WHERE document_id IN (SELECT document_id FROM selectie)
) TO 'data/fact_document_publicatie.csv' (HEADER, DELIMITER ',');

COPY (
    SELECT * FROM gold.fact_bronvermelding
    WHERE document_id IN (SELECT document_id FROM selectie)
) TO 'data/fact_bronvermelding.csv' (HEADER, DELIMITER ',');

-- Dimensies
COPY (SELECT * FROM gold.dim_documentsoort) TO 'data/dim_documentsoort.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM gold.dim_documenttype) TO 'data/dim_documenttype.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM gold.dim_organisatie) TO 'data/dim_organisatie.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM gold.dim_tijd) TO 'data/dim_tijd.csv' (HEADER, DELIMITER ',');

-- Documenten uit de selectie en de documenten waar zij naar verwijzen (voor de titels)
COPY (
    SELECT * FROM gold.dim_document
    WHERE document_id IN (SELECT document_id FROM selectie)
       OR document_id IN (
            SELECT bron_document_id FROM gold.fact_bronvermelding
            WHERE document_id IN (SELECT document_id FROM selectie)
       )
) TO 'data/dim_document.csv' (HEADER, DELIMITER ',');