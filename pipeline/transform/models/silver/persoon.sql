{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.persoon',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH links AS (
    SELECT
        _dlt_parent_id,
        MAX(CASE WHEN rel = 'enclosure' THEN href END) AS portret_url
    FROM {{ source('bronze', 'persoon__atom_links') }}
    GROUP BY 1
),

renamed AS (
    SELECT
        p.id,
        p.nummer,
        p.titels,
        p.initialen,
        p.tussenvoegsel,
        p.achternaam,
        p.voornamen,
        p.roepnaam,
        p.geslacht,
        p.functie,
        {{ parse_partial_datum('p.geboortedatum') }} AS geboortedatum_parsed,
        p.geboortedatum AS geboortedatum_ruw,
        p.geboorteplaats,
        p.geboorteland,
        {{ parse_partial_datum('p.overlijdensdatum') }} AS overlijdensdatum_parsed,
        p.overlijdensdatum AS overlijdensdatum_ruw,
        p.overlijdensplaats,
        p.woonplaats,
        p.land,
        p.fractielabel,
        l.portret_url,
        p.content_type,
        CAST(p.content_length AS INTEGER) AS content_length,
        p.verwijderd,
        p.bijgewerkt AS gewijzigd_op,
        p.feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'persoon') }} AS p
    LEFT JOIN links AS l ON p._dlt_id = l._dlt_parent_id
),

incoming AS (
    SELECT * EXCLUDE (geboortedatum_parsed, overlijdensdatum_parsed),
        geboortedatum_parsed.datum AS geboortedatum,
        geboortedatum_parsed.precisie AS geboortedatum_precisie,
        overlijdensdatum_parsed.datum AS overlijdensdatum,
        overlijdensdatum_parsed.precisie AS overlijdensdatum_precisie
    FROM (
        SELECT *
        FROM renamed
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY gewijzigd_op DESC, api_gewijzigd_op DESC
        ) = 1
    ) AS latest
    WHERE NOT verwijderd
        {% if is_incremental() %}
        AND api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    nummer,
    titels,
    initialen,
    tussenvoegsel,
    achternaam,
    voornamen,
    roepnaam,
    geslacht,
    functie,
    geboortedatum,
    geboortedatum_ruw,
    geboortedatum_precisie,
    geboorteplaats,
    geboorteland,
    overlijdensdatum,
    overlijdensdatum_ruw,
    overlijdensdatum_precisie,
    overlijdensplaats,
    woonplaats,
    land,
    fractielabel,
    portret_url,
    content_type,
    content_length,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming
-- Deduplicate to the most recent version per person within this batch
QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY gewijzigd_op DESC, api_gewijzigd_op DESC) = 1
