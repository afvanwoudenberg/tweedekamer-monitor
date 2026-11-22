# Dit script voert de queries uit ster_commissies.sql uit op de database.
# Elke query wordt een CSV bestand in dezelfde map als dit script.
# Start het vanuit de projectmap, naast App.py en tweedekamer.duckdb.

import re
from pathlib import Path

import duckdb

BASE = Path(__file__).resolve().parent
SQL_PATH = BASE / "ster_commissies.sql"

# De database staat in de projectmap, een of twee mappen boven dit script
DB_PATH = next((m for m in (BASE / "tweedekamer.duckdb", BASE.parent / "tweedekamer.duckdb",
                            BASE.parent.parent / "tweedekamer.duckdb") if m.exists()),
               BASE / "tweedekamer.duckdb")
if not DB_PATH.exists():
    raise SystemExit("tweedekamer.duckdb niet gevonden. Zet het in de projectmap naast App.py.")

# Het SQL bestand knippen op de regels die beginnen met Tabel, zodat elke query een naam krijgt
delen = re.split(r"^-- Tabel\s+(\w+)\s*$", SQL_PATH.read_text(encoding="utf-8"), flags=re.M)
queries = dict(zip(delen[1::2], delen[2::2]))

con = duckdb.connect(str(DB_PATH), read_only=True)

# Elke query uitvoeren en het resultaat opslaan als CSV
for naam, sql in queries.items():
    df = con.sql(sql.strip().rstrip(";")).df()
    df.to_csv(BASE / f"{naam}.csv", index=False)
    print(f"{naam:28s} {len(df):>7} rijen")

print(f"\nKlaar. De CSV bestanden staan in {BASE}")
