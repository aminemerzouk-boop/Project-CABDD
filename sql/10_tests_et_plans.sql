-- ============================================================================
-- Script 10 : Validation Complète, Plans d'Exécution & Tests de Résilience
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsables : Merzouk Amine & Megharba Samou (ensemble)
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Tests Étape 1 (Modèle RO, Contraintes & Opérations)
-- ----------------------------------------------------------------------------
-- TODO :
--   - Interroger tous les capteurs via la table mère capteur (36 capteurs attendus)
--   - Calculer la distance en km entre une station de Béjaïa (Zone 1) et Sétif (Zone 2)
--   - Tester la détection de dépassement de seuil et la conversion d'unité

-- ----------------------------------------------------------------------------
-- 2. Tests Étape 2 (Bilan XML entrant, Lots bruts XPath & Rapport XML)
-- ----------------------------------------------------------------------------
-- TODO :
--   - Afficher le décompte : mesures valides + mesures isolées (par motif) = total XML
--   - Exécuter les 2 requêtes XPath sur lot_brut (lots d'un capteur donné + nb mesures/lot)

-- ----------------------------------------------------------------------------
-- 3. Tests Étape 3 (Propagation, Insertion Transparente, Unicité IDs & Plans)
-- ----------------------------------------------------------------------------
-- TODO :
--   a) Ajouter un capteur de test ou modifier l'état d'un capteur dans centre
--      et vérifier sa présence immédiate dans zone1 et zone2.
--   b) Insérer deux mesures depuis centre (une pour Béjaïa, une pour Sétif) sans
--      préciser la zone : vérifier leur stockage physique respectif dans zone1 et zone2
--      et l'unicité de leurs identifiants (impair vs pair).
--   c) Plans d'exécution commentés pour le rapport :
--      EXPLAIN (ANALYZE, VERBOSE) d'une requête depuis centre ciblant
--      UNE SEULE ZONE (ex. Zone 1 : Béjaïa) et UN SEUL MOIS (ex. février 2026),
--      et vérifier sur zone1 le Partition Pruning mensuel.
--   d) Générer un extrait du rapport XML Bilan journalier depuis centre.
--   e) Scénario de panne simulée d'une zone (ex. port invalide temporaire sur srv_zone2
--      dans une transaction annulée par ROLLBACK) pour observer le comportement exact.
