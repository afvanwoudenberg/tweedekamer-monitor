"""Run ingestion sources followed by dbt transformations."""

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

import dlt

# Support both module execution and direct script execution from the pipeline directory.
if __package__:
    from .ingest.opendata import opendata_source
else:
    from ingest.opendata import opendata_source

PIPELINE_DIR = Path(__file__).resolve().parent
TRANSFORM_DIR = PIPELINE_DIR / "transform"
DUCKDB_PATH = PIPELINE_DIR.parent / "tweedekamer.duckdb"

def run_ingestion(
    pipeline_name: str = "tweedekamer_pipeline",
    dataset_name: str = "bronze",
    category: Optional[str] = None,
    max_pages: Optional[int] = None,
    validate_xsd: bool = True,
):
    """Run all configured ingestion sources into DuckDB."""
    pipeline = dlt.pipeline(
        pipeline_name=pipeline_name,
        destination=dlt.destinations.duckdb(credentials=str(DUCKDB_PATH)),
        dataset_name=dataset_name,
    )
    load_info = pipeline.run(
        opendata_source(category=category, max_pages=max_pages, validate_xsd=validate_xsd)
    )
    print(load_info)
    return load_info

def run_transform() -> None:
    """Run the dbt project after ingestion has completed."""
    environment = os.environ.copy()
    environment["DUCKDB_PATH"] = str(DUCKDB_PATH)
    dbt_executable = Path(sys.executable).with_name("dbt")

    subprocess.run(
        [str(dbt_executable), "build", "--project-dir", str(TRANSFORM_DIR), "--profiles-dir", str(TRANSFORM_DIR)],
        check=True,
        env=environment,
    )

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--category")
    parser.add_argument("--max-pages", type=int)
    parser.add_argument("--no-xsd-validation", action="store_true")
    args = parser.parse_args()

    run_ingestion(
        category=args.category,
        max_pages=args.max_pages,
        validate_xsd=not args.no_xsd_validation,
    )
    run_transform()

if __name__ == "__main__":
    main()
