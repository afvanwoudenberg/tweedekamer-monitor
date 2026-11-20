SELECT
	id AS fractie_id,
	afkorting,
	naam_nl,
	CASE
		WHEN afkorting IN ('PvdA', 'GL', 'GroenLinks-PvdA', 'PRO') THEN 'PRO'
		ELSE afkorting
	END AS fractie_norm,
	datum_actief,
	datum_inactief
FROM silver.fractie;