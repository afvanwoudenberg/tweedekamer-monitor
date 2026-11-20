SELECT
	id AS zaak_actor_id,
	zaak_id,
	fractie_id,
	actor_naam,
	actor_fractie,
	relatie
FROM silver.zaak_actor
LIMIT 800000;