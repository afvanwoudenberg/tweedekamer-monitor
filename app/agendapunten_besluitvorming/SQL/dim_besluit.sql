SELECT
	id AS besluit_id,
	stemmings_soort,
	besluit_soort,
	CASE
		WHEN besluit_soort ILIKE '%aangenomen%' THEN 'aangenomen'
		WHEN besluit_soort ILIKE '%verworpen%' THEN 'verworpen'
		WHEN besluit_soort ILIKE '%aangehouden%' THEN 'aangehouden'
	END AS uitkomst
FROM silver.besluit;