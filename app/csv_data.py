from pathlib import Path

import pandas as pd
import streamlit as st

DATA_MAP = Path(__file__).resolve().parent.parent / "data"


@st.cache_data
def laad(naam):
    df = pd.read_csv(DATA_MAP / f"{naam}.csv")
    for kolom in ["datum", "publicatiedatum"]:
        if kolom in df.columns:
            df[kolom] = pd.to_datetime(df[kolom])
    return df