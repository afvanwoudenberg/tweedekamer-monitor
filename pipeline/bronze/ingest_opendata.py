# Tweede Kamer Open Data API ingestion

import re
import json
import requests
import xml.etree.ElementTree as ET

from delta.tables import DeltaTable
from pyspark.sql.functions import (
    col,
    current_timestamp,
    explode,
    parse_json,
    regexp_extract,
    expr,
    udf
)
from pyspark.sql.types import (
    LongType, 
    TimestampType, 
    VariantType, 
    StringType, 
    ArrayType
)

# Configuration
CATALOG = "workspace"
SCHEMA = "tweedekamer"

TABLE_NAME = f"{CATALOG}.{SCHEMA}.bronze_opendata_api"
BASE_URL = "https://gegevensmagazijn.tweedekamer.nl/SyncFeed/2.0/Feed"
BATCH_SIZE_PAGES = 50  # Flush memory to Delta table every 50 pages

CATEGORIES = [
    'Activiteit', 'ActiviteitActor', 'Agendapunt', 'Besluit', 'Commissie', 
    'CommissieContactinformatie', 'CommissieZetel', 'CommissieZetelVastPersoon',
    'CommissieZetelVastVacature', 'CommissieZetelVervangerPersoon', 'CommissieZetelVervangerVacature',
    'Document', 'DocumentActor', 'DocumentVersie', 'DocumentPublicatie', 'DocumentPublicatieMetadata',
    'Fractie', 'FractieZetel', 'FractieZetelPersoon', 'FractieZetelVacature', 'Kamerstukdossier',
    'Persoon', 'PersoonContactinformatie', 'PersoonGeschenk', 'PersoonLoopbaan', 'PersoonNevenfunctie',
    'PersoonNevenfunctieInkomsten', 'PersoonOnderwijs', 'PersoonReis', 'Reservering', 'Stemming',
    'Toezegging', 'Vergadering', 'Verslag', 'Zaak', 'ZaakActor', 'Zaal'
]

def create_opendata_api_table_if_not_exists():
    """
    Creates the table to store the XML in if it doesn't exist.
    """
    (
        DeltaTable.createIfNotExists(spark)
        .tableName(TABLE_NAME)
        .addColumn(
            "entry",
            VariantType(),
            comment="XML entry-object met alle metagegevens, links en inhoud van de entiteit",
        )
        .addColumn(
            "skiptoken",
            LongType(),
            comment="Oplopend token geëxtraheerd uit de entry-link; wordt gebruikt voor incrementele synchronisatie en versievolgorde",
        )
        .addColumn(
            "ingested_at",
            TimestampType(),
            comment="UTC-tijdstempel van het moment waarop het record in Bronze is geschreven",
        )
        .comment("Brontabel voor ruwe SyncFeed-entries van de Tweede Kamer")
        .execute()
    )

def _element_to_dict(element):
    """
    Recursively converts an ElementTree XML element into a Python dictionary,
    preserving attributes (@), inner text (#text), and forcing arrays for repeated tags.
    """
    node = {}

    # Preserve attributes with '@' prefix
    for key, value in element.attrib.items():
        attr_key = key.split("}")[-1] if "}" in key else key
        node[f"@{attr_key}"] = value

    # Force array behavior for tags that can repeat
    FORCE_LIST_TAGS = {"link"}

    # Process child tags
    children = list(element)
    if children:
        for child in children:
            child_data = _element_to_dict(child)
            tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag

            if tag in node:
                if not isinstance(node[tag], list):
                    node[tag] = [node[tag]]
                node[tag].append(child_data)
            else:
                if tag in FORCE_LIST_TAGS:
                    node[tag] = [child_data]
                else:
                    node[tag] = child_data
    
    # Handle inner text content
    text = element.text.strip() if element.text else ""
    if text:
        if children or element.attrib:
            node["#text"] = text
        else:
            return text

    return node

def _extract_and_convert_entries_func(page_xml_str):
    """
    Extracts all <entry> nodes from an Atom XML feed page and converts each to a JSON string.
    Unwraps the outer 'entry' wrapper so fields sit directly at the root.
    """
    if not page_xml_str or not page_xml_str.strip():
        return []

    try:
        root = ET.fromstring(page_xml_str)
        json_entries = []

        for elem in root.iter():
            tag_name = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
            if tag_name == "entry":
                # Convert the XML element to a dictionary
                entry_dict = _element_to_dict(elem)
                
                # If _element_to_dict returned a dict wrapped in {"entry": {...}}, unwrap it.
                # Otherwise, if it returned the fields directly, use it as is.
                if isinstance(entry_dict, dict) and "entry" in entry_dict and len(entry_dict) == 1:
                    unwrapped_dict = entry_dict["entry"]
                else:
                    unwrapped_dict = entry_dict

                json_entries.append(json.dumps(unwrapped_dict))

        return json_entries
    except Exception as e:
        print(f"XML Parsing Exception: {e}")
        return []

# Explicit UDF registration to avoid Spark Connect Python 3.12 warnings
parse_page_xml_to_json_array = udf(
    _extract_and_convert_entries_func, 
    returnType=ArrayType(StringType())
)

def get_last_skiptoken(category: str, table_name=TABLE_NAME) -> int | None:
    """
    Reads the highest skiptoken processed so far from the Bronze Delta table.
    """
    if spark.catalog.tableExists(table_name):
        query = f"""
            SELECT MAX(skiptoken) 
            FROM {table_name} 
            WHERE entry:category:['@term']::string ILIKE '{category}'
        """
        max_token = spark.sql(query).collect()[0][0]
        return int(max_token) if max_token is not None else None
    return None

def flush_pages_to_bronze(xml_pages_list: list[str], table_name: str) -> int:
    """
    Parses a batch of XML page strings into VARIANT structs and appends them to Delta.
    """
    df_raw = spark.createDataFrame([(xml,) for xml in xml_pages_list], ["page_xml"])

    df_json_entries = df_raw.select(
        explode(parse_page_xml_to_json_array(col("page_xml"))).alias("entry_json")
    )

    # Store as 'entry' column
    df_entries = df_json_entries.select(
        parse_json(col("entry_json")).alias("entry"),
        current_timestamp().alias("ingested_at")
    )

    # Extract skiptoken from 'entry' column
    df_final = df_entries.withColumn(
        "skiptoken",
        regexp_extract(
            expr("to_json(entry:link)"), 
            r"skiptoken=(\d+)", 
            1
        ).cast("long")
    )

    record_count = df_final.count()
    df_final.write.format("delta").mode("append").saveAsTable(table_name)
    print(f"Appended {record_count} entries to {table_name}.")

    return record_count

def ingest_opendata_category(category: str, max_pages: int | None = None):
    create_opendata_api_table_if_not_exists()

    current_token = get_last_skiptoken(category, TABLE_NAME)
    
    if current_token is None:
        print(f"No previous skiptoken found for {category}. Starting initial full load...")
    else:
        print(f"Resuming incremental load from {category} skiptoken: {current_token}")

    pending_xml_pages = []
    page_count = 0
    total_entries_ingested = 0
    has_more_data = True

    session = requests.Session()

    while has_more_data:
        if max_pages is not None and page_count >= max_pages:
            print(f"Reached user-defined execution limit of {max_pages} pages. Stopping batch run.")
            break

        params = {"content": "internal", "category": category}
        if current_token is not None:
            params["skiptoken"] = current_token

        response = session.get(BASE_URL, params=params)
        response.raise_for_status()
        xml_content = response.text

        if "<entry" in xml_content:
            pending_xml_pages.append(xml_content)
            page_count += 1
        else:
            print(f"Reached end of feed (no entries on page).")
            has_more_data = False

        resume_match = re.search(r'<link[^>]*rel="resume"[^>]*href="([^"]+)"', xml_content)
        if resume_match:
            next_link_match = None
        else:
            next_link_match = re.search(r'<link[^>]*rel="next"[^>]*href="([^"]+)"', xml_content)
        
        if next_link_match:
            next_url = next_link_match.group(1)
            token_match = re.search(r"skiptoken=(\d+)", next_url)
            next_token = int(token_match.group(1)) if token_match else None
        else:
            next_token = None

        reached_max = (max_pages is not None and page_count >= max_pages)

        if (len(pending_xml_pages) >= BATCH_SIZE_PAGES) or (not has_more_data) or (next_token is None) or reached_max:
            if pending_xml_pages:
                total_entries_ingested += flush_pages_to_bronze(pending_xml_pages, TABLE_NAME)
                pending_xml_pages = []

        if next_token is not None and (current_token is None or next_token > current_token):
            current_token = next_token
        else:
            has_more_data = False

    return (max_pages - page_count) if max_pages is not None else None, page_count, total_entries_ingested, current_token

def ingest_opendata(max_pages: int | None = None):
    mp = max_pages
    for category in CATEGORIES:
        if mp and mp <= 0:
            break
        mp, page_count, total_entries_ingested, current_token = ingest_opendata_category(category, mp)
        print(f"Processed {page_count} pages (~{total_entries_ingested} entries). Final skiptoken: {current_token}")

if __name__ == "__main__":
    # ingest_opendata(max_pages=5000)
    ingest_opendata()