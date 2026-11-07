-- ============================================================================
-- Script 01 : Initialisation des trois bases et extensions PostgreSQL
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Megharba Samou
-- Exécution : psql -h 127.0.0.1 -U postgres -d postgres -f sql/01_init_bases.sql
-- ============================================================================

-- Se placer sur 'postgres' pour pouvoir supprimer proprement les 3 bases
\connect postgres

-- Nettoyage propre sur une installation de test (WITH (FORCE) ferme les
-- connexions actives éventuelles de VS Code sous PostgreSQL 13–18)
DROP DATABASE IF EXISTS centre WITH (FORCE);
DROP DATABASE IF EXISTS zone1  WITH (FORCE);
DROP DATABASE IF EXISTS zone2  WITH (FORCE);

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
