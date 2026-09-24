-- Generate a basic Mermaid ERD from all tables in the silver layer
-- Usage: duckdb tweedekamer.duckdb -noheader -list < utils/summary_erd_silver.sql

WITH table_list AS (
    SELECT table_name, '    ' || table_name || ' {}' AS mermaid_entity
    FROM information_schema.tables
    WHERE table_schema = 'silver' AND table_type = 'BASE TABLE'
),
fk_constraints AS (
    SELECT 
        tc.constraint_name, kcu.table_name AS child_table, ccu.table_name AS parent_table,
        string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS fk_columns,
        COUNT(kcu.column_name) AS fk_col_count
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.referential_constraints rc
        ON tc.constraint_name = rc.constraint_name AND tc.table_schema = rc.constraint_schema
    JOIN information_schema.constraint_column_usage ccu
        ON rc.unique_constraint_name = ccu.constraint_name AND rc.unique_constraint_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'silver'
    GROUP BY tc.constraint_name, kcu.table_name, ccu.table_name
),
cardinality_check AS (
    SELECT 
        fk.constraint_name, fk.child_table, fk.parent_table, fk.fk_columns,
        CASE 
            WHEN uc.constraint_type IN ('PRIMARY KEY', 'UNIQUE') 
                 AND COUNT(DISTINCT ukcu.column_name) = fk.fk_col_count 
            THEN '||--||' ELSE '||--o{' 
        END AS relationship_operator
    FROM fk_constraints fk
    LEFT JOIN information_schema.key_column_usage ukcu ON fk.child_table = ukcu.table_name
    LEFT JOIN information_schema.table_constraints uc
        ON ukcu.constraint_name = uc.constraint_name AND uc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
    GROUP BY fk.constraint_name, fk.child_table, fk.parent_table, fk.fk_columns, fk.fk_col_count, uc.constraint_type
)
SELECT 
    'erDiagram' || chr(10) ||
    COALESCE(string_agg(t.mermaid_entity, chr(10)), '') || chr(10) || chr(10) ||
    COALESCE((SELECT string_agg('    ' || c.parent_table || ' ' || c.relationship_operator || ' ' || c.child_table || ' : ' || chr(34) || c.fk_columns || chr(34), chr(10)) FROM cardinality_check c), '') AS mermaid_erd
FROM table_list t;

