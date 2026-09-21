# Tweede Kamer Monitor Architecture

## Purpose

Tweede Kamer Monitor is an open-source data pipeline and public dashboard for exploring the work of the Dutch House of Representatives (Tweede Kamer). It turns data from the Tweede Kamer Open Data API into information that is useful to the public and to people doing research.

The project has two goals:

1. Give the public a simple way to explore parliamentary work, legislation, motions, meetings, documents, and voting.
2. Provide clean, documented data for journalists, researchers, and data scientists who want to work in SQL, Python, or R notebooks.

## Architecture

### Intended Users and Design Goals

The primary intended users are members of the general public. Journalists, researchers, and data scientists are important secondary users who can clone or fork the repository and work directly with cleaned data using data analysis tools like Python/R notebooks, SQL or Power BI.

The architecture prioritizes:

- Explain parliamentary concepts instead of leaving readers to decode jargon.
- Make data preparation reproducible and the source of each dataset clear.
- Keep analytical data clean and its contracts stable.
- Use low-cost hosting and public distribution.
- Prefer portable technologies and open formats.
- Keep components small enough for an open-source project to operate.

### System Overview

The pipeline periodically reads the [Tweede Kamer Open Data](https://opendata.tweedekamer.nl/) API using **dlt** (data load tool) into a local **DuckDB** database (`bronze` layer). Transformations from Bronze to Silver and Gold are managed with **dbt** (dbt-duckdb). The Gold data is published as Parquet files. The Streamlit dashboard runs from this repository on Streamlit Community Cloud and queries those files through DuckDB.

```mermaid
flowchart LR
    API["🏛️ Tweede Kamer Open Data API"]
    
    subgraph LocalEngine["DuckDB + dlt + dbt"]
        direction LR
        B[("🥉 Bronze\nraw feed via dlt")]
        S[("🥈 Silver\nclean models via dbt")]
        G[("🥇 Gold\nstar schema via dbt")]
        
        B --> S --> G
    end

    GH["GitHub Releases\n📦 Parquet assets"]
    SC["Streamlit Community Cloud\n📊 Dashboard"]
    USER["🙍 General Public"]
    ANALYST["👩‍💻 Data Scientist"]


    API --> B
    G --> GH
        
    %% The dashboard is placed under the assets
    GH -- "DuckDB SQL over Parquet" --> SC
    
    %% The user is placed to the left of the dashboard
    USER -. "uses" .-> SC
    ANALYST -. "uses" .-> LocalEngine
```

### Data Layers

The pipeline follows the [Medallion Architecture](https://docs.databricks.com/en/lakehouse/medallion.html):

- **Bronze** stores raw source feed data ingested by `dlt` in DuckDB with automatic incremental `skiptoken` tracking and XSD schema validation. Entries are dynamically routed to dedicated bronze tables per entity type (`bronze.verslag`, `bronze.persoon`, `bronze.vergadering`, etc.).
- **Silver** cleans and conforms the data for analytical use via `dbt`.
- **Gold** organizes the data for dashboard and reporting queries.

### Source and Ingestion

The source is the public [Tweede Kamer Open Data](https://opendata.tweedekamer.nl/) API, accessed through its SyncFeed 2.0 XML interface. The ingestion logic lives in [`pipeline/ingest/opendata.py`](pipeline/ingest/opendata.py). A skiptoken managed automatically by `dlt`'s incremental state ensures that only new items are ingested.

Raw source records are validated against XSD schemas and dynamically dispatched to dedicated `bronze.<entity>` tables in DuckDB.

Any future external sources must also enter through Bronze. Their original data and source metadata should remain there before the data is cleaned, combined, or transformed in Silver and Gold.

Ingestion should respect the public API with bounded requests, suitable retries, and a schedule that does not create unnecessary load. Failures must be visible and must not silently produce an incomplete refresh.

### Transformation

The dbt project that transforms raw data in the Bronze layer to clean Silver and Gold tables lives in [`pipeline/transform/`](pipeline/transform/). Models for each table belong in its `models/` folder.

The [`pipeline/run_pipeline.py`](pipeline/run_pipeline.py) script runs all ingestion sources and then the dbt transformation project. It is run periodically to keep data up to date.

### Publication

Parquet is the exchange format between the pipeline and the dashboard. Gold tables are exported as Parquet files, published through GitHub Releases, and queried by the Streamlit dashboard using DuckDB.

Each release replaces the previous assets. 

This arrangement provides several benefits:

- Parquet is compact and columnar, so it works well for analytical scans.
- Column pruning and compression limit the data read by dashboard queries.
- The files work across Python, R, SQL engines, and local data tools.
- GitHub Releases provide public distribution without requiring a database server.
- The pipeline and the dashboard can be run independently.
- DuckDB can run expressive SQL over Parquet inside the Streamlit process.

The release process should publish complete, consistent assets, and the dashboard should never mix files from different refreshes. 

### Dashboard

#### Hosting and Caching

The Streamlit dashboard is deployed from this repository on [Streamlit Community Cloud](https://streamlit.io/cloud). It should use caching because Streamlit reruns the script when users interact with widgets. Otherwise, each interaction could recreate DuckDB connections, download the same data, and repeat identical queries.

#### Public Usability

The dashboard should work for people who are unfamiliar with the Tweede Kamer. Each view should briefly explain what it shows, why it matters, and how to read it. The interface should:

- Explain terms such as *motie*, *wetsvoorstel*, *stemming*, *fractie*, *commissie*, and *vergadering* in plain language.
- Explain the basic path from proposal to debate, vote, and decision where relevant.
- Use clear labels, descriptive chart titles, units, and legends.
- Provide sensible defaults and allow users to start exploring without configuring many controls.
- Use progressive disclosure so advanced detail is available without overwhelming first-time users.
- Handle empty results, loading, stale data, and failures with useful messages.
- Show data freshness and source provenance.
- Keep text and controls readable on common desktop and mobile viewports.
- Use accessible color choices, sufficient contrast, and alternatives to color-only distinctions.
- Avoid presenting correlations or counts as causal explanations.

The dashboard is a public explanation layer, not the only way to analyze the data. Users who need more detail or repeatability can clone or fork the repository and work with Silver and Gold tables in SQL, Python, or R notebooks.

## Standards

### Coding and Data

The pipeline and analytical models follow these conventions:

- Follow the [PEP 8](https://peps.python.org/pep-0008/) style guide for Python code.
- Use singular, lowercase Dutch words in `snake_case` for table names and column names. Apply the same convention consistently across all layers.
- Prefer meaningful names over unexplained abbreviations.
- Use stable source identifiers for keys and document any surrogate-key strategy.
- Use consistent types for dates, timestamps, booleans, numeric measures, and text.
- Define the grain of every fact and the intended cardinality of important relationships.
- Keep transformation logic deterministic and idempotent where possible.
- Prefer portable SQL, Python, and open file formats.
- Write all SQL keywords in uppercase, such as `SELECT`, `FROM`, `WHERE`, `JOIN`, and `GROUP BY`. Table names, column names, and other identifiers follow the lowercase Dutch naming convention above.

### Data Contracts

Silver merges should use durable source identifiers, defined merge keys, and idempotent update rules. Gold uses a star schema with documented fact-table grains and dimensions for descriptive context. Silver should be usable directly in SQL, Python, or R; Gold is recalculated and published on each refresh.

Every Silver and Gold table and column must have a Dutch description added to it. It should describe things such as its meaning, provenance, units where relevant, nullability or expected values, and transformation semantics. These comments are part of the data contract: they document the data for users and maintainers and help LLM agents build accurate queries.

## Operations

Refreshes should include checks appropriate to each layer, including XML parsing, required fields, uniqueness, referential integrity, expected row-count changes, freshness, valid domains, and completeness of the Gold export.

### Refresh and Reliability

Operations should include:

- Periodic scheduling of API ingestion.
- Bounded retries and respectful request pacing.
- Idempotent ingestion and Silver merges.
- Handling and reporting of malformed or unexpected source data.
- Explicit schema-evolution decisions when the API changes.
- Logging of refresh start, completion, row counts, failures, and publication results.
- No credentials or secrets committed to the repository.

### Portability

The pipeline prioritizes open-source tools, including **DuckDB** for analytical storage, **dlt** for ingestion, and **dbt** for transformations. The dashboard is built using **Streamlit**. Using open-source tools, portable SQL, and open formats helps keep the workload reproducible and portable across environments.

## Glossary

- **Tweede Kamer**: the Dutch House of Representatives.
- **Fractie**: a parliamentary group, usually organized around a political party.
- **Motie**: a motion in which members ask the government to take an action or express a view.
- **Wetsvoorstel**: a legislative proposal.
- **Stemming**: a vote.
- **Vergadering**: a parliamentary meeting or sitting.
- **Commissie**: a parliamentary committee.
