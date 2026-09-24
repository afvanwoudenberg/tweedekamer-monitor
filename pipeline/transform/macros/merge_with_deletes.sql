{% macro get_incremental_merge_with_deletes_sql(arg_dict) %}
    {% set target_relation = arg_dict['target_relation'] %}
    {% set temp_relation = arg_dict['temp_relation'] %}
    {% set unique_key = arg_dict['unique_key'] %}
    {% set dest_columns = arg_dict['dest_columns'] %}
    {% set incremental_predicates = arg_dict.get('incremental_predicates') %}
    {% set deletion_relation = config.get('deletion_relation') %}

    {% if not deletion_relation %}
        {{ exceptions.raise_compiler_error(
            "incremental_strategy='merge_with_deletes' requires deletion_relation"
        ) }}
    {% endif %}

    {% if unique_key is not string %}
        {{ exceptions.raise_compiler_error(
            "merge_with_deletes currently requires a single-column unique_key"
        ) }}
    {% endif %}

    {% set column_names = dest_columns | map(attribute='name') | list %}
    {% set quoted_columns = get_quoted_csv(column_names) %}
    {% set active_values = [] %}
    {% set source_values = [] %}
    {% set deleted_values = [] %}
    {% set update_values = [] %}

    {% for column_name in column_names %}
        {% do active_values.append('DBT_ACTIVE_SOURCE.' ~ adapter.quote(column_name)) %}
        {% do source_values.append('DBT_SOURCE.' ~ adapter.quote(column_name)) %}
        {% do update_values.append(adapter.quote(column_name) ~ ' = DBT_SOURCE.' ~ adapter.quote(column_name)) %}
        {% if column_name == unique_key %}
            {% do deleted_values.append('DBT_DELETED_SOURCE.' ~ adapter.quote(column_name)) %}
        {% else %}
            {% do deleted_values.append('NULL') %}
        {% endif %}
    {% endfor %}

    {% set latest_deleted_sql %}
        SELECT {{ unique_key }}
        FROM (
            SELECT
                {{ unique_key }},
                verwijderd,
                ROW_NUMBER() OVER (
                    PARTITION BY {{ unique_key }}
                    ORDER BY feed_updated DESC, bijgewerkt DESC, _dlt_id DESC
                ) AS version_number
            FROM {{ deletion_relation }}
        ) AS latest
        WHERE version_number = 1
            AND verwijderd = true
    {% endset %}

    {% set merge_sql %}
        MERGE INTO {{ target_relation }} AS DBT_TARGET
        USING (
            SELECT
                {{ active_values | join(', ') }},
                FALSE AS __dbt_deleted
            FROM {{ temp_relation }} AS DBT_ACTIVE_SOURCE

            UNION ALL

            SELECT
                {{ deleted_values | join(', ') }},
                TRUE AS __dbt_deleted
            FROM ({{ latest_deleted_sql }}) AS DBT_DELETED_SOURCE
        ) AS DBT_SOURCE
        ON DBT_SOURCE.{{ adapter.quote(unique_key) }} = DBT_TARGET.{{ adapter.quote(unique_key) }}
        WHEN MATCHED AND DBT_SOURCE.__dbt_deleted THEN DELETE
        WHEN MATCHED THEN UPDATE SET {{ update_values | join(', ') }}
        WHEN NOT MATCHED AND DBT_SOURCE.__dbt_deleted THEN DO NOTHING
        WHEN NOT MATCHED THEN INSERT ({{ quoted_columns }})
            VALUES ({{ source_values | join(', ') }})
    {% endset %}

    {{ return(merge_sql) }}
{% endmacro %}