
# ==================================================
# DASHBOARD 2 - ACTIVITEIT & PLANNING
# Business Intelligence - Tweede Kamer
# ==================================================

# Importeer de benodigde bibliotheken
import streamlit as st
import pandas as pd
from pathlib import Path


# ==================================================
# 1. PAGINA INSTELLEN
# ==================================================

# Geef het dashboard een titel en brede indeling
st.set_page_config(
    page_title="Activiteit & Planning",
    page_icon="📊",
    layout="wide"
)

# Toon de titel bovenaan
st.title("Dashboard 2 - Activiteit & Planning")

# Geef een korte uitleg
st.write(
    "Analyse van reserveringen, activiteiten en "
    "vergaderzalen van de Tweede Kamer."
)


# ==================================================
# 2. CSV-BESTAND INLEZEN
# ==================================================

# Zoek de map waarin dit Python-bestand staat
map_pad = Path(__file__).resolve().parent

# Bepaal waar het CSV-bestand staat
csv_pad = map_pad / "dashboard_data" / "dashboard_2_activiteiten_planning.csv"

# Lees het CSV-bestand in als Pandas DataFrame
@st.cache_data
def laad_data():
    df = pd.read_csv(csv_pad)

    # Zet de datumkolom om naar echte datums
    df["datum"] = pd.to_datetime(df["datum"], errors="coerce")

    # Maak kolommen voor jaar en maand
    df["jaar"] = df["datum"].dt.year
    df["maand"] = df["datum"].dt.to_period("M").dt.to_timestamp()

    # Vul ontbrekende tekstwaarden op
    for kolom in ["vergaderzaal", "activiteitssoort", "status"]:
        df[kolom] = df[kolom].fillna("Onbekend")

    return df


# Controleer of het CSV-bestand bestaat
if not csv_pad.exists():
    st.error("Het CSV-bestand is niet gevonden.")
    st.stop()

# Laad de gegevens
df = laad_data()


# ==================================================
# 3. FILTERS
# ==================================================

st.sidebar.header("Filters")

# Maak een lijst met beschikbare jaren
jaren = sorted(df["jaar"].dropna().astype(int).unique())

# Laat de gebruiker een jaar kiezen
gekozen_jaar = st.sidebar.selectbox(
    "Selecteer jaar",
    ["Alle jaren"] + jaren
)

# Maak een lijst met vergaderzalen
zalen = sorted(df["vergaderzaal"].unique())

# Laat de gebruiker een vergaderzaal kiezen
gekozen_zaal = st.sidebar.selectbox(
    "Selecteer vergaderzaal",
    ["Alle zalen"] + zalen
)

# Maak een lijst met activiteitssoorten
soorten = sorted(df["activiteitssoort"].unique())

# Laat de gebruiker een activiteitssoort kiezen
gekozen_soort = st.sidebar.selectbox(
    "Selecteer activiteitssoort",
    ["Alle soorten"] + soorten
)


# ==================================================
# 4. FILTERS TOEPASSEN
# ==================================================

# Maak een kopie van de gegevens
df_filter = df.copy()

# Filter op jaar als een jaar is gekozen
if gekozen_jaar != "Alle jaren":
    df_filter = df_filter[df_filter["jaar"] == gekozen_jaar]

# Filter op vergaderzaal
if gekozen_zaal != "Alle zalen":
    df_filter = df_filter[
        df_filter["vergaderzaal"] == gekozen_zaal
    ]

# Filter op activiteitssoort
if gekozen_soort != "Alle soorten":
    df_filter = df_filter[
        df_filter["activiteitssoort"] == gekozen_soort
    ]


# ==================================================
# 5. BELANGRIJKSTE CIJFERS (KPI'S)
# ==================================================

st.subheader("Belangrijkste cijfers")

# Maak drie kolommen naast elkaar
kolom1, kolom2, kolom3 = st.columns(3)

# Tel het aantal unieke reserveringen
aantal_reserveringen = df_filter["reservering_id"].nunique()

# Tel het aantal verschillende zaalnamen
aantal_zalen = df_filter["vergaderzaal"].nunique()

# Tel het aantal unieke activiteiten
aantal_activiteiten = df_filter["activiteit_id"].nunique()

# Laat de cijfers zien
kolom1.metric("Reserveringen", f"{aantal_reserveringen/1000:.1f}k")

kolom2.metric("Vergaderzalen", f"{aantal_zalen:,}")

kolom3.metric("Activiteiten", f"{aantal_activiteiten/1000:.1f}k")


# ==================================================
# 6. GRAFIEKEN
# ==================================================

st.divider()

# Maak twee kolommen voor de grafieken
links, rechts = st.columns(2)

# GRAFIEK 1: MEEST GEBRUIKTE VERGADERZALEN
with links:

    st.subheader("Meest gebruikte vergaderzalen")

    # Tel de reserveringen per vergaderzaal
    zalen_telling = (
        df_filter.groupby("vergaderzaal")
        .size()
        .reset_index(name="aantal")
        .sort_values("aantal", ascending=False)
        .head(10)
    )

    # Maak een horizontaal staafdiagram
    st.bar_chart(
        zalen_telling,
        x="vergaderzaal",
        y="aantal",
        horizontal=True,
        height=400
    )



# GRAFIEK 2: ACTIVITEITEN PER JAAR
with rechts:

    st.subheader("Activiteiten per jaar")

    # Tel het aantal unieke activiteiten per jaar
    jaar_telling = (
        df_filter.dropna(subset=["jaar"])
        .groupby("jaar")["activiteit_id"]
        .nunique()
        .reset_index(name="aantal")
        .sort_values("jaar")
    )

    # Maak een staafdiagram
    st.bar_chart(
        jaar_telling,
        x="jaar",
        y="aantal",
        height=400
    )



# ==================================================
# 7. DETAILTABEL
# ==================================================

st.divider()

st.subheader("Overzicht activiteiten en reserveringen")

# Kies welke kolommen we willen laten zien
detailtabel = df_filter[
    [
        "datum",
        "vergaderzaal",
        "activiteitssoort",
        "activiteit",
        "status"
    ]
].copy()

# Geef de kolommen duidelijke namen
detailtabel.columns = [
    "Datum",
    "Vergaderzaal",
    "Activiteitssoort",
    "Activiteit",
    "Status"
]

# Toon de tabel in het dashboard
st.dataframe(
    detailtabel,
    use_container_width=True,
    hide_index=True
)


# ==================================================
# 8. CSV DOWNLOADEN
# ==================================================

# Maak de gefilterde gegevens downloadbaar
st.download_button(
    label="Download gefilterde gegevens als CSV",
    data=detailtabel.to_csv(index=False).encode("utf-8-sig"),
    file_name="activiteiten_planning_gefilterd.csv",
    mime="text/csv"
)


# ==================================================
# 9. BRONVERMELDING
# ==================================================

st.divider()

st.caption(
    "Bron: Tweede Kamer - DuckDB Silver-laag. "
    "Gegevens verwerkt met SQL en Pandas."
)

st.caption(
    "Let op: dit dashboard gebruikt reserveringen als uitgangspunt. "
    "Activiteiten zonder reservering zijn niet opgenomen."
)
