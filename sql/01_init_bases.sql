-- ============================================================================
-- Script 01 : Initialisation des trois bases et extensions PostgreSQL
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou
-- Exécution : psql -U postgres -f sql/01_init_bases.sql
-- ============================================================================

-- Nettoyage optionnel sur une installation de test (à adapter si besoin)
DROP DATABASE IF EXISTS centre;
DROP DATABASE IF EXISTS zone1;
DROP DATABASE IF EXISTS zone2;

-- Création des trois bases exigées par l'Étape 3 :
--   - centre : référentiel maître + vue globale transparente + rapport XML
--   - zone1  : mesures de Béjaïa et Jijel (partitionnées par mois) + copie référentiel
--   - zone2  : mesures de Sétif et Bordj Bou Arréridj (partitionnées par mois) + copie référentiel
CREATE DATABASE centre ENCODING 'UTF8';
CREATE DATABASE zone1  ENCODING 'UTF8';
CREATE DATABASE zone2  ENCODING 'UTF8';

\connect centre
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

\connect zone1
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

\connect zone2
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
