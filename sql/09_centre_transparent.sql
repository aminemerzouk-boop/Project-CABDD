-- ============================================================================
-- Script 09 : Transparence de Consultation/Insertion & Rapport Global (Étape 3)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou
-- Base cible : centre
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Tables étrangères (FDW) vers les mesures de zone1 et zone2
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Déclarer les FOREIGN TABLES sur centre pointant vers les tables de mesures
--     de zone1 et zone2 (avec use_remote_estimate 'true' pour optimiser les plans).

-- ----------------------------------------------------------------------------
-- 2. Répartition physique des mesures vers zone1 et zone2
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Déplacer les mesures initialement chargées à l'Étape 2 vers zone1 (Béjaïa, Jijel)
--     et zone2 (Sétif, Bordj Bou Arréridj), puis vider/supprimer le stockage local
--     de mesures sur centre conformément à l'énoncé (« centre ne stocke elle-même aucune mesure »).

-- ----------------------------------------------------------------------------
-- 3. Vues globales transparentes & Routage automatique INSTEAD OF INSERT
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Créer les vues globales (v_mesure_temperature, v_mesure_air, v_mesure_hydro
--     et/ou vue unifiée de toutes les mesures du réseau) combinant zone1 UNION ALL zone2
--     avec prédicat de zone permettant l'élimination de branche par l'optimiseur.
--   - Créer les triggers INSTEAD OF INSERT : une mesure insérée depuis centre
--     recherche la zone de la station du capteur et s'insère physiquement dans
--     zone1 ou zone2 sans que l'utilisateur précise la zone.

-- ----------------------------------------------------------------------------
-- 4. Adaptation du Rapport XML « Bilan Journalier » sur les données réparties
-- ----------------------------------------------------------------------------
-- TODO (Megharba Samou) :
--   - Brancher generer_bilan_journalier_xml(p_date_debut, p_date_fin) sur les vues
--     réparties de centre afin qu'il produise le même bilan sur l'ensemble du réseau.
