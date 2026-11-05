-- ============================================================================
-- Script 04 : Chargement du Référentiel CSV vers le Modèle RO (Étape 1)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou
-- Base cible : centre
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Tables temporaires (staging plat) pour lecture des 3 CSV UTF-8
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Créer des tables TEMP reflétant les colonnes plates de :
--       * data/stations_A.csv
--       * data/capteurs_A.csv
--       * data/seuils_A.csv
--   - Charger avec \copy ... FROM 'data/..._A.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- ----------------------------------------------------------------------------
-- 2. Transformation vers le modèle Relationnel-Objet
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Insérer dans station en construisant l'objet composé ROW(latitude, longitude, altitude)::t_position
--   - Répartir les 36 capteurs dans les sous-tables filles :
--       * capteur_temperature (type = 'temperature')
--       * capteur_air         (type = 'air')
--       * capteur_hydro       (type = 'hydro')
--   - Insérer les seuils d'alerte dans seuil_alerte

-- ----------------------------------------------------------------------------
-- 3. Vérifications de fin d'Étape 1
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Vérifier que SELECT * FROM capteur retourne bien les 36 capteurs (polymorphisme)
--   - Tester (dans des blocs DO / SAVEPOINT) que :
--       * l'insertion d'une humidité > 100% ou d'un PM2.5 < 0 est refusée par la base
--       * l'insertion d'une mesure pour un capteur inexistant est refusée
--   - Exécuter un exemple de requête utilisant distance_km, depasse_seuil_* et conversion d'unité
