{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.reservering',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH activity_links AS (
    SELECT
        _dlt_parent_id,
        MAX(ref) AS activiteit_id
    FROM {{ source('bronze', 'reservering__activiteit') }}
    GROUP BY 1
),

latest AS (
    SELECT
        r.id,
        al.activiteit_id,
        r.zaal__ref AS zaal_id,
        r.nummer,
        r.activiteit_nummer,
        r.status_code,
        r.status_naam,
        r.verwijderd,
        r.bijgewerkt AS gewijzigd_op,
        r.feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'reservering') }} AS r
    LEFT JOIN activity_links AS al ON r._dlt_id = al._dlt_parent_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY r.id
        ORDER BY r.bijgewerkt DESC, r.feed_updated DESC, r._dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.activiteit_id,
        latest.zaal_id,
        latest.nummer,
        latest.activiteit_nummer,
        latest.status_code,
        latest.status_naam,
        latest.gewijzigd_op,
        latest.api_gewijzigd_op
    FROM latest
    LEFT JOIN {{ ref('activiteit') }} AS activity
        ON latest.activiteit_id = activity.id
    LEFT JOIN {{ ref('zaal') }} AS room
        ON latest.zaal_id = room.id
    WHERE NOT latest.verwijderd
      AND (latest.activiteit_id IS NULL OR activity.id IS NOT NULL)
      AND (latest.zaal_id IS NULL OR room.id IS NOT NULL)
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    activiteit_id,
    zaal_id,
    nummer,
    activiteit_nummer,
    status_code,
    status_naam,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming