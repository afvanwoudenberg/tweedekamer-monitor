{#- Convert an ISO year/week (+ optional weekday) string to a Gregorian DATE.
    Approximate: assumes the standard ISO 8601 week-numbering rule (week 1 = the
    week containing the first Thursday of the year / 4 January). -#}
{% macro _iso_week_date(column, weekday_expr='1') %}
(
    DATE (substr({{ column }}, 1, 4) || '-01-04')
    - CAST(
        (isodow(DATE (substr({{ column }}, 1, 4) || '-01-04')) - 1)
        - (CAST(substr({{ column }}, 7, 2) AS INTEGER) - 1) * 7
        - (({{ weekday_expr }}) - 1)
        AS INTEGER
    )
)
{% endmacro %}

{#- Parse a source date string that follows the tkData "datum" union type
    (xs:date | gYearWeekDay | gYearWeek | xs:gYearMonth | xs:gYear), e.g.
    "1980-03-14", "1980-03", "1980", "1980-W11", "1980-W11-4".
    Returns a STRUCT(datum DATE, precisie VARCHAR) with missing month/day
    defaulted to 1 and a precisie tag (dag/maand/jaar/week/week_dag)
    describing how precise the source value actually was. -#}
{% macro parse_partial_datum(column, is_end_date=false) %}
struct_pack(
    datum := CASE
        WHEN regexp_matches({{ column }}, '^\d{4}-\d{2}-\d{2}$')
            THEN CAST({{ column }} AS DATE)
        WHEN regexp_matches({{ column }}, '^\d{4}-\d{2}$')
            THEN {% if is_end_date %}last_day(CAST({{ column }} || '-01' AS DATE)){% else %}CAST({{ column }} || '-01' AS DATE){% endif %}
        WHEN regexp_matches({{ column }}, '^\d{4}-W\d{2}-\d$')
            THEN {{ _iso_week_date(column, "CAST(substr(" ~ column ~ ", 11, 1) AS INTEGER)") }}
        WHEN regexp_matches({{ column }}, '^\d{4}-W\d{2}$')
            THEN {% if is_end_date %}CAST({{ _iso_week_date(column) }} + INTERVAL '6 days' AS DATE){% else %}{{ _iso_week_date(column) }}{% endif %}
        WHEN regexp_matches({{ column }}, '^\d{4}$')
            THEN {% if is_end_date %}CAST({{ column }} || '-12-31' AS DATE){% else %}CAST({{ column }} || '-01-01' AS DATE){% endif %}
        ELSE NULL
    END,
    precisie := CASE
        WHEN regexp_matches({{ column }}, '^\d{4}-\d{2}-\d{2}$') THEN 'dag'
        WHEN regexp_matches({{ column }}, '^\d{4}-\d{2}$') THEN 'maand'
        WHEN regexp_matches({{ column }}, '^\d{4}-W\d{2}-\d$') THEN 'week_dag'
        WHEN regexp_matches({{ column }}, '^\d{4}-W\d{2}$') THEN 'week'
        WHEN regexp_matches({{ column }}, '^\d{4}$') THEN 'jaar'
        ELSE NULL
    END
)
{% endmacro %}
