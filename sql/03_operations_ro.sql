-- ============================================================================
-- Script 03 : Opérations définies en base sur les objets (Étape 1)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou
-- Base cible : centre
-- Prérequis : sql/02_schema_ro.sql exécuté (types t_position, t_qualite_air,
--             t_hydrometrie + tables station et seuil_alerte)
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Distance en kilomètres entre deux positions (formule de Haversine, R=6371 km)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION distance_km(pos1 t_position, pos2 t_position)
RETURNS NUMERIC AS $$
    SELECT round(6371 * acos(
             least(1, greatest(-1,
               sin(radians((pos1).latitude))  * sin(radians((pos2).latitude))
             + cos(radians((pos1).latitude))  * cos(radians((pos2).latitude))
             * cos(radians((pos2).longitude - (pos1).longitude))))
           )::numeric, 3)
$$ LANGUAGE sql IMMUTABLE;

-- Surcharge pratique : distance entre deux stations à partir de leurs codes
CREATE OR REPLACE FUNCTION distance_stations_km(p_station1 VARCHAR, p_station2 VARCHAR)
RETURNS NUMERIC AS $$
    SELECT distance_km(s1.position, s2.position)
    FROM station s1, station s2
    WHERE s1.code_station = p_station1 AND s2.code_station = p_station2
$$ LANGUAGE sql STABLE;

-- ----------------------------------------------------------------------------
-- 2. Tests de dépassement des seuils d'alerte du référentiel (seuil_alerte)
--    Chaque fonction s'applique directement à l'objet/valeur mesurée.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION depasse_seuil_temperature(p_temp NUMERIC) RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM seuil_alerte
                   WHERE type_capteur = 'temperature' AND grandeur = 'valeur'
                     AND ((borne = 'max' AND p_temp > valeur)
                       OR (borne = 'min' AND p_temp < valeur)))
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION depasse_seuil_air(p_air t_qualite_air) RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM seuil_alerte s
                   WHERE s.type_capteur = 'air'
                     AND ((s.grandeur = 'pm25' AND s.borne = 'max' AND (p_air).pm25 > s.valeur)
                       OR (s.grandeur = 'pm10' AND s.borne = 'max' AND (p_air).pm10 > s.valeur)
                       OR (s.grandeur = 'no2'  AND s.borne = 'max' AND (p_air).no2  > s.valeur)))
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION depasse_seuil_hydro(p_hydro t_hydrometrie) RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM seuil_alerte s
                   WHERE s.type_capteur = 'hydro'
                     AND ((s.grandeur = 'pluie'    AND s.borne = 'max' AND (p_hydro).pluie    > s.valeur)
                       OR (s.grandeur = 'humidite' AND s.borne = 'min' AND (p_hydro).humidite < s.valeur)
                       OR (s.grandeur = 'humidite' AND s.borne = 'max' AND (p_hydro).humidite > s.valeur)))
$$ LANGUAGE sql STABLE;

-- Fonction détaillée : liste des seuils franchis (grandeur, borne, seuil, unite)
CREATE OR REPLACE FUNCTION seuils_franchis(p_type VARCHAR, p_grandeur VARCHAR, p_valeur NUMERIC)
RETURNS TABLE(grandeur VARCHAR, borne VARCHAR, seuil NUMERIC, unite VARCHAR) AS $$
    SELECT s.grandeur, s.borne::text, s.valeur, s.unite
    FROM seuil_alerte s
    WHERE s.type_capteur::text = p_type AND s.grandeur = p_grandeur
      AND ((s.borne = 'max' AND p_valeur > s.valeur)
        OR (s.borne = 'min' AND p_valeur < s.valeur))
$$ LANGUAGE sql STABLE;

-- ----------------------------------------------------------------------------
-- 3. Conversions d'unités adaptées à la Variante A (hydrométrie)
-- ----------------------------------------------------------------------------
-- °C -> °F
CREATE OR REPLACE FUNCTION celsius_vers_fahrenheit(p_temp_c NUMERIC) RETURNS NUMERIC AS $$
    SELECT round((p_temp_c * 9 / 5 + 32)::numeric, 2)
$$ LANGUAGE sql IMMUTABLE;

-- mm -> pouces (1 pouce = 25,4 mm) : pluie tombée exprimée en pouces
CREATE OR REPLACE FUNCTION pluie_mm_vers_pouces(p_hydro t_hydrometrie) RETURNS NUMERIC AS $$
    SELECT round(((p_hydro).pluie / 25.4)::numeric, 3)
$$ LANGUAGE sql IMMUTABLE;

-- Point de rosée (°C) par la formule de Magnus, à partir de la température
-- de l'air et de l'humidité relative de l'objet hydrométrie
CREATE OR REPLACE FUNCTION point_de_rosee(p_temp_c NUMERIC, p_hydro t_hydrometrie) RETURNS NUMERIC AS $$
    SELECT round((237.7 * (17.27 * p_temp_c / (237.7 + p_temp_c) + ln((p_hydro).humidite / 100)))
                 / (17.27 - (17.27 * p_temp_c / (237.7 + p_temp_c) + ln((p_hydro).humidite / 100)))::numeric, 2)
$$ LANGUAGE sql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- 4. Démonstrations (à commenter dans le rapport)
-- ----------------------------------------------------------------------------
-- Distance Béjaïa Aéroport (zone 1) <-> Sétif Université (zone 2)
SELECT distance_stations_km('BJ-01', 'SE-01') AS distance_BJ01_SE01_km;

-- Test de dépassement de seuil
SELECT depasse_seuil_temperature(41.2)  AS temp_41_2_depasse,
       depasse_seuil_air(ROW(30.5, 60.0, 80.0)::t_qualite_air) AS air_depasse,
       depasse_seuil_hydro(ROW(55, 12.0)::t_hydrometrie)     AS hydro_depasse;

-- Détail des seuils franchis
SELECT * FROM seuils_franchis('air', 'pm25', 30.5);

-- Conversions variante A
SELECT celsius_vers_fahrenheit(35)                        AS fahrenheit_35C,
       pluie_mm_vers_pouces(ROW(55, 25.4)::t_hydrometrie) AS pluie_25_4mm_en_pouces,
       point_de_rosee(20, ROW(60, 0)::t_hydrometrie)      AS point_rosee_20C_60pct;
