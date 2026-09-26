{{ config(unique_key=['zaak_id', 'agendapunt_id'], incremental_strategy='merge_with_deletes', deletion_relation='none', on_schema_change='fail', contract={'enforced': true}) }}
WITH links AS (
    SELECT DISTINCT parent.id AS zaak_id, ref AS agendapunt_id
    FROM {{ source('bronze', 'zaak__agendapunt') }} link
    JOIN {{ source('bronze', 'zaak') }} parent ON link._dlt_parent_id = parent._dlt_id
    WHERE ref IS NOT NULL
)
SELECT links.* FROM links
JOIN {{ ref('zaak') }} zaak ON links.zaak_id = zaak.id
JOIN {{ ref('agendapunt') }} agendapunt ON links.agendapunt_id = agendapunt.id