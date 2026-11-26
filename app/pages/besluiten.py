import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from datetime import datetime, timedelta
from pathlib import Path

#---------------------------------------------
# Data inladen
#---------------------------------------------

# Pad naar CVS bestanden
DATA_DIR = Path(__file__).resolve().parents[1] / "agendapunten_besluitvorming" / "CVS_files"

for csv_file in DATA_DIR.glob("*.csv"):
    variable_name = f"{csv_file.stem}"
    globals()[variable_name] = pd.read_csv(csv_file)

# Rijen met ngative duraties verwijderen
fact_activiteit = fact_activiteit[fact_activiteit.duur_minuten >= 0]
fact_activiteit_besluit = fact_activiteit_besluit[fact_activiteit_besluit.duur_minuten >= 0]

# Omzetten juiste datatypes
fact_activiteit["datum"] = pd.to_datetime(fact_activiteit["datum"])

dim_activiteit["datum"] = pd.to_datetime(dim_activiteit["datum"])
dim_activiteit["aanvangstijd"] = pd.to_datetime(dim_activiteit["aanvangstijd"])
dim_activiteit["eindtijd"] = pd.to_datetime(dim_activiteit["eindtijd"])

dim_fractie["datum_actief"] = pd.to_datetime(dim_fractie["datum_actief"])
dim_fractie["datum_inactief"] = pd.to_datetime(dim_fractie["datum_inactief"])

# normaliseren
dim_besluit['uitkomst'] = dim_besluit['uitkomst'].str.lower()

#---------------------------------------------
# Filters (in sidebar)
#---------------------------------------------

# datum filter
min_date = min(fact_activiteit['datum'])
max_date = max(fact_activiteit['datum'])

all_dates = st.sidebar.checkbox("Alle datums", value=True)

if all_dates:
    datums = (min_date, max_date)
else:
    datums = st.sidebar.date_input(
        'Selecteer de gewenste datums',
        value=(min_date, max_date),
        min_value=min_date,
        max_value=max_date,
        format='DD/MM/YYYY')    

# Besluit soort filter
besluit_soorten = st.sidebar.multiselect(
    "Besluit soorten",
    dim_besluit['uitkomst'].dropna().unique().tolist(),
    default = dim_besluit['uitkomst'].dropna().unique().tolist())

# Fracties filter
nu_fracties = dim_fractie.loc[dim_fractie['datum_inactief'
    ].isna(), 'fractie_norm'].reset_index(drop=True)
oude_fracties = dim_fractie.loc[~dim_fractie['fractie_norm'
    ].isin(nu_fracties), 'fractie_norm'].reset_index(drop=True)

all_fracties = st.sidebar.checkbox("Alle fracties (ook inactieve fracties)", 
                                   value = True)

if all_fracties:
    fracties = dim_fractie['fractie_norm'].dropna().unique().tolist()
else:
    huidige_fracties = st.sidebar.multiselect(
        "Huidige fracties",
        sorted(nu_fracties.tolist()))

    inactieve_fracties = st.sidebar.multiselect(
        "Oude fracties",
        sorted(oude_fracties.tolist()))

    fracties = huidige_fracties + inactieve_fracties

###
# Voorkomen error weergave tijdens instellen filters
###

# Checked of de datumselectie incompleet is
# Geeft aan wat moet gebeuren om dashboard te laden de 
if len(datums) != 2:
    st.warning("Selecteer een startdatum en een einddatum om het dashboard te laden.")

# Checked besluitenfilter leeg is
# Geeft aan wat moet gebeuren om dashboard te laden 
if len(besluit_soorten) == 0:
    st.warning("Selecteer minstens 1 besluitsoort om het dashboard te laden.")

# Checked fractiefilter leeg is
# Geeft aan wat moet gebeuren om dashboard te laden 
if len(fracties) == 0:
    st.warning("Selecteer minstens 1 fractie om het dashboard te laden.")

# Stopt het laden van het dashboard als 1 van de filters incorrect is
if len(datums) != 2 or len(besluit_soorten) == 0 or len(fracties) == 0:
    st.stop()
    
###
# Filters toepassen
###

# ID's selecteren die onder de filter instellingen passen
selected_activiteit_ids = fact_activiteit.loc[
    fact_activiteit['datum'].between(
        pd.to_datetime(datums[0]), pd.to_datetime(datums[1])), 'activiteit_id']

selected_besluit_ids = dim_besluit.loc[
    dim_besluit['uitkomst'].isin(besluit_soorten), 'besluit_id']

selected_fractie_ids = dim_fractie.loc[
    dim_fractie['fractie_norm'].isin(fracties), 'fractie_id']

selected_zaak_ids = set(bridge_zaak_actor.loc[
    bridge_zaak_actor['fractie_id'].isin(selected_fractie_ids), 'zaak_id'])

# Centrale feitentabel filteren
f_fact_activiteit_besluit = fact_activiteit_besluit[
    fact_activiteit_besluit['besluit_id'].isin(selected_besluit_ids)
    & fact_activiteit_besluit['zaak_id'].isin(selected_zaak_ids)
    & fact_activiteit_besluit['activiteit_id'].isin(selected_activiteit_ids)].copy()

# ID's selecteren die rekening houden met interactie filters
actual_besluit_ids = set(f_fact_activiteit_besluit['besluit_id'])
actual_zaak_ids = set(f_fact_activiteit_besluit['zaak_id'])
actual_activiteit_ids = set(f_fact_activiteit_besluit['activiteit_id'])

# Alle tabellen filteren
f_dim_activiteit = dim_activiteit[
    dim_activiteit['activiteit_id'].isin(actual_activiteit_ids)].copy()

f_fact_activiteit = fact_activiteit[
    fact_activiteit['activiteit_id'].isin(actual_activiteit_ids)].copy()

f_dim_besluit = dim_besluit[
    dim_besluit['besluit_id'].isin(actual_besluit_ids)].copy()

f_bridge_besluit_zaak = bridge_besluit_zaak[
    bridge_besluit_zaak['besluit_id'].isin(actual_besluit_ids)
    & bridge_besluit_zaak['zaak_id'].isin(actual_zaak_ids)].copy()

f_dim_zaak = dim_zaak[
    dim_zaak['zaak_id'].isin(actual_zaak_ids)].copy()

f_bridge_zaak_actor = bridge_zaak_actor[
    bridge_zaak_actor['zaak_id'].isin(actual_zaak_ids)
    & bridge_zaak_actor['fractie_id'].isin(selected_fractie_ids)].copy()

f_dim_fractie = dim_fractie[
    dim_fractie['fractie_id'].isin(selected_fractie_ids)].copy()

#---------------------------------------------
# Title and such
#---------------------------------------------

st.title("Besluiten via stemming")
st.write("Dit dashboard laat zien **welke besluiten genomen worden bij stemmingen** en **hoe deze besluiten verdeeld zijn onder de fracties**. Het geeft inzicht in welke fracties vaak zaken aandienen en wat het stemgedrag is over zaken voorgesteld door bepaalde fracties. Ook geeft het inzicht op de tijdsduur van activiteiten per besluituitkomst. Dit dashboard geeft dus **geen** inzicht op het stemgedrag van de partij zelf.")

#---------------------------------------------
# Cards
#---------------------------------------------

def format_besluit_perc(uitkomst):
    percentage = perc_besluiten.get(uitkomst)

    if percentage is None or pd.isna(percentage):
        return "-"
    return f"{percentage:.1f}%"
    
def format_besluit_duur(uitkomst):
    duur = gemiddelde_duur.loc[
        gemiddelde_duur['uitkomst'] == uitkomst, 'duur_minuten']

    if duur.empty or pd.isna(duur.iloc[0]):
        return "-"
    return f"{duur.iloc[0] / 60:.1f} uur"

# Eerste twee cards naast elkaar
col1, col2 = st.columns([1.8, 2.2])

# Percentage van soort besluit
with col1: 
    with st.container(border=True):
        st.markdown(
            "<h4 style='text-align: center;'>Totaal aantal besluiten</h4>", 
            unsafe_allow_html=True)
        st.metric("Met stemming",
              f_dim_besluit['uitkomst'].notna().sum())


perc_besluiten = (f_dim_besluit['uitkomst'].value_counts(normalize=True) * 100)

# Totaal aantal besluiten
with col2:
    with st.container(border=True):
        st.markdown(
            "<h4 style='text-align: center;'>Algemene besluitpercentages</h4>", 
            unsafe_allow_html=True)

        col_1, col_2, col_3 = st.columns(3)

        col_1.metric("Aangenomen", format_besluit_perc("aangenomen"))
        col_2.metric("Verworpen", format_besluit_perc("verworpen"))
        col_3.metric("Aangehouden", format_besluit_perc("aangehouden"))

# Gemiddelde tijd per besluit
duratie_besluiten = f_dim_besluit.merge(
    f_fact_activiteit_besluit[['besluit_id', 'duur_minuten']], 
    on='besluit_id', how='left')

gemiddelde_duur = (
    duratie_besluiten.groupby('uitkomst')['duur_minuten'].mean().reset_index())

with st.container(border=True):
    st.markdown(
        "<h4 style='text-align: center;'>Gemiddelde tijd per soort besluit</h4>",
        unsafe_allow_html=True)

    col_1, col_2, col_3 = st.columns(3)

    col_1.metric("Aangenomen", format_besluit_duur("aangenomen"))
    col_2.metric("Verworpen", format_besluit_duur("verworpen"))
    col_3.metric("Aangehouden", format_besluit_duur("aangehouden"))

#---------------------------------------------
# Dashboard graphs
#---------------------------------------------

###
# Pi plots per besluit uitkomst op fracties
###

st.header("Hoe zijn de fracties verdeeld onder de besluituitkomsten?")
st.write("De cirkeldiagrammen hieronder laten per besluituitkomst zien welke fracties hier de grootste rol in spelen. Hiermee kan een algemene blik op het Nederlandse beleid door de jaren heen gevormdt worden.")

# Dataframe maken
stemgedrag_fracties = (
    f_bridge_zaak_actor[['fractie_id', 'zaak_id']]
    .merge(
        f_dim_fractie[['fractie_id', 'fractie_norm']],
        on='fractie_id',
        how='left')
    .merge(
        f_bridge_besluit_zaak[['zaak_id', 'besluit_id']],
        on='zaak_id',
        how='left')
    .merge(
        f_dim_besluit[['besluit_id', 'uitkomst']],
        on='besluit_id',
        how='left'))

# Drie pie-charts naast elkaar, gescheiden door uitkomst
uitkomsten = ['aangenomen', 'verworpen', 'aangehouden']

plot_stemgedrag_fracties = make_subplots(
    rows=1,
    cols=3,
    specs=[[{'type': 'domain'}, {'type': 'domain'}, {'type': 'domain'}]],
    subplot_titles=[uitkomst.capitalize() for uitkomst in uitkomsten],
    horizontal_spacing=0,
    vertical_spacing=0)

# Fractie kleuren consistent houden
fracties = sorted(stemgedrag_fracties['fractie_norm'].dropna().unique())

kleuren = px.colors.sample_colorscale(
    'Turbo',
    [i / max(len(fracties) - 1, 1) for i in range(len(fracties))])

kleur_mapping = dict(zip(fracties, kleuren))

# Plots maken
for i, uitkomst in enumerate(uitkomsten, start=1):
    df = stemgedrag_fracties[stemgedrag_fracties['uitkomst'] == uitkomst]

    verdeling = df.groupby('fractie_norm').size().reset_index(name='aantal')

    plot_stemgedrag_fracties.add_trace(
        go.Pie(
            labels=verdeling['fractie_norm'],
            values=verdeling['aantal'],
            marker=dict(
            colors=[kleur_mapping[f] for f in verdeling['fractie_norm']]),
            texttemplate=[
                '%{percent}' if aantal / verdeling['aantal'].sum() > 0.04 else ''
                for aantal in verdeling['aantal']],
            textposition='inside',
            showlegend=False),
        row=1,
        col=i)

# Één gezamelijke legenda met alle fracties
for fractie in fracties:
    plot_stemgedrag_fracties.add_trace(
        go.Scatter(
            x=[None],
            y=[None],
            mode='markers',
            marker=dict(
                size=10,
                color=kleur_mapping[fractie]),
            name=fractie,
            showlegend=True))

# Layout plot (a lot of spacing stuff)
plot_stemgedrag_fracties.update_layout(
    title=dict(
        text='Besluituitkomst per zaak actor',
        x=0.5,
        xanchor='center',
        font_size=28),
    legend=dict(
        title='Fracties',
        title_font=dict(size=16),
        orientation='h',
        yanchor='top',
        xanchor='center',
        y = 0.42,
        x=0.5,
        entrywidth=0.25,
        entrywidthmode='fraction',
        itemclick=False,
        itemdoubleclick=False),
    showlegend=True,
    height=550,
    margin=dict(t=100, b=60))

plot_stemgedrag_fracties.update_traces(
    domain=dict(y=[0.45, 1]),
    selector=dict(type='pie'))

# Assen van dummyplot(legenda) weghalen
plot_stemgedrag_fracties.update_xaxes(visible=False)
plot_stemgedrag_fracties.update_yaxes(visible=False)

st.plotly_chart(plot_stemgedrag_fracties, use_container_width=True)

###
# Boxplot duratie vs besluit uitkomst
###

st.header("Wat zijn de activiteitsduraties bij de verschillende soorten besluituitkomsten?")
st.write("De boxdiagrammen hieronder laten per besluituitkomst zien wat de mediale tijdsduur is (lijn in de doos) en de spreiding van de middelste 50% van alle tijden (de doos). Daarnaast geeft het met de losse punten aan wat extreme (zeer onwaarschijnlijke) tijden zijn per besluituitkomst. Hiermee wordt inzichtelijk gemaakt of bepaalde besluituikomsten vaker voorkomen bij een bepaalde activiteitsduur.")

# Dataframe maken
duratie_besluit_uitkomst = (
    f_dim_besluit[['besluit_id', 'uitkomst']]
    .merge(
        f_fact_activiteit_besluit[['besluit_id', 'duur_minuten']],
        on='besluit_id',
        how='left'))

# Plot
plot_duratie_besluit_uitkomst = px.box(
    duratie_besluit_uitkomst,
    x='uitkomst',
    y='duur_minuten',
    color='uitkomst',
    labels={
        'uitkomst': 'Besluituitkomst',
        'duur_minuten': 'Duur (minuten)'})

# Layout plot
plot_duratie_besluit_uitkomst.update_xaxes(
    ticktext=['Aangenomen', 'Verworpen', 'Aangehouden'],
    tickvals=['aangenomen', 'verworpen', 'aangehouden'])

plot_duratie_besluit_uitkomst.update_layout(
    title=dict(
        text='Besluituitkomst per tijdsduur',
        x=0.5,
        xanchor='center',
        font_size=28),
    xaxis=dict(
        title_font=dict(size=18),
        tickfont=dict(size=14)),
    yaxis=dict(
        title_font=dict(size=18),
        tickfont=dict(size=14)),
    showlegend=False,
    height=600)

st.plotly_chart(plot_duratie_besluit_uitkomst, use_container_width=True)

###
# Tabel met stemgedrag op zaken voorgesteld door fracties
###

st.header("Hoe zijn de besluituitkomsten verdeeld onder de fracties?")
st.write("In de tabel hieronder wordt per fractie gekeken naar de besluituitkomsten op zaken die de fractie heeft aangedragen (zaakactor). Hiermee kan de activiteit en effectiviteit van een fractie gemeten worden.")

st.markdown(
    "<h4 style='text-align: center;'>Stemgedrag op zaken voorgesteld door fracties</h4>", 
    unsafe_allow_html=True)

# Dataframe maken
alle_percentages = pd.DataFrame()

for i, fractie in enumerate(fracties, start=1):
    df = stemgedrag_fracties[stemgedrag_fracties['fractie_norm'] == fractie]

    percentages = df.groupby('uitkomst').size().reset_index(name='aantal')
    percentages['percentage'] = (
        percentages['aantal'] / percentages['aantal'].sum() * 100)
    percentages['fractie'] = fractie

    alle_percentages = pd.concat([alle_percentages, percentages], ignore_index=True)

alle_percentages_pivot = alle_percentages.pivot(
    index = 'fractie',
    columns='uitkomst',
    values = 'percentage').reset_index().fillna(0)

aantallen_per_fractie = (
    alle_percentages.groupby('fractie')['aantal'].sum())

alle_percentages_pivot = alle_percentages_pivot.merge(
    aantallen_per_fractie, on='fractie', how='left')

st.dataframe(
    alle_percentages_pivot,
    width='stretch',
    column_config={
        "fractie": st.column_config.TextColumn(
            "Fractie",
            width="medium"),
        **{
            col: st.column_config.NumberColumn(
                "Totaal aantal zaken" if col == "aantal" else col.capitalize(),
                format="%d" if col == "aantal" else "%.1f%%",
                width='medium' if col =='aantal' else "small")
            for col in alle_percentages_pivot.columns
            if col != "fractie"}},
    hide_index=True)

#---------------------------------------------
# Over de data
#---------------------------------------------

with st.expander("Over de data"):
    st.write("Bij dit dashboard zijn de fracties Groenlinks, de Partij van de Arbeid, Groenlinks-PvdA en Progressief Nederland samengevoegd tot één fractie: PRO. Activiteiten met een negatieve tijdsduratie zijn niet meegenomen.")