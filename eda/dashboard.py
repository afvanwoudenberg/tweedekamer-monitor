import json #geoJSON bestanden inlezen
import pandas as pd 
import plotly.express as px
import streamlit as st
import geopandas as gpd
import pandas as pd


#pagina instellingen bepalen: Tilte en de layout
st.set_page_config(page_title="Geboorte- en woonplaats Kamerleden", layout="wide")


#python dictionary 
WEERGAVE = {"'s-Gravenhage": "Den Haag", "'s-Hertogenbosch": "Den Bosch"}
 
#data inladen
@st.cache_data
def laad_data():
    persoon = pd.read_csv("data/dim_persoon.csv")
    gemeente = pd.read_csv("data/dim_gemeente.csv").drop_duplicates("gemeentecode")
    gemeente["gemeente_weergave"] = gemeente["gemeente"].replace(WEERGAVE)
 
    if "geboortejaar" not in persoon.columns:
        d = pd.to_datetime(persoon["geboortedatum"], errors="coerce")
        persoon["geboortejaar"] = d.dt.year
    persoon["decennium"] = persoon["geboortejaar"] // 10 * 10
 
    with open("data/provincies.geojson", encoding="utf-8") as f:
        geo_prov = json.load(f)
    with open("data/gemeenten.geojson", encoding="utf-8") as f:
        geo_gem = json.load(f)
    return persoon, gemeente, geo_prov, geo_gem
 
 
persoon, gemeente, geo_prov, geo_gem = laad_data()
gem_naar_prov = gemeente.set_index("gemeentecode")["provincie"]
 
#filters in de sidebar op links
st.sidebar.header("Filters")

#persoon was het dataframe met alle informatie over een eerst-, tweede- of oudkamerleden
df = persoon.copy()

#in de sidebar sorteren op eerste, tweede, oudkamerleden  
if "functie" in df.columns:
    opties = sorted(df["functie"].dropna().unique())
    keuze = st.sidebar.multiselect("Functie", opties, default=opties)
    df = df[df["functie"].isin(keuze)]

#slider om in te delen op kamerleden in een bepaalde periode 
dec_min = int(persoon["decennium"].min())
dec_max = int(persoon["decennium"].max())
dec = st.sidebar.slider("Geboortedecennium", dec_min, dec_max, (dec_min, dec_max), step=10)
if dec != (dec_min, dec_max):
    df = df[df["decennium"].between(dec[0], dec[1])]
#bij het volledige bereik blijven de 2 personen zonder geboortedatum meegeteld


#radio laat gebruiker precies 1 optie kiezen
niveau = st.sidebar.radio("Kaartniveau", ["Provincie", "Gemeente"])
soort = st.sidebar.radio("Wat tonen?", ["Geboorteplaats", "Woonplaats"])
prefix = "geboorte" if soort == "Geboorteplaats" else "woon"
 
#titel en noemers
st.title("Waar komen Kamerleden vandaan, en waar wonen ze?")
 
if df.empty:
    st.warning("Geen personen binnen deze filters.")
    st.stop()

#personen tellen en andere belangrijke getallen klaar zetten voor het dashboard
n = len(df)
n_geb = int(df["geboorte_status"].isin(["gematcht", "niet gevonden", "niet eenduidig"]).sum())
n_geb_ok = int((df["geboorte_status"] == "gematcht").sum())
n_woon = int(df["woon_status"].isin(["gematcht", "niet gevonden", "niet eenduidig"]).sum())
n_woon_ok = int((df["woon_status"] == "gematcht").sum())

#getallen komen bovenaan te staan als 5 cards
c = st.columns(5)
c[0].metric("Personen", f"{n}")
c[1].metric("Geboorteplaats ingevuld", f"{n_geb}", f"{100 * n_geb / n:.0f}%", delta_color="off")
c[2].metric("Geboorteplaats aan gemeente gekoppeld", f"{n_geb_ok}", f"{100 * n_geb_ok / n:.0f}%", delta_color="off")
c[3].metric("Woonplaats ingevuld", f"{n_woon}", f"{100 * n_woon / n:.0f}%", delta_color="off")
c[4].metric("Woonplaats aan gemeente gekoppeld", f"{n_woon_ok}", f"{100 * n_woon_ok / n:.0f}%", delta_color="off")
st.caption(
    "Percentages zijn aandeel van alle personen binnen de filters. Voor oudere geboortejaren "
    "is geboorteplaats vaak niet vastgelegd, dus de kaart laat vooral de twintigste eeuw zien."
)
 
 
#hulpfuncties
def tel(frame, pre, lvl): #frame= dataframe, pre= geboorte of woonplek, #lvl= gemeente provincie
    """Aantal gematchte personen per provincie of gemeente."""
    #filteren op pre en daarna personentabel aan gemeentetabelkoppelen via gemeentecode; soort SQL left join
    g = frame[frame[f"{pre}_status"] == "gematcht"].merge(
        gemeente, left_on=f"{pre}_gemeentecode", right_on="gemeentecode", how="left"
    )
    #als provincie, dan groeperen 
    if lvl == "Provincie":
        t = g.groupby(["provinciecode", "provincie"]).size().rename("aantal").reset_index()
        #kolommen hernoemen is makkelijker mee te werken
        t = t.rename(columns={"provinciecode": "code", "provincie": "naam"})
        #alle zorgt ervoor dat ook provincies waar niemand in woont, voorkomen in het dashboard
        alle = gemeente[["provinciecode", "provincie"]].drop_duplicates()
        alle = alle.rename(columns={"provinciecode": "code", "provincie": "naam"})
        #NA waarden worden vervangen voor 0
        t = alle.merge(t, on=["code", "naam"], how="left").fillna({"aantal": 0})
    else:
        t = g.groupby(["gemeentecode", "gemeente_weergave"]).size().rename("aantal").reset_index()
        t = t.rename(columns={"gemeentecode": "code", "gemeente_weergave": "naam"})
    t["aantal"] = t["aantal"].astype(int)
    totaal = t["aantal"].sum()
    t["aandeel_%"] = (100 * t["aantal"] / totaal).round(1) if totaal else 0.0
    return t
 
 
tab_kaart, tab_top, tab_vergelijk, tab_status = st.tabs(
    ["Kaart", "Top gemeenten", "Geboorte vs woon", "Matchstatus"]
)
 
#tab 1: kaart
with tab_kaart:
    t = tel(df, prefix, niveau)
    geo = geo_prov if niveau == "Provincie" else geo_gem
    noemer = n_geb_ok if prefix == "geboorte" else n_woon_ok
    st.subheader(f"{soort} per {niveau.lower()} (n = {noemer} gekoppeld)")
    fig = px.choropleth_map(
        t,
        geojson=geo,
        locations="code",
        featureidkey="properties.code",
        color="aantal",
        hover_name="naam",
        hover_data={"code": False, "aantal": True, "aandeel_%": True},
        map_style="carto-positron",
        center={"lat": 52.2, "lon": 5.3},
        zoom=6.2,
        opacity=0.8,
        color_continuous_scale="Blues",
    )
    fig.update_layout(margin=dict(l=0, r=0, t=0, b=0), height=650)
    st.plotly_chart(fig, use_container_width=True)
 
#tab 2: top gemeenten
with tab_top:
    aantal_top = st.slider("Aantal gemeenten", 5, 40, 15)
    kol = st.columns(2)
    for kolom, pre, titel in ((kol[0], "geboorte", "Geboorteplaats"), (kol[1], "woon", "Woonplaats")):
        t = tel(df, pre, "Gemeente").nlargest(aantal_top, "aantal").sort_values("aantal")
        f = px.bar(t, x="aantal", y="naam", orientation="h", title=titel,
                   hover_data={"aandeel_%": True})
        f.update_layout(yaxis_title=None, height=120 + 24 * aantal_top)
        kolom.plotly_chart(f, use_container_width=True)
 
#tab 3: geboorte vs woon
with tab_vergelijk:
    beide = df[(df["geboorte_status"] == "gematcht") & (df["woon_status"] == "gematcht")].copy()
    st.write(f"Alleen personen met zowel een gekoppelde geboorte- als woonplaats: **n = {len(beide)}**.")
    if beide.empty:
        st.info("Geen personen met beide gegevens binnen deze filters.")
    else:
        beide["geboorteprovincie"] = beide["geboorte_gemeentecode"].map(gem_naar_prov)
        beide["woonprovincie"] = beide["woon_gemeentecode"].map(gem_naar_prov)
        zelfde = (beide["geboorteprovincie"] == beide["woonprovincie"]).mean()
        st.metric("Woont in dezelfde provincie als geboorte", f"{100 * zelfde:.1f}%")
 
        ct = pd.crosstab(beide["geboorteprovincie"], beide["woonprovincie"])
        f = px.imshow(ct, text_auto=True, aspect="auto", color_continuous_scale="Blues",
                      labels=dict(x="Woonprovincie", y="Geboorteprovincie", color="Personen"))
        f.update_layout(height=600)
        st.plotly_chart(f, use_container_width=True)
        st.caption(
            "Let op: woonplaats is voor veel oud-Kamerleden niet vastgelegd en geeft niet altijd "
            "de woonplaats tijdens hun Kamerlidmaatschap."
        )
 
#  tab 4: matchstatus
with tab_status:
    st.write("Hoeveel personen vallen in welke categorie? Dit zijn de noemers achter de kaarten.")
    rij = []
    for pre, titel in (("geboorte", "Geboorteplaats"), ("woon", "Woonplaats")):
        vc = df[f"{pre}_status"].value_counts()
        for status, aantal in vc.items():
            rij.append({"soort": titel, "status": status, "aantal": int(aantal),
                        "aandeel_%": round(100 * aantal / n, 1)})
    st.dataframe(pd.DataFrame(rij), use_container_width=True, hide_index=True)
    st.caption(
        "'niet gevonden' is vooral buitenland en oude gemeenten. 'niet eenduidig' zijn plaatsnamen "
        "die in meerdere gemeenten voorkomen (zoals Hengelo en Oosterhout)."
    )