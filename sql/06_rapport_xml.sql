-- ============================================================================
-- Script 06 : Génération du Rapport XML « Bilan Journalier » (Étape 2)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou
-- Base cible : centre
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- Vue aplatie des grandeurs valides comprises dans la fenêtre de service du
-- capteur (date_mise_en_service <= jour < date_retrait du référentiel).
-- Exemples concrets dans capteurs_A.csv :
--   * BJ-02-A1 : mise_en_service = 2026-02-02
--   * JJ-02-T1 : date_retrait    = 2026-03-17 (hors_service à partir du 17/03)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_mesure_plat AS
SELECT mt.id_mesure, mt.code_capteur, mt.instant_mesure,
       mt.instant_mesure::date AS jour, c.code_station,
       'temperature'::varchar AS grandeur, '°C'::varchar AS unite,
       mt.temperature AS valeur
FROM mesure_temperature mt
JOIN capteur c ON c.code_capteur = mt.code_capteur
WHERE mt.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mt.instant_mesure::date < c.date_retrait)
UNION ALL
SELECT ma.id_mesure, ma.code_capteur, ma.instant_mesure,
       ma.instant_mesure::date, c.code_station,
       'pm25'::varchar, 'µg/m3'::varchar, (ma.valeurs_air).pm25
FROM mesure_air ma
JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date < c.date_retrait)
UNION ALL
SELECT ma.id_mesure, ma.code_capteur, ma.instant_mesure,
       ma.instant_mesure::date, c.code_station,
       'pm10'::varchar, 'µg/m3'::varchar, (ma.valeurs_air).pm10
FROM mesure_air ma
JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date < c.date_retrait)
UNION ALL
SELECT ma.id_mesure, ma.code_capteur, ma.instant_mesure,
       ma.instant_mesure::date, c.code_station,
       'no2'::varchar, 'µg/m3'::varchar, (ma.valeurs_air).no2
FROM mesure_air ma
JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date < c.date_retrait)
UNION ALL
SELECT mh.id_mesure, mh.code_capteur, mh.instant_mesure,
       mh.instant_mesure::date, c.code_station,
       'humidite'::varchar, '%'::varchar, (mh.valeurs_hydro).humidite
FROM mesure_hydro mh
JOIN capteur c ON c.code_capteur = mh.code_capteur
WHERE mh.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mh.instant_mesure::date < c.date_retrait)
UNION ALL
SELECT mh.id_mesure, mh.code_capteur, mh.instant_mesure,
       mh.instant_mesure::date, c.code_station,
       'pluie'::varchar, 'mm'::varchar, (mh.valeurs_hydro).pluie
FROM mesure_hydro mh
JOIN capteur c ON c.code_capteur = mh.code_capteur
WHERE mh.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mh.instant_mesure::date < c.date_retrait);

-- ----------------------------------------------------------------------------
-- Fonction de génération du rapport XML « Bilan journalier » (Variante A)
-- Paramètres : p_date_debut, p_date_fin
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION generer_bilan_journalier_xml(p_date_debut DATE, p_date_fin DATE)
RETURNS XML LANGUAGE sql STABLE AS $$
WITH jours AS (
    SELECT generate_series(p_date_debut, p_date_fin, interval '1 day')::date AS jour
),
stats AS (
    SELECT v.jour, v.code_station, v.grandeur, v.unite,
           min(v.valeur) AS min_val,
           max(v.valeur) AS max_val,
           avg(v.valeur) AS moy_val,
           count(*)      AS nb
    FROM v_mesure_plat v
    WHERE v.jour BETWEEN p_date_debut AND p_date_fin
    GROUP BY v.jour, v.code_station, v.grandeur, v.unite
)
SELECT xmlelement(
         NAME "bilanJournalier",
         xmlattributes(p_date_debut::text AS debut, p_date_fin::text AS fin),
         (SELECT xmlagg(
                   xmlelement(
                     NAME jour,
                     xmlattributes(j.jour::text AS date),
                     (SELECT xmlagg(
                               xmlelement(
                                 NAME station,
                                 xmlattributes(
                                   s.code_station AS code,
                                   s.nom          AS nom,
                                   s.wilaya       AS wilaya,
                                   s.zone::text   AS zone
                                 ),
                                 (SELECT xmlagg(
                                           xmlelement(
                                             NAME grandeur,
                                             xmlattributes(
                                               g.grandeur AS nom,
                                               g.unite    AS unite,
                                               g.nb::text AS "nbMesures"
                                             ),
                                             xmlelement(NAME min,     round(g.min_val, 2)::text),
                                             xmlelement(NAME max,     round(g.max_val, 2)::text),
                                             xmlelement(NAME moyenne, round(g.moy_val, 2)::text)
                                           )
                                           ORDER BY g.grandeur
                                         )
                                  FROM stats g
                                  WHERE g.jour = j.jour
                                    AND g.code_station = s.code_station)
                               )
                               ORDER BY s.code_station
                             )
                      FROM station s
                      WHERE EXISTS (
                          SELECT 1 FROM stats g
                          WHERE g.jour = j.jour AND g.code_station = s.code_station
                      ))
                   )
                   ORDER BY j.jour
                 )
          FROM jours j
          WHERE EXISTS (SELECT 1 FROM stats g WHERE g.jour = j.jour))
       )
$$;

-- ----------------------------------------------------------------------------
-- Test : génération du bilan sur la 1re semaine de février 2026
-- ----------------------------------------------------------------------------
SELECT generer_bilan_journalier_xml(DATE '2026-02-01', DATE '2026-02-07');
