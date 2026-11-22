from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

# Pagina instellingen, in de hoofdapp staat dit al
try:
    st.set_page_config(page_title="Dashboard Tweede Kamer", page_icon="🏛️", layout="wide")
except Exception:
    pass

DATA_DIR = Path(__file__).resolve().parent / "Data_commissies"
FUNCTIES = {
    "OnderVz": "Ondervoorzitter",
    "PlvLid": "Plaatsvervangend lid",
    "EersteOndVzTk": "Eerste ondervoorzitter",
    "TweedeOndVzTk": "Tweede ondervoorzitter",
}


@st.cache_data
def laad_data() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    # De CSV bestanden zijn de feit en dimensietabellen van het ster ontwerp
    commissies = pd.read_csv(DATA_DIR / "dim_commissie.csv")
    personen = pd.read_csv(DATA_DIR / "dim_persoon.csv")
    datum = pd.read_csv(DATA_DIR / "dim_datum.csv")
    zittingen = pd.read_csv(DATA_DIR / "fact_commissie_zitting.csv")
    activiteiten = pd.read_csv(DATA_DIR / "fact_commissie_activiteit.csv")
    zaken = pd.read_csv(DATA_DIR / "fact_commissie_zaak.csv")

    # Korte naam voor in de grafieken, de volledige naam blijft in naam_nl
    commissies["naam_nl"] = commissies["naam_nl"].fillna(commissies["afkorting"]).fillna("Onbekend")
    commissies["label"] = (
        commissies["naam_nl"]
        .str.replace("Vaste commissie voor ", "")
        .str.replace("Tijdelijke commissie ", "Tijdelijk ")
        .str[:40]
    )
    namen = commissies[["commissie_id", "label", "naam_nl"]]

    # Zittende leden van actieve commissies, met persoon en commissienaam erbij
    actief = commissies.loc[commissies["is_actief"], "commissie_id"]
    leden = (
        zittingen[zittingen["is_huidig"] & zittingen["commissie_id"].isin(actief)]
        .merge(personen, on="persoon_id", how="left")
        .merge(namen, on="commissie_id", how="left")
    )
    leden["vrouw"] = leden["geslacht"].str.lower() == "vrouw"
    leden["functie"] = leden["functie"].replace(FUNCTIES).fillna("Onbekend")

    # Activiteiten en zaken met jaar en maand uit dim_datum
    activiteiten = (
        activiteiten.merge(datum[["datum_id", "jaar", "maand"]], on="datum_id", how="left")
        .merge(namen, on="commissie_id", how="left")
    )
    zaken = zaken.merge(datum[["datum_id", "jaar"]], on="datum_id", how="left")
    return commissies, leden, activiteiten, zaken


commissies, leden, activiteiten, zaken = laad_data()

# Filters in de zijbalk
st.sidebar.header("Filters")

types = sorted(commissies["commissietype"].unique())
gekozen_types = st.sidebar.multiselect(
    "Soort commissie", types, default=types,
    help="Het type is afgeleid van de naam van de commissie.",
)
alleen_actief = st.sidebar.checkbox("Alleen actieve commissies", value=True)

selectie = commissies[commissies["commissietype"].isin(gekozen_types)]
if alleen_actief:
    selectie = selectie[selectie["is_actief"]]

# Bij een gekozen commissie gaat de hele pagina over alleen die commissie
opties = sorted(selectie.loc[selectie["commissie_id"].isin(leden["commissie_id"]), "naam_nl"])
keuze = st.sidebar.selectbox("Zoom in op een commissie", ["Alle commissies"] + opties)
een_commissie = keuze != "Alle commissies"
if een_commissie:
    selectie = selectie[selectie["naam_nl"] == keuze]

jaar_min = int(activiteiten["jaar"].min())
jaar_max = int(activiteiten["jaar"].max())
gekozen_jaren = st.sidebar.slider(
    "Jaren", jaar_min, jaar_max, (jaar_min, jaar_max), help="Geldt voor activiteiten en zaken."
)

# Dezelfde selectie voor leden, activiteiten en zaken
ids = selectie["commissie_id"]
df_leden = leden[leden["commissie_id"].isin(ids)]
df_act = activiteiten[activiteiten["commissie_id"].isin(ids) & activiteiten["jaar"].between(*gekozen_jaren)]
df_zaken = zaken[zaken["commissie_id"].isin(ids) & zaken["jaar"].between(*gekozen_jaren)]
personen = df_leden.drop_duplicates("persoon_id")

st.title("Commissies")
if df_leden.empty:
    st.warning("Geen gegevens voor deze filters.")
    st.stop()

# KPI's over de leden
st.subheader("Wie zitten erin?")
kolommen = st.columns(4)
kolommen[0].metric("Commissies", len(selectie))
kolommen[1].metric(
    "Personen in een commissie", len(personen), help="Iemand in meerdere commissies telt een keer."
)
kolommen[2].metric("Gemiddelde leeftijd", f"{personen['leeftijd'].mean():.1f}".replace(".", ",") + " jaar")
kolommen[3].metric("Aandeel vrouwen", f"{personen['vrouw'].mean() * 100:.0f}%")

# KPI's over de activiteiten en zaken
st.subheader("Wat doen ze?")
vandaag = int(pd.Timestamp.today().strftime("%Y%m%d"))
verleden = df_act[df_act["datum_id"] <= vandaag]
kolommen = st.columns(3)
kolommen[0].metric("Activiteiten", f"{len(df_act):,}".replace(",", "."), help="Inclusief geplande activiteiten.")
kolommen[1].metric(
    "Uitgevoerd",
    f"{verleden['is_uitgevoerd'].mean() * 100:.0f}%" if len(verleden) else "-",
    help="Aandeel uitgevoerd tot en met vandaag. Verplaatst of geannuleerd telt als niet uitgevoerd.",
)
kolommen[2].metric(
    "Zaken met een besluit",
    f"{df_zaken['zaak_id'].nunique():,}".replace(",", "."),
    help="Aantal verschillende zaken waarover een besluit is genomen.",
)

st.divider()

# Voorzitters en ondervoorzitters per geslacht, gewone leden laten we weg
leiding = df_leden[~df_leden["functie"].isin(["Lid", "Plaatsvervangend lid", "Onbekend"])]
per_functie = leiding.groupby(["functie", "geslacht"]).size().reset_index(name="aantal")
fig_leiding = px.bar(
    per_functie, x="aantal", y="functie", color="geslacht", orientation="h",
    labels={"aantal": "Aantal personen", "geslacht": "Geslacht"},
)
fig_leiding.update_layout(yaxis_title=None, yaxis={"categoryorder": "total ascending"})

# Grafieken, bij een gekozen commissie zie je de samenstelling van die commissie
if een_commissie:
    links, rechts = st.columns(2)
    with links:
        st.subheader("Man en vrouw")
        per_geslacht = personen["geslacht"].fillna("Onbekend").value_counts().rename_axis("geslacht").reset_index(name="aantal")
        fig = px.pie(per_geslacht, names="geslacht", values="aantal", hole=0.5)
        st.plotly_chart(fig, width="stretch")
    with rechts:
        st.subheader("Wie leidt de commissie?", help="Alleen voorzitters en ondervoorzitters.")
        fig_leiding.update_xaxes(dtick=1)
        st.plotly_chart(fig_leiding, width="stretch")
else:
    links, rechts = st.columns([2, 3])
    with links:
        st.subheader("Soorten commissies")
        per_type = selectie["commissietype"].value_counts().rename_axis("type").reset_index(name="aantal")
        fig = px.pie(per_type, names="type", values="aantal", hole=0.5)
        st.plotly_chart(fig, width="stretch")
    with rechts:
        st.subheader("Grootste commissies")
        grootste = (
            df_leden.groupby(["label", "naam_nl"])["persoon_id"].nunique()
            .nlargest(10).reset_index(name="leden").sort_values("leden")
        )
        fig = px.bar(
            grootste, x="leden", y="label", orientation="h", text_auto=True,
            hover_name="naam_nl", labels={"leden": "Aantal leden"},
        )
        fig.update_layout(yaxis_title=None)
        st.plotly_chart(fig, width="stretch")

    links, rechts = st.columns(2)
    with links:
        st.subheader("Vrouwen in de grootste commissies")
        vrouwen = (
            df_leden.groupby(["label", "naam_nl"])
            .agg(leden=("persoon_id", "nunique"), vrouwen=("vrouw", "mean"))
            .nlargest(10, "leden").reset_index()
        )
        vrouwen["vrouwen"] = (vrouwen["vrouwen"] * 100).round(0)
        fig = px.bar(
            vrouwen.sort_values("vrouwen"), x="vrouwen", y="label", orientation="h", text_auto=True,
            hover_name="naam_nl", range_x=[0, 100], labels={"vrouwen": "% vrouwen"},
        )
        fig.add_vline(x=50, line_dash="dash")
        fig.update_layout(yaxis_title=None)
        st.plotly_chart(fig, width="stretch")
    with rechts:
        st.subheader("Wie leidt de commissies?", help="Alleen voorzitters en ondervoorzitters.")
        st.plotly_chart(fig_leiding, width="stretch")

links, rechts = st.columns([3, 2])
with links:
    st.subheader("Wanneer is het druk?")
    maand = df_act.groupby(["jaar", "maand"]).size().reset_index(name="aantal")
    maand["periode"] = pd.to_datetime(dict(year=maand["jaar"], month=maand["maand"], day=1))
    fig = px.line(maand, x="periode", y="aantal", markers=True, labels={"aantal": "Aantal activiteiten"})
    fig.update_layout(xaxis_title=None)
    st.plotly_chart(fig, width="stretch")
with rechts:
    st.subheader("Wat gebeurt er met activiteiten?")
    per_status = df_act["status"].fillna("Onbekend").value_counts().rename_axis("status").reset_index(name="aantal")
    fig = px.pie(per_status, names="status", values="aantal", hole=0.5)
    st.plotly_chart(fig, width="stretch")

if not een_commissie:
    st.subheader("Welke commissies zijn het drukst?")
    drukst = (
        df_act.groupby(["label", "naam_nl"]).size()
        .nlargest(10).reset_index(name="aantal").sort_values("aantal")
    )
    fig = px.bar(
        drukst, x="aantal", y="label", orientation="h", text_auto=True,
        hover_name="naam_nl", labels={"aantal": "Aantal activiteiten"},
    )
    fig.update_layout(yaxis_title=None)
    st.plotly_chart(fig, width="stretch")

st.divider()

# Tabel met alle commissies in de selectie
st.subheader("Alle commissies")
tabel = selectie[["naam_nl", "afkorting", "commissietype", "datum_actief", "datum_inactief"]].copy()
tabel["Leden nu"] = selectie["commissie_id"].map(df_leden.groupby("commissie_id")["persoon_id"].nunique()).fillna(0).astype(int)
tabel["Activiteiten"] = selectie["commissie_id"].map(df_act.groupby("commissie_id").size()).fillna(0).astype(int)
tabel.columns = ["Commissie", "Afkorting", "Type", "Actief sinds", "Opgeheven op", "Leden nu", "Activiteiten"]
st.dataframe(tabel.sort_values("Leden nu", ascending=False), width="stretch", hide_index=True, height=320)

# Tabel met alle zittende leden in de selectie
st.subheader("Wie zitten erin?")
st.dataframe(
    df_leden[["label", "achternaam", "geslacht", "leeftijd", "functie"]]
    .rename(columns={
        "label": "Commissie", "achternaam": "Achternaam", "geslacht": "Geslacht",
        "leeftijd": "Leeftijd", "functie": "Functie",
    })
    .sort_values(["Commissie", "Functie", "Achternaam"]),
    width="stretch", hide_index=True, height=320,
)

st.caption("Bron: open data van de Tweede Kamer.")