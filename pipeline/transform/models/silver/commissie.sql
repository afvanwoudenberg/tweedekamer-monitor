{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.commissie',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        nummer,
        soort,
        afkorting,
        naam_nl,
        naam_en,
        naam_web_nl,
        naam_web_en,
        inhoudsopgave,
        {{ parse_partial_datum('datum_actief') }} AS datum_actief_parsed,
        datum_actief AS datum_actief_ruw,
        {{ parse_partial_datum('datum_inactief', is_end_date=true) }} AS datum_inactief_parsed,
        datum_inactief AS datum_inactief_ruw,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'commissie') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.nummer,
        latest.soort,
        latest.afkorting,
        latest.naam_nl,
        latest.naam_en,
        latest.naam_web_nl,
        latest.naam_web_en,
        latest.inhoudsopgave,
        latest.datum_actief_parsed.datum AS datum_actief,
        latest.datum_actief_ruw,
        latest.datum_actief_parsed.precisie AS datum_actief_precisie,
        latest.datum_inactief_parsed.datum AS datum_inactief,
        latest.datum_inactief_ruw,
        latest.datum_inactief_parsed.precisie AS datum_inactief_precisie,
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
    soort,
    afkorting,
    naam_nl,
    naam_en,
    naam_web_nl,
    naam_web_en,
    inhoudsopgave,
    datum_actief,
    datum_actief_ruw,
    datum_actief_precisie,
    datum_inactief,
    datum_inactief_ruw,
    datum_inactief_precisie,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming