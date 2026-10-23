import altair as alt
import pandas as pd
import streamlit as st
from csv_data import laad

st.title("Bronvermelding (CSV)")


def nl(getal):
    return f"{getal:,.0f}".replace(",", ".")


# ---- CSV's inlezen ----
fact = laad("fact_document_publicatie")
bron = laad("fact_bronvermelding")
docs = laad("dim_document")
fact["jaar"] = fact["datum"].dt.year

# ---- Rij 1: twee slicers naast elkaar ----
min_jaar = int(fact["jaar"].min())
max_jaar = int(fact["jaar"].max())
soorten = sorted(fact["soort"].dropna().unique())

s1, s2 = st.columns(2)
van, tot = s1.slider("Jaar", min_jaar, max_jaar, (min_jaar, max_jaar))
gekozen = s2.multiselect("Documentsoort (leeg = alle)", soorten)

# ---- Filteren ----
f = fact[(fact["jaar"] >= van) & (fact["jaar"] <= tot)]
if gekozen:
    f = f[f["soort"].isin(gekozen)]
b = bron[bron["document_id"].isin(f["document_id"])]

if f.empty:
    st.info("Geen documenten voor deze selectie.")
    st.stop()

# ---- Rij 2: vier cards naast elkaar ----
pct = b["document_id"].nunique() / len(f) * 100
gem = f["dagen_tot_publicatie"].mean()

c1, c2, c3, c4 = st.columns(4)
c1.metric("Totaal documenten", nl(len(f)))
c2.metric("Totaal bronvermeldingen", nl(len(b)))
c3.metric("Percentage met bronvermelding", f"{pct:.1f}%".replace(".", ","))
c4.metric("Gem. dagen tot publicatie", "-" if pd.isna(gem) else nl(gem))

# ---- Rij 3: bar chart en line chart naast elkaar ----
docs_per_jaar = f.groupby("jaar").size().reset_index(name="aantal")

b_met_jaar = b.merge(f[["document_id", "jaar"]], on="document_id")
bronnen_per_jaar = b_met_jaar.groupby("jaar").size().reset_index(name="aantal")

g1, g2 = st.columns(2)

g1.subheader("Documenten per jaar")
bar = alt.Chart(docs_per_jaar).mark_bar().encode(
    x=alt.X("jaar:O", title="Jaar"),
    y=alt.Y("aantal:Q", title="Aantal documenten"),
    tooltip=["jaar", "aantal"],
)
g1.altair_chart(bar, use_container_width=True)

g2.subheader("Documenten en bronvermeldingen per jaar")
docs_per_jaar["reeks"] = "Documenten"
bronnen_per_jaar["reeks"] = "Bronvermeldingen"
lijn_data = pd.concat([docs_per_jaar, bronnen_per_jaar])
lijn = alt.Chart(lijn_data).mark_line(point=True).encode(
    x=alt.X("jaar:O", title="Jaar"),
    y=alt.Y("aantal:Q", title="Aantal"),
    color=alt.Color("reeks:N", title=None),
    tooltip=["jaar", "reeks", "aantal"],
)
g2.altair_chart(lijn, use_container_width=True)

# ---- Top 20 meest geciteerde documenten ----
top = (
    b.groupby("bron_document_id", dropna=False)
    .agg(aantal_verwijzingen=("document_id", "size"), soort=("bron_document_soort", "first"))
    .reset_index()
    .merge(docs, left_on="bron_document_id", right_on="document_id", how="left")
    .sort_values("aantal_verwijzingen", ascending=False)
    .head(20)
)
top["titel"] = top["titel"].fillna("(geen titel)")

if top.empty:
    st.info("Geen bronvermeldingen voor deze selectie.")
    st.stop()

# ---- Rij 4: twee cards naast elkaar ----
vaakst = top.iloc[0]
pct_vaakst = vaakst["aantal_verwijzingen"] / len(b) * 100

k1, k2 = st.columns(2)
k1.caption("Meest geciteerde document")
k1.markdown(vaakst["titel"])
k1.caption(f"{nl(vaakst['aantal_verwijzingen'])} verwijzingen")
k2.metric("Aandeel meest geciteerde document van alle bronvermeldingen", f"{pct_vaakst:.2f}%".replace(".", ","))

# ---- Rij 5: horizontale bar chart en tabel naast elkaar ----
t1, t2 = st.columns(2)

t1.subheader("Top 20 meest geciteerde documenten")
top["label"] = [f"{i + 1}. {t[:50]}" for i, t in enumerate(top["titel"])]
top_chart = alt.Chart(top).mark_bar().encode(
    x=alt.X("aantal_verwijzingen:Q", title="Aantal verwijzingen"),
    y=alt.Y("label:N", sort="-x", title=None),
    tooltip=["titel", "soort", "aantal_verwijzingen"],
)
t1.altair_chart(top_chart, use_container_width=True)

t2.subheader("Tabel")
t2.dataframe(
    top[["titel", "soort", "aantal_verwijzingen"]].rename(columns={
        "titel": "Titel", "soort": "Soort", "aantal_verwijzingen": "Aantal verwijzingen",
    }),
    hide_index=True,
    use_container_width=True,
)