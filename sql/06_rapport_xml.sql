-- ============================================================================
-- Script 06 : Génération du Rapport XML « Bilan Journalier » (Étape 2)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- Spécification du rapport XML de la Variante A :
--   Pour chaque jour de la période [p_date_debut, p_date_fin],
--   chaque station et chaque grandeur mesurée
--   (temperature, pm25, pm10, no2, humidite, pluie) :
--     - minimum des mesures valides
--     - maximum des mesures valides
--     - moyenne des mesures valides (arrondie p. ex. à 2 décimales)
--     - nombre de mesures utilisées
--   Important : tenir compte des dates de mise en service et de retrait
--   des capteurs figurant dans le référentiel !
-- ----------------------------------------------------------------------------

-- TODO (Megharba Samou) :
--   1. Définir la fonction generer_bilan_journalier_xml(p_date_debut DATE, p_date_fin DATE) RETURNS XML
--      utilisant xmlelement, xmlattributes et xmlagg.
--   2. Structure XML cible proposée (à justifier dans le rapport) :
--      <bilanJournalier debut="2026-02-01" fin="2026-02-07">
--        <jour date="2026-02-01">
--          <station code="BJ-01" nom="..." wilaya="Béjaïa" zone="1">
--            <grandeur nom="temperature" unite="°C" nbMesures="8">
--              <min>...</min><max>...</max><moyenne>...</moyenne>
--            </grandeur>
--            ...
--          </station>
--        </jour>
--      </bilanJournalier>
--   3. Tester la génération sur une période exemple (ex. 1re semaine de février 2026).
