{{
    config(
        unique_key='id',
        incremental_strategy='merge_with_deletes',
        deletion_relation='bronze.verslag',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH links AS (
    SELECT
        _dlt_parent_id,
        MAX(CASE WHEN rel = 'enclosure' THEN href END) AS xml_url
    FROM {{ source('bronze', 'verslag__atom_links') }}
    GROUP BY 1
),

latest AS (
    SELECT
        v.id,
        v.vergadering__ref AS vergadering_id,
        v.soort,
        v.status,
        v.content_type,
        CAST(v.content_length AS INTEGER) AS content_length,
        l.xml_url,
        v.verwijderd,
        v.bijgewerkt AS gewijzigd_op,
        v.feed_updated AS api_gewijzigd_op
    FROM {{ source('bronze', 'verslag') }} AS v
    LEFT JOIN links AS l ON v._dlt_id = l._dlt_parent_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY v.id
        ORDER BY v.bijgewerkt DESC, v.feed_updated DESC, v._dlt_id DESC
    ) = 1
),

incoming AS (
    SELECT
        latest.id,
        latest.vergadering_id,
        latest.soort,
        latest.status,
        latest.content_type,
        latest.content_length,
        latest.xml_url,
        latest.gewijzigd_op,
        latest.api_gewijzigd_op
    FROM latest
    INNER JOIN {{ ref('vergadering') }} AS meeting
        ON latest.vergadering_id = meeting.id
    WHERE NOT latest.verwijderd
        {% if is_incremental() %}
        AND latest.api_gewijzigd_op > (SELECT MAX(api_gewijzigd_op) FROM {{ this }})
        {% endif %}
)

SELECT
    id,
    vergadering_id,
    soort,
    status,
    content_type,
    content_length,
    xml_url,
    gewijzigd_op,
    api_gewijzigd_op
FROM incoming