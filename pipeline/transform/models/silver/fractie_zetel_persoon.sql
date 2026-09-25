{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.fractie_zetel_persoon',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        fractie_zetel__ref AS fractie_zetel_id,
        persoon__ref AS persoon_id,
        functie,
        {{ parse_partial_datum('van') }} AS van_parsed,
        van AS van_ruw,
        {{ parse_partial_datum('tot_en_met', is_end_date=true) }} AS tot_en_met_parsed,
        tot_en_met AS tot_en_met_ruw,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'fractie_zetel_persoon') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.fractie_zetel_id,
        latest.persoon_id,
        latest.functie,
        latest.van_parsed.datum AS van,
        latest.van_ruw,
        latest.van_parsed.precisie AS van_precisie,
        latest.tot_en_met_parsed.datum AS tot_en_met,
        latest.tot_en_met_ruw,
        latest.tot_en_met_parsed.precisie AS tot_en_met_precisie,
        latest.gewijzigd_op,
        latest.api_gewijzigd_op
    FROM latest
    INNER JOIN {{ ref('fractie_zetel') }} AS seat
        ON latest.fractie_zetel_id = seat.id
    INNER JOIN {{ ref('persoon') }} AS person
        ON latest.persoon_id = person.id
    WHERE NOT latest.verwijderd
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    fractie_zetel_id,
    persoon_id,
    functie,
    van,
    van_ruw,
    van_precisie,
    tot_en_met,
    tot_en_met_ruw,
    tot_en_met_precisie,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming