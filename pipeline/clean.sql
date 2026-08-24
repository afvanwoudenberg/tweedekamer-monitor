-- Reset the environment by deleting all tables

-- Set default catalog and schema for subsequent queries
USE CATALOG workspace;
USE SCHEMA tweedekamer;

-- Drop tables
DROP TABLE IF EXISTS bronze_opendata_api;
