"""
Tweede Kamer Open Data API ingestion using dlt (data load tool), DuckDB, and XSD validation.

Extracts data from the SyncFeed 2.0 XML Atom feed, validates and decodes each XML entity
against official XSD schemas (tkData-v1-0.xsd), and dynamically dispatches records into
dedicated bronze tables for each entity type (e.g. bronze.verslag, bronze.persoon, bronze.vergadering).
"""

from pathlib import Path
from typing import Any, Dict, Iterator, Optional
import re
import xml.etree.ElementTree as ET
import dlt
import requests
import xmlschema

BASE_URL = "https://gegevensmagazijn.tweedekamer.nl/SyncFeed/2.0/Feed"
SCHEMA_DIR = Path(__file__).resolve().parent / "schemas"
XSD_FILE = SCHEMA_DIR / "tkData-v1-0.xsd"

XML_NAMESPACES = {
    "atom": "http://www.w3.org/2005/Atom",
    "ns1": "http://www.tweedekamer.nl/xsd/tkData/v1-0",
    "xsi": "http://www.w3.org/2001/XMLSchema-instance",
}

IGNORED_KEYS = {"xmlns", "atom", "ns1", "xsi"}

# Cache compiled XMLSchema instance
_XSD_SCHEMA: Optional[xmlschema.XMLSchema] = None

def get_xsd_schema() -> xmlschema.XMLSchema:
    """Loads and caches the compiled XSD schema definition."""
    global _XSD_SCHEMA
    if _XSD_SCHEMA is None:
        if not XSD_FILE.exists():
            raise FileNotFoundError(f"XSD schema file not found at: {XSD_FILE}")
        _XSD_SCHEMA = xmlschema.XMLSchema(str(XSD_FILE))
    return _XSD_SCHEMA

def clean_dict_keys(data: Any) -> Any:
    """
    Recursively strips XML namespace prefixes (e.g., 'ns1:', 'xmlns:')
    and XML attribute prefixes ('@') from dictionary keys.
    """
    if isinstance(data, dict):
        cleaned = {}
        for k, v in data.items():
            clean_k = k.split(":")[-1].lstrip("@")
            if clean_k in IGNORED_KEYS or k.startswith("@xmlns"):
                continue
            cleaned[clean_k] = clean_dict_keys(v)
        return cleaned
    elif isinstance(data, list):
        return [clean_dict_keys(item) for item in data]
    return data

def extract_skiptoken_from_links(element: ET.Element) -> Optional[int]:
    """
    Extracts the skiptoken integer from Atom feed link elements (rel='next' or rel='resume').
    """
    for link in element.findall("atom:link", XML_NAMESPACES):
        rel = link.get("rel")
        href = link.get("href", "")
        if rel in ("next", "resume"):
            match = re.search(r"skiptoken=(\d+)", href)
            if match:
                return int(match.group(1))
    return None


def extract_atom_links(entry_element: ET.Element) -> list[Dict[str, str]]:
    """Returns the Atom link metadata attached to an entry."""
    return [
        {key: value for key, value in link.attrib.items()}
        for link in entry_element.findall("atom:link", XML_NAMESPACES)
    ]


def normalize_boolean_attributes(entity_element: ET.Element) -> None:
    """Normalizes source boolean attributes to XML Schema lexical values."""
    for attribute_name, value in entity_element.attrib.items():
        if attribute_name.rsplit("}", maxsplit=1)[-1] == "verwijderd" and value in {"True", "False"}:
            entity_element.set(attribute_name, value.lower())


def get_entity_table_name(item: Dict[str, Any]) -> str:
    """
    Computes a dedicated table name per entity category, e.g.
    'Verslag' -> 'verslag', 'CommissieZetel' -> 'commissie_zetel'.
    """
    category = item.get("_category") or item.get("category") or "raw_entity"
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", category)
    table_suffix = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1).lower()
    return f"{table_suffix}"

@dlt.resource(
    table_name=get_entity_table_name,
    write_disposition="append",
)
def opendata_feed_resource(
    category: Optional[str] = None,
    max_pages: Optional[int] = None,
    validate_xsd: bool = True,
) -> Iterator[Dict[str, Any]]:
    """
    dlt resource yielding XSD-validated records dynamically routed to separate bronze tables.
    """
    schema = get_xsd_schema() if validate_xsd else None
    session = requests.Session()
    state = dlt.current.resource_state()
    skiptoken_key = category or "all"
    skiptokens = state.setdefault("skiptokens", {})
    current_skiptoken = skiptokens.get(skiptoken_key)
    pages_processed = 0

    if current_skiptoken is None:
        print(f"No previous skiptoken found (category: {category or 'ALL'}). Starting initial load...")
    else:
        print(f"Resuming incremental load from skiptoken: {current_skiptoken} (category: {category or 'ALL'})...")

    while True:
        if max_pages is not None and pages_processed >= max_pages:
            print(f"Reached execution limit of {max_pages} pages.")
            break

        params: Dict[str, Any] = {"content": "internal"}
        if category:
            params["category"] = category
        if current_skiptoken is not None:
            params["skiptoken"] = current_skiptoken

        response = session.get(BASE_URL, params=params, timeout=60)
        response.raise_for_status()

        root = ET.fromstring(response.text)
        entries = root.findall("atom:entry", XML_NAMESPACES)
        if not entries:
            print("Reached end of feed (no entries on page).")
            break

        next_page_token = extract_skiptoken_from_links(root)
        for raw_entry in entries:
            # Feed metadata
            entry_id_el = raw_entry.find("atom:id", XML_NAMESPACES)
            entry_title_el = raw_entry.find("atom:title", XML_NAMESPACES)
            entry_updated_el = raw_entry.find("atom:updated", XML_NAMESPACES)
            entry_category_el = raw_entry.find("atom:category", XML_NAMESPACES)

            feed_id = entry_id_el.text if entry_id_el is not None else None
            feed_title = entry_title_el.text if entry_title_el is not None else None
            feed_updated = entry_updated_el.text if entry_updated_el is not None else None
            cat_name = entry_category_el.get("term") if entry_category_el is not None else "unknown"

            record: Dict[str, Any] = {
                "feed_id": feed_id,
                "feed_title": feed_title,
                "feed_updated": feed_updated,
                "category": cat_name,
                "atom_links": extract_atom_links(raw_entry),
            }

            # Parse and validate entity content
            content_el = raw_entry.find("atom:content", XML_NAMESPACES)
            if content_el is not None and len(content_el) > 0:
                entity_el = list(content_el)[0]

                if schema is not None:
                    normalize_boolean_attributes(entity_el)
                    # Validate and decode against XSD schema with native type casting
                    decoded_entity = schema.decode(
                        entity_el,
                        namespaces=XML_NAMESPACES,
                        validation="strict",
                    )
                    cleaned_entity = clean_dict_keys(decoded_entity)
                else:
                    cleaned_entity = clean_dict_keys(entity_el.attrib)

                # Unpack entity attributes and elements directly into record fields
                if isinstance(cleaned_entity, dict):
                    record.update(cleaned_entity)

            yield record

        pages_processed += 1
        if next_page_token is None or (current_skiptoken is not None and next_page_token <= current_skiptoken):
            print("Reached end of feed (no newer skiptoken).")
            break
        skiptokens[skiptoken_key] = next_page_token
        current_skiptoken = next_page_token

@dlt.source(name="opendata_source")
def opendata_source(
    category: Optional[str] = None,
    max_pages: Optional[int] = None,
    validate_xsd: bool = True,
):
    """
    dlt source for Tweede Kamer Open Data API with XSD schema validation.
    """
    return opendata_feed_resource(category=category, max_pages=max_pages, validate_xsd=validate_xsd)
