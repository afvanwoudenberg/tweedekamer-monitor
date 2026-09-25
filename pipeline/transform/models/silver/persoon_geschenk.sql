{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.persoon_geschenk',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        persoon__ref AS persoon_id,
        omschrijving,
        {{ parse_partial_datum('datum') }} AS datum_parsed,
        datum AS datum_ruw,
        CAST(gewicht AS INTEGER) AS gewicht,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'persoon_geschenk') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        id,
        persoon_id,
        omschrijving,
        datum_parsed.datum AS datum,
        datum_ruw,
        datum_parsed.precisie AS datum_precisie,
        gewicht,
        gewijzigd_op,
        api_gewijzigd_op
    FROM latest
    WHERE NOT verwijderd
        {% if is_incremental() %}
        AND api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    persoon_id,
    omschrijving,
    datum,
    datum_ruw,
    datum_precisie,
    gewicht,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming