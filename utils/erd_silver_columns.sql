-- Generate a Mermaid ERD containing basic column information from all tables in the silver layer
-- Usage: duckdb tweedekamer.duckdb -noheader -list < utils/erd_silver_columns.sql | wl-copy

WITH column_keys AS (
    -- Extract Primary Keys (including multi-column composite PKs) and Foreign Keys
    SELECT 
        c.table_name,
        c.column_name,
        LOWER(c.data_type) AS data_type,
        c.ordinal_position,
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
    WHERE c.table_schema = 'silver'
    GROUP BY c.table_name, c.column_name, c.data_type, c.ordinal_position
),
entity_definitions AS (
    -- Build Mermaid entity blocks with PK/FK indicators
    SELECT 
        table_name,
        '    ' || table_name || ' {' || chr(10) || 
        string_agg(
            '        ' || REPLACE(data_type, ' ', '_') || ' ' || column_name || 
            CASE 
                WHEN is_pk = 'PK' AND is_fk = 'FK' THEN ' PK,FK'
                WHEN is_pk = 'PK' THEN ' PK'
                WHEN is_fk = 'FK' THEN ' FK'
                ELSE '' 
            END, 
            chr(10) ORDER BY ordinal_position
        ) || chr(10) || '    }' AS mermaid_entity
    FROM column_keys
    GROUP BY table_name
),
fk_constraints AS (
    -- Aggregate foreign key columns per constraint (handles composite FKs)
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
    -- Determine if the Foreign Key constraint is also UNIQUE or PK on the child table (1:1 vs 1:N)
    SELECT 
        fk.constraint_name,
        fk.child_table,
        fk.parent_table,
        fk.fk_columns,
        CASE 
            WHEN uc.constraint_name IS NOT NULL
            THEN '||--||'  -- One-to-One
            ELSE '||--o{'  -- One-to-Many
        END AS relationship_operator
    FROM fk_constraints fk
    LEFT JOIN (
        SELECT
            tc.table_name,
            tc.constraint_name,
            string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS key_columns,
            COUNT(*) AS key_col_count
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
           AND tc.table_schema = kcu.table_schema
        WHERE tc.table_schema = 'silver'
          AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
        GROUP BY tc.table_name, tc.constraint_name
    ) uc
        ON fk.child_table = uc.table_name
       AND fk.fk_columns = uc.key_columns
       AND fk.fk_col_count = uc.key_col_count
    GROUP BY fk.constraint_name, fk.child_table, fk.parent_table, fk.fk_columns, uc.constraint_name
)
-- Aggregate diagram elements into final Mermaid erDiagram
SELECT 
    'erDiagram' || chr(10) ||
    COALESCE(string_agg(DISTINCT e.mermaid_entity, chr(10)), '') || chr(10) ||
    COALESCE(
        (SELECT string_agg(
            '    ' || c.parent_table || ' ' || c.relationship_operator || ' ' || c.child_table || ' : "' || c.fk_columns || '"', 
            chr(10)
        ) FROM cardinality_check c), 
        ''
    ) AS mermaid_erd
FROM entity_definitions e;

