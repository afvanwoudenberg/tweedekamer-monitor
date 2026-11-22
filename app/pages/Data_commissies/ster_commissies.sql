-- Tabel fact_commissie_zitting
SELECT
    zp.id                                                   AS zitting_id,
    z.commissie_id                                          AS commissie_id,
    zp.persoon_id                                           AS persoon_id,
    CAST(strftime(zp.van, '%Y%m%d') AS INTEGER)             AS datum_id_van,
    CAST(strftime(zp.tot_en_met, '%Y%m%d') AS INTEGER)      AS datum_id_tot,
    zp.commissie_zetel_id                                   AS zetel_id,
    zp.functie                                              AS functie,
    date_diff('day', zp.van, COALESCE(zp.tot_en_met, current_date)) AS dagen_zitting,
    (zp.van <= current_date
     AND (zp.tot_en_met IS NULL OR zp.tot_en_met >= current_date))  AS is_huidig
FROM silver.commissie_zetel_vast_persoon zp
JOIN silver.commissie_zetel z ON z.id = zp.commissie_zetel_id
WHERE zp.persoon_id IS NOT NULL;


-- Tabel fact_commissie_vacature
SELECT
    v.id                                                    AS vacature_id,
    z.commissie_id                                          AS commissie_id,
    v.fractie_id                                            AS fractie_id,
    CAST(strftime(v.van, '%Y%m%d') AS INTEGER)              AS datum_id_van,
    CAST(strftime(v.tot_en_met, '%Y%m%d') AS INTEGER)       AS datum_id_tot,
    v.commissie_zetel_id                                    AS zetel_id,
    date_diff('day', v.van, COALESCE(v.tot_en_met, current_date)) AS dagen_open,
    (v.van <= current_date
     AND (v.tot_en_met IS NULL OR v.tot_en_met >= current_date))   AS is_open
FROM silver.commissie_zetel_vast_vacature v
JOIN silver.commissie_zetel z ON z.id = v.commissie_zetel_id;


-- Tabel fact_commissie_activiteit
SELECT
    a.id                                                    AS activiteit_id,
    a.voortouwcommissie_id                                  AS commissie_id,
    CAST(strftime(a.datum, '%Y%m%d') AS INTEGER)            AS datum_id,
    a.soort                                                 AS soort,
    a.status                                                AS status,
    (a.status = 'Uitgevoerd')                               AS is_uitgevoerd
FROM silver.activiteit a
WHERE a.voortouwcommissie_id IS NOT NULL
  AND a.datum >= DATE '2024-01-01';


-- Tabel fact_commissie_zaak
SELECT
    a.voortouwcommissie_id                                  AS commissie_id,
    bz.zaak_id                                              AS zaak_id,
    CAST(strftime(MIN(a.datum), '%Y%m%d') AS INTEGER)       AS datum_id,
    COUNT(DISTINCT b.id)                                    AS aantal_besluiten
FROM silver.activiteit a
JOIN silver.agendapunt ap   ON ap.activiteit_id = a.id
JOIN silver.besluit b       ON b.agendapunt_id = ap.id
JOIN silver.besluit_zaak bz ON bz.besluit_id = b.id
WHERE a.voortouwcommissie_id IS NOT NULL
  AND a.datum >= DATE '2024-01-01'
GROUP BY a.voortouwcommissie_id, bz.zaak_id;


-- Tabel dim_commissie
SELECT
    c.id                                                    AS commissie_id,
    c.naam_nl                                               AS naam_nl,
    c.afkorting                                             AS afkorting,
    c.soort                                                 AS soort,
    CASE
        WHEN lower(c.naam_nl) LIKE '%interparlementair%'    THEN 'Interparlementair'
        WHEN lower(c.naam_nl) LIKE 'tijdelijke%'
          OR lower(c.naam_nl) LIKE '%enquête%'              THEN 'Tijdelijk'
        WHEN lower(c.naam_nl) LIKE 'vaste commissie%'       THEN 'Vast'
        ELSE 'Overig'
    END                                                     AS commissietype,
    c.datum_actief                                          AS datum_actief,
    c.datum_inactief                                        AS datum_inactief,
    (c.datum_inactief IS NULL OR c.datum_inactief > current_date) AS is_actief,
    (SELECT COUNT(DISTINCT zp.commissie_zetel_id)
       FROM silver.commissie_zetel_vast_persoon zp
       JOIN silver.commissie_zetel z ON z.id = zp.commissie_zetel_id
      WHERE z.commissie_id = c.id
        AND zp.van <= current_date
        AND (zp.tot_en_met IS NULL OR zp.tot_en_met >= current_date)) AS aantal_zetels
FROM silver.commissie c;


-- Tabel dim_persoon
SELECT
    p.id                                                    AS persoon_id,
    p.achternaam                                            AS achternaam,
    p.geslacht                                              AS geslacht,
    p.geboortedatum                                         AS geboortedatum,
    date_diff('year', p.geboortedatum, current_date)        AS leeftijd
FROM silver.persoon p
WHERE p.id IN (SELECT persoon_id FROM silver.commissie_zetel_vast_persoon
               WHERE persoon_id IS NOT NULL);


-- Tabel dim_fractie
SELECT
    f.id                                                    AS fractie_id,
    f.afkorting                                             AS afkorting,
    f.naam_nl                                               AS naam_nl
FROM silver.fractie f;


-- Tabel dim_zaak
SELECT
    z.id                                                    AS zaak_id,
    z.soort                                                 AS soort,
    substr(z.onderwerp, 1, 100)                             AS onderwerp,
    z.status                                                AS status,
    z.afgedaan                                              AS afgedaan
FROM silver.zaak z
WHERE z.id IN (
    SELECT bz.zaak_id
    FROM silver.activiteit a
    JOIN silver.agendapunt ap   ON ap.activiteit_id = a.id
    JOIN silver.besluit b       ON b.agendapunt_id = ap.id
    JOIN silver.besluit_zaak bz ON bz.besluit_id = b.id
    WHERE a.voortouwcommissie_id IS NOT NULL
      AND a.datum >= DATE '2024-01-01'
);


-- Tabel dim_datum
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER)                  AS datum_id,
    CAST(d AS DATE)                                         AS datum,
    year(d)                                                 AS jaar,
    quarter(d)                                              AS kwartaal,
    month(d)                                                AS maand
FROM generate_series(DATE '2020-01-01', DATE '2030-12-31', INTERVAL 1 DAY) t(d);
