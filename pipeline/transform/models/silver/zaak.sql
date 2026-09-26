{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.zaak',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        nummer,
        soort,
        onderwerp,
        CAST(gestart_op AS DATE) AS gestart_op,
        organisatie,
        titel,
        citeertitel,
        alias,
        grondslagvoorhang,
        CAST(termijn AS TIMESTAMP) AS termijn,
        vergaderjaar,
        CAST(volgnummer AS INTEGER) AS volgnummer,
        status,
        afgedaan,
        groot_project,
        kabinetsappreciatie,
        kamerstukdossier__ref AS kamerstukdossier_id,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'zaak') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC) = 1
),

incoming AS (
    SELECT latest.* EXCLUDE (verwijderd)
    FROM latest
    LEFT JOIN {{ ref('kamerstukdossier') }} AS dossier ON latest.kamerstukdossier_id = dossier.id
    WHERE NOT latest.verwijderd
      AND (latest.kamerstukdossier_id IS NULL OR dossier.id IS NOT NULL)
      {% if is_incremental() %}
      AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
      {% endif %}
)

SELECT * FROM incoming