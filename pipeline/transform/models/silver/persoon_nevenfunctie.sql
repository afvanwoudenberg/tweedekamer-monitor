{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.persoon_nevenfunctie',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        persoon__ref AS persoon_id,
        omschrijving,
        is_actief,
        {{ parse_partial_datum('periode__van') }} AS periode_van_parsed,
        periode__van AS periode_van_ruw,
        {{ parse_partial_datum('periode__tot_en_met', is_end_date=true) }} AS periode_tot_en_met_parsed,
        periode__tot_en_met AS periode_tot_en_met_ruw,
        vergoeding__soort AS vergoeding_soort,
        vergoeding__toelichting AS vergoeding_toelichting,
        CAST(gewicht AS INTEGER) AS gewicht,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'persoon_nevenfunctie') }}
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
        is_actief,
        periode_van_parsed.datum AS periode_van,
        periode_van_ruw,
        periode_van_parsed.precisie AS periode_van_precisie,
        periode_tot_en_met_parsed.datum AS periode_tot_en_met,
        periode_tot_en_met_ruw,
        periode_tot_en_met_parsed.precisie AS periode_tot_en_met_precisie,
        vergoeding_soort,
        vergoeding_toelichting,
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
    is_actief,
    periode_van,
    periode_van_ruw,
    periode_van_precisie,
    periode_tot_en_met,
    periode_tot_en_met_ruw,
    periode_tot_en_met_precisie,
    vergoeding_soort,
    vergoeding_toelichting,
    gewicht,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming