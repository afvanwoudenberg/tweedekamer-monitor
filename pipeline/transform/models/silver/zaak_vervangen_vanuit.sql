{{ config(unique_key=['zaak_id', 'vervangen_vanuit_id'], incremental_strategy='merge_with_deletes', deletion_relation='none', on_schema_change='fail', contract={'enforced': true}) }}
WITH links AS (
    SELECT DISTINCT parent.id AS zaak_id, ref AS vervangen_vanuit_id
    FROM {{ source('bronze', 'zaak__vervangen_vanuit') }} link
    JOIN {{ source('bronze', 'zaak') }} parent ON link._dlt_parent_id = parent._dlt_id
    WHERE ref IS NOT NULL
)
SELECT links.* FROM links
JOIN {{ ref('zaak') }} zaak ON links.zaak_id = zaak.id
JOIN {{ ref('zaak') }} parent ON links.vervangen_vanuit_id = parent.id