-- ============================================================================
-- Script 03 : Opérations définies en base sur les objets (Étape 1)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou
-- Base cible : centre
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Distance en kilomètres entre deux stations (sur le type t_position)
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Fonction distance_km(pos1 t_position, pos2 t_position) RETURNS NUMERIC
--     utilisant la formule sphérique de Haversine (rayon terrestre R = 6371 km).
--   - Surcharge pratique distance_stations_km(p_station1 VARCHAR, p_station2 VARCHAR).

-- ----------------------------------------------------------------------------
-- 2. Test de dépassement d'un seuil d'alerte du référentiel
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Fonctions s'appliquant directement aux valeurs et objets composés :
--       * depasse_seuil_temperature(p_temp NUMERIC) RETURNS BOOLEAN
--       * depasse_seuil_air(p_air t_qualite_air) RETURNS BOOLEAN
--       * depasse_seuil_hydro(p_hydro t_hydrometrie) RETURNS BOOLEAN
--   - Fonction détaillée retournant les seuils franchis (grandeur, borne, seuil, valeur).

-- ----------------------------------------------------------------------------
-- 3. Conversions d'unités adaptées à la Variante A
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Conversion température : celsius_vers_fahrenheit(p_temp_c NUMERIC) RETURNS NUMERIC
--   - Conversion hydrométrie (Variante A) :
--       * pluie_mm_vers_pouces(p_hydro t_hydrometrie) RETURNS NUMERIC
--       * point_de_rosee(p_temp_c NUMERIC, p_hydro t_hydrometrie) RETURNS NUMERIC
