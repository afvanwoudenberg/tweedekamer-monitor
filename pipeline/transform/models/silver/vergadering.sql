{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.vergadering',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        soort,
        titel,
        zaal,
        vergaderjaar,
        CAST(vergadering_nummer AS INTEGER) AS vergadering_nummer,
        CAST(datum AS DATE) AS datum,
        CAST(aanvangstijd AS TIMESTAMP) AS aanvangstijd,
        CAST(sluiting AS TIMESTAMP) AS sluiting,
        kamer,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'vergadering') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        id,
        soort,
        titel,
        zaal,
        vergaderjaar,
        vergadering_nummer,
        datum,
        aanvangstijd,
        sluiting,
        kamer,
        gewijzigd_op,
        api_gewijzigd_op
    FROM latest
    WHERE NOT verwijderd
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    soort,
    titel,
    zaal,
    vergaderjaar,
    vergadering_nummer,
    datum,
    aanvangstijd,
    sluiting,
    kamer,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming