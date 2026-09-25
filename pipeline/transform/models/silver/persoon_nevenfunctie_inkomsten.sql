{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.persoon_nevenfunctie_inkomsten',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        persoon_nevenfunctie__ref AS persoon_nevenfunctie_id,
        CAST(jaar AS INTEGER) AS jaar,
        bedrag_soort,
        bedrag_voorvoegsel,
        bedrag_valuta,
        CAST(bedrag AS DECIMAL(18, 2)) AS bedrag,
        bedrag_achtervoegsel,
        frequentie,
        frequentie_beschrijving,
        opmerking,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'persoon_nevenfunctie_inkomsten') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.persoon_nevenfunctie_id,
        latest.jaar,
        latest.bedrag_soort,
        latest.bedrag_voorvoegsel,
        latest.bedrag_valuta,
        latest.bedrag,
        latest.bedrag_achtervoegsel,
        latest.frequentie,
        latest.frequentie_beschrijving,
        latest.opmerking,
        latest.gewijzigd_op,
        latest.api_gewijzigd_op
    FROM latest
    INNER JOIN {{ ref('persoon_nevenfunctie') }} AS parent
        ON latest.persoon_nevenfunctie_id = parent.id
    WHERE NOT latest.verwijderd
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    persoon_nevenfunctie_id,
    jaar,
    bedrag_soort,
    bedrag_voorvoegsel,
    bedrag_valuta,
    bedrag,
    bedrag_achtervoegsel,
    frequentie,
    frequentie_beschrijving,
    opmerking,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming