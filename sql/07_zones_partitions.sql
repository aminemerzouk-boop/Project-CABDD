-- ============================================================================
-- Script 07 : Schéma des Zones 1 & 2, Partitionnement Mensuel et IDs Globaux
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou (partitions) & Merzouk Amine (IDs globaux)
-- Bases cibles : zone1 (Béjaïa, Jijel) et zone2 (Sétif, Bordj Bou Arréridj)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Base zone1 (Wilayas : Béjaïa, Jijel)
-- ----------------------------------------------------------------------------
\connect zone1

-- TODO :
--   a) Créer les mêmes types composés (t_position, t_qualite_air, t_hydrometrie)
--      et la copie locale du référentiel (station, hiérarchie capteur*, seuil_alerte)
--      nécessaire au contrôle local des mesures de la Zone 1.
--   b) Séquence globale sans collision (Merzouk Amine) :
--      CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH 1; -- IDs impairs en zone1
--   c) Organisation temporelle par mois (Megharba Samou — Variante A) :
--      Créer les tables de mesures partitionnées PARTITION BY RANGE (instant_mesure) :
--        * Partition 2026_01 : ['2026-01-01', '2026-02-01')
--        * Partition 2026_02 : ['2026-02-01', '2026-03-01')
--        * Partition 2026_03 : ['2026-03-01', '2026-04-01')
--        * Partition 2026_04 : ['2026-04-01', '2026-05-01')
--        * Partition complémentaire / DEFAULT pour les insertions futures de démonstration
--   d) Contrainte locale vérifiant qu'aucune mesure d'une station hors Zone 1 n'est stockée ici.

-- ----------------------------------------------------------------------------
-- 2. Base zone2 (Wilayas : Sétif, Bordj Bou Arréridj)
-- ----------------------------------------------------------------------------
\connect zone2

-- TODO :
--   a) Même structure locale du référentiel et des types composés.
--   b) Séquence globale sans collision (Merzouk Amine) :
--      CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH 2; -- IDs pairs en zone2
--   c) Mêmes partitions mensuelles PARTITION BY RANGE (instant_mesure).
--   d) Contrainte locale limitant le stockage aux stations de la Zone 2.
