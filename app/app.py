from pathlib import Path

import streamlit as st

st.set_page_config(
    page_title="Tweede Kamer Monitor",
    page_icon=":material/account_balance:",
    layout="wide",
)

def home_page():
    st.title("Parlement in beeld")
    st.write("Een actueel overzicht van kabinet, fracties en reizen.")

    metric_columns = st.columns(4)
    metrics = [
        ("Kamerleden", "150", "+2 sinds start zittingsjaar"),
        ("Fracties", "15", "Vertegenwoordigd in de Kamer"),
        ("Kabinet", "29", "Ministers en staatssecretarissen"),
        ("Geregistreerde reizen", "86", "In het huidige kalenderjaar"),
    ]
    for column, (label, value, detail) in zip(metric_columns, metrics):
        column.metric(label, value, detail)

    st.divider()
    chart_column, activity_column = st.columns([1.3, 1])
    with chart_column:
        st.subheader("Parlementaire activiteit")
        st.caption("Voorbeeld van geregistreerde activiteiten per maand")
        st.bar_chart(
            {
                "Maand": ["Apr", "Mei", "Jun", "Jul", "Aug", "Sep"],
                "Debatten": [32, 28, 41, 37, 45, 39],
                "Stemmingen": [18, 24, 20, 31, 27, 34],
            },
            x="Maand",
            y=["Debatten", "Stemmingen"],
            x_label="Maand",
            y_label="Aantal",
            color=["#18836b", "#d5943c"],
        )
    with activity_column:
        st.subheader("In één oogopslag")
        st.caption("Voorbeeldgegevens · laatst bijgewerkt vandaag")
        st.dataframe(
            [
                {"Onderwerp": "Plenair debat", "Commissie": "Justitie en Veiligheid", "Status": "Gepland"},
                {"Onderwerp": "Begrotingsbehandeling", "Commissie": "Financiën", "Status": "In behandeling"},
                {"Onderwerp": "Vragenuur", "Commissie": "Plenair", "Status": "Afgerond"},
            ],
            hide_index=True,
            width="stretch",
        )

st.logo(
    str(Path(__file__).with_name("logo.svg")),
    size="large",
    icon_image=":material/account_balance:",
)

pages = st.navigation(
    {
        "Monitor": [
            st.Page(home_page, title="Overzicht", icon=":material/space_dashboard:", default=True)
        ],
        "Thema's": [
            st.Page("pages/kabinet.py", title="Kabinet", icon=":material/account_balance:"),
            st.Page("pages/fracties.py", title="Fracties", icon=":material/groups:"),
            st.Page("pages/reizen.py", title="Reizen", icon=":material/flight:"),
            st.Page(
                "pages/zetelverloop.py",
                title="Zetelverloop",
                icon=":material/swap_horiz:",
            ),
            st.Page(
                "pages/reis_geschenk.py",
                title="Reizen en geschenken",
                icon=":material/card_giftcard:",
            ),
            st.Page("pages/documentstroom.py", title="Documentstroom", icon=":material/description:"),
            st.Page("pages/herkomst_kamerleden.py", title="Herkomst en woonplaats", icon=":material/map:"),
            st.Page(
                "pages/tegen_de_stroom.py",
                title="Afwijkend stemgedrag",
                icon=":material/how_to_vote:",
            ),
            st.Page(
                "pages/nevenfunctie.py",
                title="Nevenfuncties en inkomsten",
                icon=":material/work_history:",
            ),
            st.Page(
                "pages/3_Bronvermelding_csv.py",
                title="Bronvermelding",
                icon=":material/link:",
            ),
            st.Page(
                "pages/2_Soorten_bronnen_en_publicatiesnelheid.py",
                title="Soorten bronnen en publicatiesnelheid",
                icon=":material/speed:",
            ),
            st.Page(
                "pages/besluiten.py",
                title="Besluiten via stemming",
                icon=":material/done_outline:",
            ),
        ],
    }
)
pages.run()
