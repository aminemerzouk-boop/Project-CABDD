-- ============================================================================
-- Script 02 : Schéma Relationnel-Objet du Centre National (Étape 1)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Merzouk Amine
-- Base cible : centre
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Énumérations métier
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) : Créer les types ENUM :
--   - type_capteur_enum ('temperature', 'air', 'hydro')
--   - borne_seuil_enum  ('min', 'max') -- à ajuster selon l'en-tête exact de seuils_A.csv
--   - motif_rejet_enum  ('valeur_impossible', 'valeur_manquante', 'format_invalide',
--                        'capteur_inconnu', 'doublon')

-- ----------------------------------------------------------------------------
-- 2. Types composés (Objets manipulables d'un seul bloc)
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   a) t_position    (latitude NUMERIC(9,6), longitude NUMERIC(9,6), altitude NUMERIC(7,2))
--   b) t_qualite_air (pm25 NUMERIC(7,2), pm10 NUMERIC(7,2), no2 NUMERIC(7,2))
--   c) t_hydrometrie (humidite NUMERIC(5,2), pluie NUMERIC(7,2)) -- Spécifique Variante A

-- ----------------------------------------------------------------------------
-- 3. Référentiel : Stations, Hiérarchie de Capteurs (INHERITS) et Seuils
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Table station (code_station PK, nom, wilaya, zone IN (1,2), position t_position)
--     avec CHECK sur latitude [-90,90], longitude [-180,180] et altitude physique.
--   - Table mère capteur (code_capteur PK, code_station FK, type_capteur,
--     date_mise_en_service, date_retrait, etat).
--   - Tables filles :
--       * capteur_temperature INHERITS (capteur)
--       * capteur_air         INHERITS (capteur)
--       * capteur_hydro       INHERITS (capteur)
--   - Table seuil_alerte (id_seuil PK, type_capteur, grandeur, borne, valeur, unite).

-- ----------------------------------------------------------------------------
-- 4. Tables de Mesures, Lots Bruts XML et Espace d'Isolement
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Table lot_brut (id_lot, code_station, date_envoi, contenu_xml XML)
--   - Table mesure_isolee (id_rejet, id_lot, code_station_lot, mesure_xml XML,
--     motif motif_rejet_enum, detail_motif TEXT, date_rejet TIMESTAMP)
--   - Tables de mesures typées (mesure_temperature, mesure_air, mesure_hydro)
--     avec contraintes CHECK interdisant toute valeur physiquement impossible :
--       * Température : plage terrestre réaliste (ex. [-60, 65] °C)
--       * Air         : pm25 >= 0, pm10 >= 0, no2 >= 0 (et pm10 >= pm25 si pertinent)
--       * Hydrométrie : humidite BETWEEN 0 AND 100, pluie >= 0

-- ----------------------------------------------------------------------------
-- 5. Triggers d'intégrité sur la hiérarchie INHERITS
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Trigger garantissant l'unicité globale de code_capteur à travers capteur*
--   - Trigger vérifiant qu'une mesure insérée cible bien un capteur existant
--     du bon type dans la hiérarchie (capteur_temperature / capteur_air / capteur_hydro)
