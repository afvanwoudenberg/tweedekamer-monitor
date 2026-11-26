"""Dashboard: contactgegevens van Tweede Kamerleden per soort en per fractie.

Starten:
    py -m streamlit run Communicatie_dashboard.py
"""

#

from pathlib import Path

import altair as alt
import pandas as pd
import streamlit as st

def vind_data_map(naam: str = "data_communicatie") -> Path:
    """Zoek vanaf dit script omhoog naar de map met de gold-CSV's."""
    for map_ in Path(__file__).resolve().parents:
        for kandidaat in (map_ / naam / "gold", map_ / naam):
            if (kandidaat / "dim_persoon.csv").is_file():
                return kandidaat
    return Path(__file__).parent / naam / "gold"  # niet gevonden: de foutmelding toont dit pad


DATA_DIR = vind_data_map()
ACCENT = "#2E6F9E"

st.set_page_config(page_title="Contactgegevens Tweede Kamer", page_icon="📇", layout="wide")


# Data inlezen
@st.cache_data
def lees(naam: str, **kwargs) -> pd.DataFrame:
    return pd.read_csv(DATA_DIR / f"{naam}.csv", **kwargs)
 
 
try:
    dim_fractie = lees("dim_fractie", dtype={"fractie_id": str})
    dim_persoon = lees("dim_persoon", dtype={"persoon_id": str})
    dim_soort = lees("dim_soort")
    fact_contact = lees("fact_contactgegevens_persoon", dtype={"persoon_id": str})
    fact_zetel = lees("fact_fractie_zetel_persoon", dtype={"persoon_id": str, "fractie_id": str})
except FileNotFoundError:
    st.error(f"Geen CSV-bestanden gevonden in `{DATA_DIR}`. Draai eerst `py export_gold.py`.")
    st.stop()
    
# X en Twitter zijn hetzelfde kanaal: samenvoegen onder één naam
dim_soort["soort"] = dim_soort["soort"].apply(
    lambda s: "X (Twitter)" if isinstance(s, str) and s.strip().lower() in ("x", "twitter") else s
)

# Berekeningen
# 1. Aantal contactgegevens per soort
tabel_soort = (
    fact_contact.merge(dim_soort[["soort_id", "soort"]], on="soort_id", how="left")
    .groupby("soort", as_index=False)["contact_count"].sum()
    .rename(columns={"contact_count": "Aantal"})
)
tabel_soort = tabel_soort[tabel_soort["soort"] != "Onbekend"].sort_values("Aantal", ascending=False)

# 2. Gemiddeld aantal contactgegevens per fractie (personen zonder contactgegevens tellen als 0)
persoon_fractie = (
    fact_zetel[["persoon_id", "fractie_id"]].drop_duplicates()
    .merge(dim_fractie[["fractie_id", "naam_nl"]], on="fractie_id", how="left")
)
contact_per_persoon = fact_contact.groupby("persoon_id", as_index=False)["contact_count"].sum()

tabel_fractie = (
    persoon_fractie.merge(contact_per_persoon, on="persoon_id", how="left")
    .fillna({"contact_count": 0})
    .groupby("naam_nl", as_index=False)
    .agg(Personen=("persoon_id", "nunique"), Gemiddeld=("contact_count", "mean"))
    .rename(columns={"naam_nl": "Fractie", "Gemiddeld": "Gemiddeld aantal"})
    .round({"Gemiddeld aantal": 1})
    .dropna(subset=["Fractie"])
    .sort_values("Gemiddeld aantal", ascending=False)
)

# 3. Soort per fractie (niet beïnvloed door tijd)
fractie_contact = (
    persoon_fractie
    .merge(fact_contact[["persoon_id", "soort_id", "contact_count"]], on="persoon_id", how="inner")
    .merge(dim_soort[["soort_id", "soort"]], on="soort_id", how="left")
)
fractie_contact = fractie_contact[
    (fractie_contact["soort"] != "Onbekend") & fractie_contact["naam_nl"].notna()
]
per_fractie_soort = (
    fractie_contact.groupby(["naam_nl", "soort"], as_index=False)["contact_count"].sum()
    .rename(columns={"naam_nl": "Fractie", "contact_count": "Aantal"})
)
per_fractie_soort["Aandeel (%)"] = (
    per_fractie_soort["Aantal"]
    / per_fractie_soort.groupby("Fractie")["Aantal"].transform("sum") * 100
).round(1)

tabel_top_soort = (
    per_fractie_soort.sort_values(["Fractie", "Aantal", "soort"], ascending=[True, False, True])
    .drop_duplicates("Fractie")
    .rename(columns={"soort": "Meest gebruikte soort"})
    .sort_values("Fractie")
)


# Hulpfunctie voor staafgrafieken
def staafgrafiek(df: pd.DataFrame, categorie: str, waarde: str, titel: str, formaat: str = ",d"):
    """Horizontale staafgrafiek, gesorteerd van hoog naar laag, met de waarde achter de balk."""
    basis = alt.Chart(df).encode(
        y=alt.Y(f"{categorie}:N", sort="-x", title=None, axis=alt.Axis(labelLimit=250)),
        x=alt.X(f"{waarde}:Q", title=titel),
        tooltip=[categorie, alt.Tooltip(waarde, format=formaat)],
    )
    balken = basis.mark_bar(color=ACCENT, cornerRadiusEnd=4)
    labels = basis.mark_text(align="left", dx=4).encode(text=alt.Text(f"{waarde}:Q", format=formaat))
    return (balken + labels).properties(height=max(120, 32 * len(df) + 40))


# Pagina
st.title("📇 Contactgegevens van Kamerleden")
st.caption("Overzicht per contactsoort en per fractie.")

# Kerncijfers
top_soort = tabel_soort.iloc[0] if not tabel_soort.empty else None
top_fractie = tabel_fractie.iloc[0] if not tabel_fractie.empty else None

kolommen = st.columns(4)
kaarten = [
    ("Personen", f"{(dim_persoon['persoon_id'] != '-1').sum():,}".replace(",", "."), None),
    ("Contactgegevens", f"{int(fact_contact['contact_count'].sum()):,}".replace(",", "."), None),
    ("Meest gebruikte soort",
     top_soort["soort"] if top_soort is not None else "-",
     f"{int(top_soort['Aantal'])} contactgegevens" if top_soort is not None else None),
    ("Hoogste gemiddelde per fractie",
     top_fractie["Fractie"] if top_fractie is not None else "-",
     f"{top_fractie['Gemiddeld aantal']} gemiddeld" if top_fractie is not None else None),
]
for kolom, (label, waarde, delta) in zip(kolommen, kaarten):
    with kolom, st.container(border=True):
        st.metric(label, waarde, delta, delta_color="off")

# Het maken van 3 tabladen in de dashboard
st.write("")
tab1, tab2, tab3 = st.tabs(["📊 Per soort", "🏛️ Per fractie", "🔎 Soort per fractie"])

with tab1:
    st.subheader("Aantal contactgegevens per soort")
    st.caption("Contactgegevens die het meeste worden gebruikt")
    links, rechts = st.columns([3, 2])
    with links:
        st.altair_chart(staafgrafiek(tabel_soort, "soort", "Aantal", "Aantal contactgegevens"),
                        use_container_width=True)
    with rechts:
        st.dataframe(tabel_soort.rename(columns={"soort": "Soort"}), hide_index=True,
                     use_container_width=True)

with tab2:
    st.subheader("Gemiddeld aantal contactgegevens per fractie")
    st.caption("Gemiddelde over alle personen die ooit in de fractie zaten; "
               "personen zonder contactgegevens tellen mee als 0.")
    links, rechts = st.columns([3, 2])
    with links:
        st.altair_chart(
            staafgrafiek(tabel_fractie, "Fractie", "Gemiddeld aantal", "Gemiddeld aantal contactgegevens", ".1f"),
            use_container_width=True,
        )
    with rechts:
        st.dataframe(tabel_fractie, hide_index=True, use_container_width=True)

with tab3:
    st.subheader("Meest gebruikte contactsoort per fractie")
    st.caption("Weergave van fracties en welke contactsoort die het meest gebruiken")
    links, rechts = st.columns([2, 3])
    with links:
        st.dataframe(
            tabel_top_soort[["Fractie", "Meest gebruikte soort", "Aantal", "Aandeel (%)"]],
            hide_index=True,
            use_container_width=True,
            column_config={
                "Aandeel (%)": st.column_config.ProgressColumn(
                    "Aandeel (%)", min_value=0, max_value=100, format="%.1f%%"
                )
            },
        )
    with rechts:
        st.caption("Aandeel van elke soort binnen de fractie (%)")
        basis = alt.Chart(per_fractie_soort).encode(
            x=alt.X("soort:N", title=None, axis=alt.Axis(labelAngle=-30)),
            y=alt.Y("Fractie:N", title=None, sort=alt.EncodingSortField("Aantal", op="sum", order="descending")),
        )
        heat = basis.mark_rect().encode(
            color=alt.Color("Aandeel (%):Q", scale=alt.Scale(scheme="blues"), legend=None),
            tooltip=["Fractie", "soort", "Aantal", "Aandeel (%)"],
        )
        tekst = basis.mark_text(fontSize=11).encode(
            text=alt.Text("Aandeel (%):Q", format=".0f"),
            color=alt.condition(alt.datum["Aandeel (%)"] > 50, alt.value("white"), alt.value("black")),
        )
        st.altair_chart(
            (heat + tekst).properties(height=max(150, 30 * per_fractie_soort["Fractie"].nunique() + 60)),
            use_container_width=True,
        )

st.divider()
st.caption("Bron: Tweede Kamer open data · gold-laag (stermodel) uit DuckDB, ingelezen als CSV")
