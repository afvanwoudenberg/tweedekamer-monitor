{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.activiteit',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        soort,
        nummer,
        onderwerp,
        datum_soort,
        CAST(datum AS DATE) AS datum,
        CAST(aanvangstijd AS TIMESTAMP) AS aanvangstijd,
        CAST(eindtijd AS TIMESTAMP) AS eindtijd,
        locatie,
        besloten,
        status,
        vergaderjaar,
        kamer,
        noot,
        vrs_nummer,
        sid_voortouw,
        voortouwnaam,
        voortouwafkorting,
        voortouwkortenaam,
        voortouwcommissie__ref AS voortouwcommissie_id,
        CAST(aanvraagdatum AS DATE) AS aanvraagdatum,
        CAST(datum_verzoek_eerste_verlenging AS DATE) AS datum_verzoek_eerste_verlenging,
        CAST(datum_mededeling_eerste_verlenging AS DATE) AS datum_mededeling_eerste_verlenging,
        CAST(datum_verzoek_tweede_verlenging AS DATE) AS datum_verzoek_tweede_verlenging,
        CAST(datum_mededeling_tweede_verlenging AS DATE) AS datum_mededeling_tweede_verlenging,
        CAST(vervaldatum AS DATE) AS vervaldatum,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'activiteit') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT latest.* EXCLUDE (verwijderd)
    FROM latest
    LEFT JOIN {{ ref('commissie') }} AS commissie
        ON latest.voortouwcommissie_id = commissie.id
    WHERE NOT latest.verwijderd
        AND (latest.voortouwcommissie_id IS NULL OR commissie.id IS NOT NULL)
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT * FROM incoming