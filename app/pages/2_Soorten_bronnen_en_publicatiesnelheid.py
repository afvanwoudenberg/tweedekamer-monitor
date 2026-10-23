import altair as alt
import streamlit as st
from csv_data import laad

st.title("Soorten bronnen en Publicatiesnelheid")

def nl(getal):
    return f"{getal:,.0f}".replace(",", ".")

# CSV's inlezen
fact = laad("fact_document_publicatie")
bron = laad("fact_bronvermelding")
docs = laad("dim_document")
fact["jaar"] = fact["datum"].dt.year

# Rij 1, twee slicers
min_jaar = int(fact["jaar"].min())
max_jaar = int(fact["jaar"].max())
soorten = sorted(fact["soort"].dropna().unique())

s1, s2 = st.columns(2)
gekozen = s1.multiselect("Documentsoort (leeg = alle)", soorten)
van, tot = s2.slider("Jaar", min_jaar, max_jaar, (min_jaar, max_jaar))

# Filteren
f = fact[(fact["jaar"] >= van) & (fact["jaar"] <= tot)]
if gekozen:
    f = f[f["soort"].isin(gekozen)]
b = bron[bron["document_id"].isin(f["document_id"])]
gepubliceerd = f[f["publicatiedatum"].notna()]

# Data klaarmaken
bron_soorten = (
    b["bron_document_soort"].dropna().value_counts().head(15)
    .rename_axis("soort").reset_index(name="aantal")
)

if bron_soorten.empty or gepubliceerd.empty:
    st.info("Geen gegevens voor deze selectie.")
    st.stop()

# Rij 2, twee cards
k1, k2 = st.columns(2)
k1.metric("Meest gebruikte soort als bron", bron_soorten["soort"][0])
k1.caption(f"{nl(bron_soorten['aantal'][0])} keer als bron")

if len(bron_soorten) > 1:
    k2.metric("Tweede meest gebruikte soort als bron", bron_soorten["soort"][1])
    k2.caption(f"{nl(bron_soorten['aantal'][1])} keer als bron")
else:
    k2.metric("Tweede meest gebruikte soort als bron", "-")

# Rij 3, horizontale bar chart
st.subheader("Top 15 soorten documenten als bron")
chart_bron = alt.Chart(bron_soorten).mark_bar().encode(
    x=alt.X("aantal:Q", title="Aantal keer als bron"),
    y=alt.Y("soort:N", sort="-x", title=None, axis=alt.Axis(labelLimit=300)),
    tooltip=["soort", "aantal"],
)
st.altair_chart(chart_bron, use_container_width=True)

# Rij 4, card links + overzicht rechts
dagen = gepubliceerd["dagen_tot_publicatie"]

c1, c2 = st.columns([1, 2])
c1.metric("Gem. dagen tot publicatie", nl(dagen.mean()))

o1, o2, o3 = c2.columns(3)
o1.metric("Mediaan (dagen)", nl(dagen.median()))
o2.metric("Min / max (dagen)", f"{nl(dagen.min())} / {nl(dagen.max())}")
o3.metric("Aantal documenten", nl(len(gepubliceerd)))

# Rij 5, histogram en bar chart
hist = (
    (dagen // 100 * 100).astype(int).value_counts().sort_index()
    .rename_axis("start").reset_index(name="aantal")
)
per_soort = (
    gepubliceerd.groupby("soort")["dagen_tot_publicatie"].mean()
    .sort_values(ascending=False).head(15)
    .reset_index(name="gemiddeld")
)

g1, g2 = st.columns(2)

g1.subheader("Verdeling dagen tot publicatie")
chart_hist = alt.Chart(hist).mark_bar().encode(
    x=alt.X("start:O", title="Dagen tot publicatie (blokken van 100)"),
    y=alt.Y("aantal:Q", title="Aantal documenten"),
    tooltip=["start", "aantal"],
)
g1.altair_chart(chart_hist, use_container_width=True)

g2.subheader("Gemiddeld aantal dagen per documentsoort")
chart_soort = alt.Chart(per_soort).mark_bar().encode(
    x=alt.X("gemiddeld:Q", title="Gemiddeld aantal dagen"),
    y=alt.Y("soort:N", sort="-x", title=None, axis=alt.Axis(labelLimit=300)),
    tooltip=["soort", "gemiddeld"],
)
g2.altair_chart(chart_soort, use_container_width=True)

# Rij 6, tabel en bar chart
tabel = (
    gepubliceerd.merge(docs, on="document_id", how="left")
    .sort_values("dagen_tot_publicatie", ascending=False)
    .head(20)
)
tabel["titel"] = tabel["titel"].fillna("(geen titel)")
tabel["datum"] = tabel["datum"].dt.date
tabel["publicatiedatum"] = tabel["publicatiedatum"].dt.date

met_zonder = (
    f["document_type"].isna()
    .map({True: "Zonder documenttype", False: "Met documenttype"})
    .value_counts().rename_axis("type").reset_index(name="aantal")
)

t1, t2 = st.columns(2)

t1.subheader("Top 20 met de meeste dagen tot publicatie")
t1.dataframe(
    tabel[["titel", "soort", "datum", "publicatiedatum", "dagen_tot_publicatie"]].rename(columns={
        "titel": "Titel", "soort": "Soort", "datum": "Documentdatum",
        "publicatiedatum": "Publicatiedatum", "dagen_tot_publicatie": "Dagen tot publicatie",
    }),
    hide_index=True,
    use_container_width=True,
)

t2.subheader("Publicaties met en zonder documenttype")
volgorde = ["Met documenttype", "Zonder documenttype"]
chart_type = alt.Chart(met_zonder).mark_bar().encode(
    x=alt.X("type:N", sort=volgorde, title=None, axis=alt.Axis(labelAngle=0)),
    y=alt.Y("aantal:Q", title="Aantal publicaties"),
    color=alt.Color(
        "type:N",
        scale=alt.Scale(domain=volgorde, range=["#1f77b4", "#ff7f0e"]),
        legend=None,
    ),
    tooltip=["type", "aantal"],
)
t2.altair_chart(chart_type, use_container_width=True)