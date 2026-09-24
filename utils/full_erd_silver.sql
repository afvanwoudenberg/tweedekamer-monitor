-- Generate a Mermaid ERD containing full column information from all tables in the silver layer
-- Usage: duckdb tweedekamer.duckdb -noheader -list < utils/full_erd_silver.sql

WITH column_meta AS (
    -- Fetch columns, primary/foreign key status, and column comments from DuckDB catalog
    SELECT 
        c.table_name,
        c.column_name,
        LOWER(c.data_type) AS data_type,
        c.ordinal_position,
        dc.comment AS column_comment,
        MAX(CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN 'PK' ELSE '' END) AS is_pk,
        MAX(CASE WHEN tc.constraint_type = 'FOREIGN KEY' THEN 'FK' ELSE '' END) AS is_fk
    FROM information_schema.columns c
    LEFT JOIN information_schema.key_column_usage kcu
        ON c.table_schema = kcu.table_schema 
       AND c.table_name = kcu.table_name 
       AND c.column_name = kcu.column_name
    LEFT JOIN information_schema.table_constraints tc
        ON kcu.constraint_name = tc.constraint_name 
       AND kcu.table_schema = tc.table_schema
    LEFT JOIN duckdb_columns() dc
        ON c.table_schema = dc.schema_name
       AND c.table_name = dc.table_name
       AND c.column_name = dc.column_name
    WHERE c.table_schema = 'silver'
    GROUP BY c.table_name, c.column_name, c.data_type, c.ordinal_position, dc.comment
),
table_meta AS (
    -- Fetch table comments from DuckDB catalog
    SELECT 
        table_name,
        comment AS table_comment
    FROM duckdb_tables()
    WHERE schema_name = 'silver'
),
entity_definitions AS (
    -- Build Mermaid entity blocks with column comments & header table comments
    SELECT 
        m.table_name,
        COALESCE('    %% Table: ' || m.table_name || 
                 CASE WHEN t.table_comment IS NOT NULL AND t.table_comment != '' 
                      THEN ' - ' || REPLACE(t.table_comment, chr(10), ' ') 
                      ELSE '' END || chr(10), '') ||
        '    ' || m.table_name || ' {' || chr(10) || 
        string_agg(
            '        ' || REPLACE(m.data_type, ' ', '_') || ' ' || m.column_name || 
            CASE 
                WHEN m.is_pk = 'PK' AND m.is_fk = 'FK' THEN ' PK,FK'
                WHEN m.is_pk = 'PK' THEN ' PK'
                WHEN m.is_fk = 'FK' THEN ' FK'
                ELSE '' 
            END ||
            CASE 
                WHEN m.column_comment IS NOT NULL AND m.column_comment != '' 
                THEN ' ' || chr(34) || REPLACE(REPLACE(m.column_comment, chr(34), chr(39)), chr(10), ' ') || chr(34)
                ELSE '' 
            END, 
            chr(10) ORDER BY m.ordinal_position
        ) || chr(10) || '    }' AS mermaid_entity
    FROM column_meta m
    LEFT JOIN table_meta t ON m.table_name = t.table_name
    GROUP BY m.table_name, t.table_comment
),
fk_constraints AS (
    -- Aggregate foreign key columns per constraint
    SELECT 
        tc.constraint_name,
        kcu.table_name AS child_table,
        ccu.table_name AS parent_table,
        string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS fk_columns,
        COUNT(kcu.column_name) AS fk_col_count
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name 
       AND tc.table_schema = kcu.table_schema
    JOIN information_schema.referential_constraints rc
        ON tc.constraint_name = rc.constraint_name 
       AND tc.table_schema = rc.constraint_schema
    JOIN information_schema.constraint_column_usage ccu
        ON rc.unique_constraint_name = ccu.constraint_name 
       AND rc.unique_constraint_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'silver'
    GROUP BY tc.constraint_name, kcu.table_name, ccu.table_name
),
cardinality_check AS (
    -- Determine 1:1 vs 1:N cardinality
    SELECT 
        fk.constraint_name,
        fk.child_table,
        fk.parent_table,
        fk.fk_columns,
        CASE 
            WHEN uc.constraint_type IN ('PRIMARY KEY', 'UNIQUE') 
                 AND COUNT(DISTINCT ukcu.column_name) = fk.fk_col_count 
            THEN '||--||' 
            ELSE '||--o{' 
        END AS relationship_operator
    FROM fk_constraints fk
    LEFT JOIN information_schema.key_column_usage ukcu
        ON fk.child_table = ukcu.table_name
    LEFT JOIN information_schema.table_constraints uc
        ON ukcu.constraint_name = uc.constraint_name 
       AND uc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
    GROUP BY fk.constraint_name, fk.child_table, fk.parent_table, fk.fk_columns, fk.fk_col_count, uc.constraint_type
)
-- Aggregate diagram elements into final Mermaid erDiagram
SELECT 
    'erDiagram' || chr(10) ||
    COALESCE(string_agg(DISTINCT e.mermaid_entity, chr(10) || chr(10)), '') || chr(10) || chr(10) ||
    COALESCE(
        (SELECT string_agg(
            '    ' || c.parent_table || ' ' || c.relationship_operator || ' ' || c.child_table || ' : ' || chr(34) || c.fk_columns || chr(34), 
            chr(10)
        ) FROM cardinality_check c), 
        ''
    ) AS mermaid_erd
FROM entity_definitions e;
