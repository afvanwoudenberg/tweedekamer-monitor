{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.fractie_zetel',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH latest AS (
    SELECT
        id,
        fractie__ref AS fractie_id,
        CAST(gewicht AS INTEGER) AS gewicht,
        verwijderd,
        bijgewerkt AS gewijzigd_op,
        feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'fractie_zetel') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY bijgewerkt DESC, feed_updated DESC, _dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.fractie_id,
        latest.gewicht,
        latest.gewijzigd_op,
        latest.api_gewijzigd_op
    FROM latest
    INNER JOIN {{ ref('fractie') }} AS parent
        ON latest.fractie_id = parent.id
    WHERE NOT latest.verwijderd
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    fractie_id,
    gewicht,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming