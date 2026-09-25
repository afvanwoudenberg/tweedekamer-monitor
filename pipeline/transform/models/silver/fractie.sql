{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.fractie',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH links AS (
    SELECT
        _dlt_parent_id,
        MAX(CASE WHEN rel = 'enclosure' THEN href END) AS logo_url
    FROM {{ source('bronze', 'fractie__atom_links') }}
    GROUP BY 1
),

latest AS (
    SELECT
        f.id,
        f.nummer,
        f.afkorting,
        f.naam_nl,
        f.naam_en,
        CAST(f.aantal_zetels AS INTEGER) AS aantal_zetels,
        CAST(f.aantal_stemmen AS INTEGER) AS aantal_stemmen,
        {{ parse_partial_datum('f.datum_actief') }} AS datum_actief_parsed,
        f.datum_actief AS datum_actief_ruw,
        {{ parse_partial_datum('f.datum_inactief', is_end_date=true) }} AS datum_inactief_parsed,
        f.datum_inactief AS datum_inactief_ruw,
        l.logo_url,
        f.content_type,
        CAST(f.content_length AS INTEGER) AS content_length,
        f.verwijderd,
        f.bijgewerkt AS gewijzigd_op,
        f.feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'fractie') }} AS f
    LEFT JOIN links AS l ON f._dlt_id = l._dlt_parent_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY f.id
        ORDER BY f.bijgewerkt DESC, f.feed_updated DESC, f._dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.nummer,
        latest.afkorting,
        latest.naam_nl,
        latest.naam_en,
        latest.aantal_zetels,
        latest.aantal_stemmen,
        latest.datum_actief_parsed.datum AS datum_actief,
        latest.datum_actief_ruw,
        latest.datum_actief_parsed.precisie AS datum_actief_precisie,
        latest.datum_inactief_parsed.datum AS datum_inactief,
        latest.datum_inactief_ruw,
        latest.datum_inactief_parsed.precisie AS datum_inactief_precisie,
        latest.logo_url,
        latest.content_type,
        latest.content_length,
        latest.gewijzigd_op,
        latest.api_gewijzigd_op
    FROM latest
    WHERE NOT latest.verwijderd
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    nummer,
    afkorting,
    naam_nl,
    naam_en,
    aantal_zetels,
    aantal_stemmen,
    datum_actief,
    datum_actief_ruw,
    datum_actief_precisie,
    datum_inactief,
    datum_inactief_ruw,
    datum_inactief_precisie,
    logo_url,
    content_type,
    content_length,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming