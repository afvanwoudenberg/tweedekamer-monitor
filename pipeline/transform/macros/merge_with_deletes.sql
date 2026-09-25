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
    {% set update_statements = [] %}

    {% for column_name in column_names %}
        {% do active_values.append('DBT_ACTIVE_SOURCE.' ~ adapter.quote(column_name)) %}
        {% do source_values.append('DBT_SOURCE.' ~ adapter.quote(column_name)) %}
        {% if column_name != unique_key %}
            {% set update_statement %}
                UPDATE {{ target_relation }} AS DBT_TARGET
                SET {{ adapter.quote(column_name) }} = DBT_SOURCE.{{ adapter.quote(column_name) }}
                FROM {{ temp_relation }} AS DBT_SOURCE
                WHERE DBT_TARGET.{{ adapter.quote(unique_key) }} = DBT_SOURCE.{{ adapter.quote(unique_key) }}
                  AND DBT_TARGET.{{ adapter.quote(column_name) }} IS DISTINCT FROM DBT_SOURCE.{{ adapter.quote(column_name) }}
            {% endset %}
            {% do update_statements.append(update_statement) %}
        {% endif %}
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

    {% set dependent_query %}
        SELECT DISTINCT
            kcu.table_schema,
            kcu.table_name,
            kcu.column_name
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
           AND tc.table_schema = kcu.table_schema
        JOIN information_schema.referential_constraints AS rc
            ON tc.constraint_name = rc.constraint_name
           AND tc.table_schema = rc.constraint_schema
        JOIN information_schema.constraint_column_usage AS ccu
            ON rc.unique_constraint_name = ccu.constraint_name
           AND rc.unique_constraint_schema = ccu.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND rc.unique_constraint_schema = '{{ target_relation.schema }}'
          AND ccu.table_name = '{{ target_relation.identifier }}'
          AND kcu.table_schema = '{{ target_relation.schema }}'
    {% endset %}

    {% set dependent_result = run_query(dependent_query) %}
    {% set dependent_deletes = [] %}
    {% if execute and dependent_result is not none %}
        {% for row in dependent_result.rows %}
            {% set child_schema = row[0] %}
            {% set child_table = row[1] %}
            {% set child_column = row[2] %}
            {% set delete_statement %}
                DELETE FROM "{{ child_schema }}"."{{ child_table }}"
                WHERE "{{ child_column }}" IN (
                    SELECT {{ unique_key }}
                    FROM ({{ latest_deleted_sql }}) AS DBT_DELETED_KEYS
                )
            {% endset %}
            {% do dependent_deletes.append(delete_statement) %}
        {% endfor %}
    {% endif %}

    {% set delete_sql %}
        DELETE FROM {{ target_relation }} AS DBT_TARGET
        WHERE {{ unique_key }} IN (
            SELECT {{ unique_key }}
            FROM ({{ latest_deleted_sql }}) AS DBT_DELETED_KEYS
        )
    {% endset %}

    {% set insert_sql %}
        INSERT INTO {{ target_relation }} ({{ quoted_columns }})
        SELECT {{ source_values | join(', ') }}
        FROM {{ temp_relation }} AS DBT_SOURCE
        WHERE NOT EXISTS (
            SELECT 1
            FROM {{ target_relation }} AS DBT_TARGET
            WHERE DBT_TARGET.{{ adapter.quote(unique_key) }} = DBT_SOURCE.{{ adapter.quote(unique_key) }}
        )
    {% endset %}

    {{ return((dependent_deletes | join(';\n')) ~ (';\n' if dependent_deletes else '') ~ delete_sql ~ ';\n' ~ (update_statements | join(';\n')) ~ ';\n' ~ insert_sql) }}
{% endmacro %}