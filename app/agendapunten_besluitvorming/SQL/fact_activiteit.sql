SELECT
	id AS activiteit_id,
	datum,
	datum_soort,
	DATE_DIFF('minute', aanvangstijd, eindtijd) AS duur_minuten
FROM silver.activiteit;