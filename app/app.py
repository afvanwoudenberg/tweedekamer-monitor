import streamlit as st

st.set_page_config(page_title="Tweede Kamer Monitor", layout="wide")

pagina_1 = st.Page("pages/3_Bronvermelding_csv.py", title="Bronvermelding", default=True)
pagina_2 = st.Page("pages/2_Soorten_bronnen_en_publicatiesnelheid.py", title="Soorten bronnen en Publicatiesnelheid")

pg = st.navigation([pagina_1, pagina_2])
pg.run()