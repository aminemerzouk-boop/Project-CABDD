-- ============================================================================
-- Script 06 : Rapport XML « Bilan Journalier » (Variante A) — Étape 2
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou
-- Base cible : centre
-- Prérequis : 02_schema_ro.sql, 04_referentiel_csv.sql, 05_chargement_xml.sql
--
-- Spécification Variante A : pour chaque jour de [p_date_debut, p_date_fin],
-- chaque station et chaque grandeur : min, max, moyenne et nb de mesures
-- valides. Les capteurs retirés/mis en service en cours de période sont pris
-- en compte via leurs dates du référentiel.
-- ============================================================================

\connect centre

-- Vue aplatie : une ligne par (mesure, grandeur), en respectant la fenêtre de
-- service du capteur (date_mise_en_service / date_retrait du référentiel)
CREATE OR REPLACE VIEW v_mesure_plat AS
SELECT mt.instant_mesure::date AS jour, c.code_station, 'temperature' AS grandeur,
       '°C' AS unite, mt.temperature AS valeur
FROM mesure_temperature mt JOIN capteur c ON c.code_capteur = mt.code_capteur
WHERE mt.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mt.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'pm25', 'µg/m3', (ma.valeurs_air).pm25
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'pm10', 'µg/m3', (ma.valeurs_air).pm10
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'no2', 'µg/m3', (ma.valeurs_air).no2
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT mh.instant_mesure::date, c.code_station, 'humidite', '%', (mh.valeurs_hydro).humidite
FROM mesure_hydro mh JOIN capteur c ON c.code_capteur = mh.code_capteur
WHERE mh.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mh.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT mh.instant_mesure::date, c.code_station, 'pluie', 'mm', (mh.valeurs_hydro).pluie
FROM mesure_hydro mh JOIN capteur c ON c.code_capteur = mh.code_capteur
WHERE mh.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mh.instant_mesure::date <= c.date_retrait);

-- ----------------------------------------------------------------------------
-- Fonction du rapport XML paramétré par la période
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION generer_bilan_journalier_xml(p_date_debut DATE, p_date_fin DATE)
RETURNS XML LANGUAGE sql AS $$
WITH jours AS (
    SELECT generate_series(p_date_debut, p_date_fin, interval '1 day')::date AS jour
),
stats AS (
    SELECT v.jour, v.code_station, v.grandeur, v.unite,
           min(v.valeur) AS min, max(v.valeur) AS max,
           avg(v.valeur) AS moyenne, count(*) AS nb
    FROM v_mesure_plat v
    WHERE v.jour BETWEEN p_date_debut AND p_date_fin
    GROUP BY v.jour, v.code_station, v.grandeur, v.unite
)
SELECT xmlelement(
         NAME bilanJournalier,
         xmlattributes(p_date_debut::text AS debut, p_date_fin::text AS fin),
         (SELECT xmlagg(
                   xmlelement(NAME jour, xmlattributes(j.jour::text AS date),
                     (SELECT xmlagg(
                               xmlelement(NAME station,
                                 xmlattributes(s.code_station AS code, s.nom AS nom,
                                               s.wilaya AS wilaya, s.zone::text AS zone),
                                 (SELECT xmlagg(
                                           xmlelement(NAME grandeur,
                                             xmlattributes(g.grandeur AS nom, g.unite AS unite,
                                                           g.nb::text AS nbMesures),
                                             xmlelement(NAME min,     round(g.min,2)::text),
                                             xmlelement(NAME max,     round(g.max,2)::text),
                                             xmlelement(NAME moyenne, round(g.moyenne,2)::text))
                                           ORDER BY g.grandeur)
                                  FROM stats g
                                  WHERE g.jour = j.jour AND g.code_station = s.code_station)))
                      FROM station s
                      WHERE EXISTS (SELECT 1 FROM stats g
                                    WHERE g.jour = j.jour AND g.code_station = s.code_station)))
                  ORDER BY j.jour)
          FROM jours j))
$$;

-- ----------------------------------------------------------------------------
-- Test : première semaine de février 2026
-- ----------------------------------------------------------------------------
SELECT generer_bilan_journalier_xml(DATE '2026-02-01', DATE '2026-02-07');
