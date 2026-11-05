-- ============================================================================
-- Script 08 : Propagation Automatique du Référentiel centre -> zone1 & zone2
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Merzouk Amine
-- Base cible : centre
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Déclaration des serveurs distants postgres_fdw (srv_zone1, srv_zone2)
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - CREATE SERVER srv_zone1 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (dbname 'zone1', ...);
--   - CREATE SERVER srv_zone2 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (dbname 'zone2', ...);
--   - CREATE USER MAPPING FOR CURRENT_USER SERVER srv_zone1 ...
--   - Tables étrangères pointant vers le référentiel de zone1 et zone2

-- ----------------------------------------------------------------------------
-- 2. Synchronisation initiale du référentiel existant vers zone1 et zone2
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Copier le référentiel initial chargé sur centre (stations, capteurs, seuils)
--     vers zone1 et zone2.

-- ----------------------------------------------------------------------------
-- 3. Triggers de propagation automatique (INSERT / UPDATE / DELETE contrôlé)
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Sur modification de station, capteur (et sous-tables), ou seuil_alerte dans centre :
--     répercuter automatiquement l'ajout ou la mise à jour (ex. changement d'état,
--     date de retrait, nouvelle station, nouveau seuil) dans zone1 et zone2 sans ressaisie.
--   - Protéger les copies locales dans zone1 et zone2 contre les modifications directes
--     hors propagation depuis centre.
