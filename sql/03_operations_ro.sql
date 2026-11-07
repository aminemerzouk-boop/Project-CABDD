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
-- 1. Distance en kilomètres entre deux positions (formule de Haversine, R = 6371 km)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION distance_km(pos1 t_position, pos2 t_position)
RETURNS NUMERIC AS $$
    SELECT round(
        (6371.0 * acos(
            least(1.0::double precision, greatest(-1.0::double precision,
                sin(radians((pos1).latitude::double precision))  * sin(radians((pos2).latitude::double precision))
              + cos(radians((pos1).latitude::double precision))  * cos(radians((pos2).latitude::double precision))
              * cos(radians(((pos2).longitude - (pos1).longitude)::double precision))
            ))
        ))::numeric, 3
    )
$$ LANGUAGE sql IMMUTABLE;

-- Surcharge pratique : distance entre deux stations à partir de leurs codes
CREATE OR REPLACE FUNCTION distance_stations_km(p_station1 VARCHAR, p_station2 VARCHAR)
RETURNS NUMERIC AS $$
    SELECT distance_km(s1.position, s2.position)
    FROM station s1, station s2
    WHERE s1.code_station = p_station1
      AND s2.code_station = p_station2
$$ LANGUAGE sql STABLE;

-- ----------------------------------------------------------------------------
-- 2. Tests de dépassement des seuils d'alerte du référentiel (seuil_alerte)
--    Note sur seuils_A.csv : pour la température, la colonne grandeur vaut 'valeur'.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION depasse_seuil_temperature(p_temp NUMERIC)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM seuil_alerte s
        WHERE s.type_capteur = 'temperature'::type_capteur_enum
          AND s.grandeur IN ('valeur', 'temperature')
          AND ((s.borne = 'max'::borne_seuil_enum AND p_temp > s.valeur)
            OR (s.borne = 'min'::borne_seuil_enum AND p_temp < s.valeur))
    )
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION depasse_seuil_air(p_air t_qualite_air)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM seuil_alerte s
        WHERE s.type_capteur = 'air'::type_capteur_enum
          AND (
               (s.grandeur = 'pm25' AND ((s.borne = 'max'::borne_seuil_enum AND (p_air).pm25 > s.valeur)
                                      OR (s.borne = 'min'::borne_seuil_enum AND (p_air).pm25 < s.valeur)))
            OR (s.grandeur = 'pm10' AND ((s.borne = 'max'::borne_seuil_enum AND (p_air).pm10 > s.valeur)
                                      OR (s.borne = 'min'::borne_seuil_enum AND (p_air).pm10 < s.valeur)))
            OR (s.grandeur = 'no2'  AND ((s.borne = 'max'::borne_seuil_enum AND (p_air).no2  > s.valeur)
                                      OR (s.borne = 'min'::borne_seuil_enum AND (p_air).no2  < s.valeur)))
          )
    )
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION depasse_seuil_hydro(p_hydro t_hydrometrie)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM seuil_alerte s
        WHERE s.type_capteur = 'hydro'::type_capteur_enum
          AND (
               (s.grandeur = 'pluie'    AND ((s.borne = 'max'::borne_seuil_enum AND (p_hydro).pluie    > s.valeur)
                                          OR (s.borne = 'min'::borne_seuil_enum AND (p_hydro).pluie    < s.valeur)))
            OR (s.grandeur = 'humidite' AND ((s.borne = 'max'::borne_seuil_enum AND (p_hydro).humidite > s.valeur)
                                          OR (s.borne = 'min'::borne_seuil_enum AND (p_hydro).humidite < s.valeur)))
          )
    )
$$ LANGUAGE sql STABLE;

-- Fonction détaillée : liste des seuils franchis (grandeur, borne, seuil, unite)
CREATE OR REPLACE FUNCTION seuils_franchis(p_type VARCHAR, p_grandeur VARCHAR, p_valeur NUMERIC)
RETURNS TABLE(grandeur VARCHAR, borne VARCHAR, seuil NUMERIC, unite VARCHAR) AS $$
    SELECT s.grandeur::varchar,
           s.borne::text::varchar,
           s.valeur,
           s.unite::varchar
    FROM seuil_alerte s
    WHERE s.type_capteur::text = p_type
      AND (s.grandeur = p_grandeur
           OR (p_type = 'temperature' AND p_grandeur = 'temperature' AND s.grandeur = 'valeur'))
      AND ((s.borne = 'max'::borne_seuil_enum AND p_valeur > s.valeur)
        OR (s.borne = 'min'::borne_seuil_enum AND p_valeur < s.valeur))
$$ LANGUAGE sql STABLE;

-- ----------------------------------------------------------------------------
-- 3. Conversions d'unités adaptées à la Variante A (hydrométrie & température)
-- ----------------------------------------------------------------------------
-- °C -> °F
CREATE OR REPLACE FUNCTION celsius_vers_fahrenheit(p_temp_c NUMERIC)
RETURNS NUMERIC AS $$
    SELECT round((p_temp_c * 9.0 / 5.0 + 32.0)::numeric, 2)
$$ LANGUAGE sql IMMUTABLE;

-- mm -> pouces (1 pouce = 25,4 mm) : pluie tombée exprimée en pouces
CREATE OR REPLACE FUNCTION pluie_mm_vers_pouces(p_hydro t_hydrometrie)
RETURNS NUMERIC AS $$
    SELECT round(((p_hydro).pluie / 25.4)::numeric, 3)
$$ LANGUAGE sql IMMUTABLE;

-- Point de rosée (°C) par la formule de Magnus-Tetens, à partir de la température
-- de l'air et de l'humidité relative de l'objet hydrométrie (protégé si humidite <= 0)
CREATE OR REPLACE FUNCTION point_de_rosee(p_temp_c NUMERIC, p_hydro t_hydrometrie)
RETURNS NUMERIC AS $$
    SELECT CASE
        WHEN p_temp_c IS NULL OR (p_hydro).humidite IS NULL OR (p_hydro).humidite <= 0 THEN NULL
        ELSE round(
            (237.7 * (17.27 * p_temp_c::double precision / (237.7 + p_temp_c::double precision)
                      + ln((p_hydro).humidite::double precision / 100.0))
             / (17.27 - (17.27 * p_temp_c::double precision / (237.7 + p_temp_c::double precision)
                         + ln((p_hydro).humidite::double precision / 100.0)))
            )::numeric, 2
        )
    END
$$ LANGUAGE sql IMMUTABLE;

-- Vérification immédiate des fonctions pures (les tests sur le référentiel
-- sont exécutés dans sql/04_referentiel_csv.sql juste après le chargement CSV)
SELECT celsius_vers_fahrenheit(35)                        AS fahrenheit_35C,
       pluie_mm_vers_pouces(ROW(55, 25.4)::t_hydrometrie) AS pluie_25_4mm_en_pouces,
       point_de_rosee(20, ROW(60, 0)::t_hydrometrie)      AS point_rosee_20C_60pct;
