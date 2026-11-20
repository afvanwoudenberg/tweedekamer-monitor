"""Voert gold_queries.sql uit op tweedekamer.duckdb en slaat elk resultaat op als CSV.

De feitentabellen worden beperkt tot de meest recente ROW_LIMIT rijen. De dimensies
worden daarna gefilterd op de sleutels die in die feiten voorkomen, zodat de CSV's
klein blijven maar nog steeds op elkaar aansluiten.

Gebruik:
    python export_gold.py
of in een notebook:
    export_gold()
"""
import re
from pathlib import Path

import duckdb
import pandas as pd

# Instellingen
try:
    BASE_DIR = Path(__file__).resolve().parent
except NameError:  # in een notebook bestaat __file__ niet
    BASE_DIR = Path.cwd()
SQL_FILE = BASE_DIR / "gold_queries.sql"
OUTPUT_DIR = BASE_DIR / "data_communicatie" / "gold"
ROW_LIMIT = 1000          # max. aantal feitrijen per feitentabel in de CSV
UNKNOWN_KEYS = ("-1", -1, 99991231)  # 'Onbekend'-rij en 'Nog actief', altijd meenemen

FACTS = ["fact_contactgegevens_persoon", "fact_fractie_zetel_persoon"]

# dimensie -> lijst van (kolom in dimensie, feitentabel, kolom in feitentabel)
DIM_FILTERS = {
    "dim_persoon": [("persoon_id", "fact_contactgegevens_persoon", "persoon_id"),
                    ("persoon_id", "fact_fractie_zetel_persoon", "persoon_id")],
    "dim_fractie": [("fractie_id", "fact_fractie_zetel_persoon", "fractie_id")],
    "dim_kanaal":  [("channel_key", "fact_contactgegevens_persoon", "channel_key")],
    "dim_soort":   [("soort_id", "fact_contactgegevens_persoon", "soort_id")],
    "dim_datum":   [("date_key", "fact_contactgegevens_persoon", "date_key"),
                    ("date_key", "fact_fractie_zetel_persoon", "van_date_key"),
                    ("date_key", "fact_fractie_zetel_persoon", "tot_en_met_date_key")],
}


# Hulpfuncties
def find_database(start: Path | None = None) -> Path:
    """Zoek tweedekamer.duckdb door omhoog te lopen vanaf de huidige map."""
    current = (start or Path.cwd()).resolve()
    for folder in (current, *current.parents):
        candidate = folder / "tweedekamer.duckdb"
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("Could not find tweedekamer.duckdb from the current directory")


def load_queries(sql_file: Path) -> dict[str, str]:
    """Lees het SQL-bestand en geef {tabelnaam: query}. Elke query start met '-- name: <naam>'."""
    text = sql_file.read_text(encoding="utf-8")
    parts = re.split(r"^-- name:\s*(\w+)\s*$", text, flags=re.MULTILINE)
    # parts = [voorwoord, naam1, sql1, naam2, sql2, ...]
    return {name: sql.strip().rstrip(";") for name, sql in zip(parts[1::2], parts[2::2])}


# Export
def export_gold(database_path: Path | None = None) -> dict[str, pd.DataFrame]:
    database_path = database_path or find_database()
    queries = load_queries(SQL_FILE)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    connection = duckdb.connect(str(database_path), read_only=True)
    try:
        tables = {name: connection.execute(sql).fetchdf() for name, sql in queries.items()}
    finally:
        connection.close()

    # 1. Feiten beperken tot de meest recente rijen (ze zijn al op datum gesorteerd)
    for fact in FACTS:
        tables[fact] = tables[fact].head(ROW_LIMIT)

    # 2. Dimensies filteren op de sleutels die in de beperkte feiten voorkomen
    for dim, links in DIM_FILTERS.items():
        mask = pd.Series(False, index=tables[dim].index)
        for dim_col, fact, fact_col in links:
            mask |= tables[dim][dim_col].isin(tables[fact][fact_col])
            mask |= tables[dim][dim_col].isin(UNKNOWN_KEYS)
        tables[dim] = tables[dim][mask]

    # 3. Opslaan
    for name, df in tables.items():
        path = OUTPUT_DIR / f"{name}.csv"
        df.to_csv(path, index=False, encoding="utf-8")
        print(f"{path}: {len(df)} rijen")

    return tables


if __name__ == "__main__":
    export_gold()
