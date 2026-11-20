SELECT
	a.id AS activiteit_id,
	z.id AS zaak_id,
	b.id AS besluit_id,
	DATE_DIFF('minute', a.aanvangstijd, a.eindtijd) AS duur_minuten
FROM 
	silver.activiteit a
	LEFT JOIN silver.agendapunt ap ON ap.activiteit_id = a.id
	LEFT JOIN silver.besluit b ON b.agendapunt_id = ap.id
	LEFT JOIN silver.besluit_zaak bz ON bz.besluit_id = b.id
	LEFT JOIN silver.zaak z ON bz.zaak_id = z.id;