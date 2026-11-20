from pathlib import Path
import duckdb

def find_database(start: Path | None = None) -> Path:
    """Find the repository DuckDB database by walking up from the current folder."""
    current = (start or Path.cwd()).resolve()
    for folder in (current, *current.parents):
        candidate = folder / "tweedekamer.duckdb"
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("Could not find tweedekamer.duckdb from the current directory")

map_hier = Path(__file__).resolve().parent                     # de map van dit script
database = find_database()
connection = duckdb.connect(str(database), read_only=True)

data_map = map_hier / "CVS_files"
data_map.mkdir(exist_ok=True)

sql_map = map_hier / "SQL"
bestanden = sorted(sql_map.glob("*.sql"))
print("Database:", database, "| bestaat:", database.exists())
print(f"{len(bestanden)} SQL-bestanden gevonden in {sql_map}")

for sql_bestand in bestanden:
    df = connection.execute(sql_bestand.read_text(encoding="utf-8")).fetchdf()
    df.to_csv(data_map / f"{sql_bestand.stem}.csv", index=False)
    print(f"{sql_bestand.stem}: {len(df)} rijen opgeslagen")

