{{
    config(
        unique_key=['activiteit_id', 'vervangen_vanuit_id'],
        incremental_strategy='merge_with_deletes',
        deletion_relation='none',
        on_schema_change='fail',
        contract={'enforced': true}
    )
}}

WITH links AS (
    SELECT DISTINCT
        parent.id AS activiteit_id,
        ref AS vervangen_vanuit_id
    FROM {{ source('bronze', 'activiteit__vervangen_vanuit') }} AS link
    INNER JOIN {{ source('bronze', 'activiteit') }} AS parent
        ON link._dlt_parent_id = parent._dlt_id
    WHERE link.ref IS NOT NULL
),

incoming AS (
    SELECT links.*
    FROM links
    INNER JOIN {{ ref('activiteit') }} AS activity
        ON links.activiteit_id = activity.id
    INNER JOIN {{ ref('activiteit') }} AS replaced
        ON links.vervangen_vanuit_id = replaced.id
)

SELECT * FROM incoming