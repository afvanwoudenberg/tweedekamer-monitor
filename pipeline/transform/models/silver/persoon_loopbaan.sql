{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.persoon_loopbaan',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        persoon__ref AS persoon_id,
        functie,
        werkgever,
        omschrijving_nl,
        omschrijving_en,
        plaats,
        {{ parse_partial_datum('van') }} AS van_parsed,
        van AS van_ruw,
        {{ parse_partial_datum('tot_en_met', is_end_date=true) }} AS tot_en_met_parsed,
        tot_en_met AS tot_en_met_ruw,
        CAST(gewicht AS INTEGER) AS gewicht,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'persoon_loopbaan') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        id,
        persoon_id,
        functie,
        werkgever,
        omschrijving_nl,
        omschrijving_en,
        plaats,
        van_parsed.datum AS van,
        van_ruw,
        van_parsed.precisie AS van_precisie,
        tot_en_met_parsed.datum AS tot_en_met,
        tot_en_met_ruw,
        tot_en_met_parsed.precisie AS tot_en_met_precisie,
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
    functie,
    werkgever,
    omschrijving_nl,
    omschrijving_en,
    plaats,
    van,
    van_ruw,
    van_precisie,
    tot_en_met,
    tot_en_met_ruw,
    tot_en_met_precisie,
    gewicht,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming