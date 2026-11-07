-- ============================================================================
-- Script 09 : Transparence de Consultation/Insertion & Rapport Global (Étape 3)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou
-- Base cible : centre
-- Prérequis : 01..08 exécutés (serveurs FDW srv_zone1/srv_zone2 de 08,
--             mesures chargées sur centre à l'étape 2, schémas des zones de 07)
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Tables étrangères (FDW) vers les MESURES de zone1 et zone2
--    (les serveurs srv_zone1 / srv_zone2 + user mappings viennent du script 08)
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS z1_mes;
CREATE SCHEMA IF NOT EXISTS z2_mes;

-- NB : IMPORT FOREIGN SCHEMA ignore les tables partitionnées -> foreign tables
-- créées manuellement vers les tables parentes distantes (postgres_fdw interroge
-- alors toutes les partitions distantes)
CREATE FOREIGN TABLE z1_mes.mesure_temperature (
    id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP,
    temperature NUMERIC(6,2), id_lot BIGINT)
    SERVER srv_zone1 OPTIONS (schema_name 'public', table_name 'mesure_temperature');
CREATE FOREIGN TABLE z1_mes.mesure_air (
    id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP,
    valeurs_air t_qualite_air, id_lot BIGINT)
    SERVER srv_zone1 OPTIONS (schema_name 'public', table_name 'mesure_air');
CREATE FOREIGN TABLE z1_mes.mesure_hydro (
    id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP,
    valeurs_hydro t_hydrometrie, id_lot BIGINT)
    SERVER srv_zone1 OPTIONS (schema_name 'public', table_name 'mesure_hydro');
CREATE FOREIGN TABLE z2_mes.mesure_temperature (
    id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP,
    temperature NUMERIC(6,2), id_lot BIGINT)
    SERVER srv_zone2 OPTIONS (schema_name 'public', table_name 'mesure_temperature');
CREATE FOREIGN TABLE z2_mes.mesure_air (
    id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP,
    valeurs_air t_qualite_air, id_lot BIGINT)
    SERVER srv_zone2 OPTIONS (schema_name 'public', table_name 'mesure_air');
CREATE FOREIGN TABLE z2_mes.mesure_hydro (
    id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP,
    valeurs_hydro t_hydrometrie, id_lot BIGINT)
    SERVER srv_zone2 OPTIONS (schema_name 'public', table_name 'mesure_hydro');
-- Séquences miroir côté centre, MÊME parité que les zones (07) :
--   ids impairs -> zone1, ids pairs -> zone2  => unicité réseau garantie
--   (toutes les insertions passant par le routeur du centre)
CREATE SEQUENCE IF NOT EXISTS seq_mesure_z1 INCREMENT BY 2 START WITH 1;
CREATE SEQUENCE IF NOT EXISTS seq_mesure_z2 INCREMENT BY 2 START WITH 2;

-- ----------------------------------------------------------------------------
-- 2. Répartition physique : migration des mesures du centre vers les zones
--    (zone de la station du capteur). L'id est généré CÔTÉ ZONE par sa
--    séquence (impair en zone1, pair en zone2) -> unicité réseau garantie.
-- ----------------------------------------------------------------------------
INSERT INTO z1_mes.mesure_temperature (id_mesure, code_capteur, instant_mesure, temperature, id_lot)
SELECT nextval('seq_mesure_z1'), mt.code_capteur, mt.instant_mesure, mt.temperature, mt.id_lot
FROM mesure_temperature mt
JOIN capteur c ON c.code_capteur = mt.code_capteur
JOIN station s ON s.code_station = c.code_station
WHERE s.zone = 1;

INSERT INTO z2_mes.mesure_temperature (id_mesure, code_capteur, instant_mesure, temperature, id_lot)
SELECT nextval('seq_mesure_z2'), mt.code_capteur, mt.instant_mesure, mt.temperature, mt.id_lot
FROM mesure_temperature mt
JOIN capteur c ON c.code_capteur = mt.code_capteur
JOIN station s ON s.code_station = c.code_station
WHERE s.zone = 2;

INSERT INTO z1_mes.mesure_air (id_mesure, code_capteur, instant_mesure, valeurs_air, id_lot)
SELECT nextval('seq_mesure_z1'), ma.code_capteur, ma.instant_mesure, ma.valeurs_air, ma.id_lot
FROM mesure_air ma
JOIN capteur c ON c.code_capteur = ma.code_capteur
JOIN station s ON s.code_station = c.code_station
WHERE s.zone = 1;

INSERT INTO z2_mes.mesure_air (id_mesure, code_capteur, instant_mesure, valeurs_air, id_lot)
SELECT nextval('seq_mesure_z2'), ma.code_capteur, ma.instant_mesure, ma.valeurs_air, ma.id_lot
FROM mesure_air ma
JOIN capteur c ON c.code_capteur = ma.code_capteur
JOIN station s ON s.code_station = c.code_station
WHERE s.zone = 2;

INSERT INTO z1_mes.mesure_hydro (id_mesure, code_capteur, instant_mesure, valeurs_hydro, id_lot)
SELECT nextval('seq_mesure_z1'), mh.code_capteur, mh.instant_mesure, mh.valeurs_hydro, mh.id_lot
FROM mesure_hydro mh
JOIN capteur c ON c.code_capteur = mh.code_capteur
JOIN station s ON s.code_station = c.code_station
WHERE s.zone = 1;

INSERT INTO z2_mes.mesure_hydro (id_mesure, code_capteur, instant_mesure, valeurs_hydro, id_lot)
SELECT nextval('seq_mesure_z2'), mh.code_capteur, mh.instant_mesure, mh.valeurs_hydro, mh.id_lot
FROM mesure_hydro mh
JOIN capteur c ON c.code_capteur = mh.code_capteur
JOIN station s ON s.code_station = c.code_station
WHERE s.zone = 2;

-- ----------------------------------------------------------------------------
-- 3. Le centre ne stocke plus aucune mesure : les tables locales deviennent
--    des VUES globales transparentes sur zone1 UNION ALL zone2
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS v_mesure_plat;
DROP TABLE IF EXISTS mesure_temperature, mesure_air, mesure_hydro, mesure CASCADE;

CREATE VIEW mesure_temperature AS
    SELECT * FROM z1_mes.mesure_temperature
    UNION ALL
    SELECT * FROM z2_mes.mesure_temperature;
CREATE VIEW mesure_air AS
    SELECT * FROM z1_mes.mesure_air
    UNION ALL
    SELECT * FROM z2_mes.mesure_air;
CREATE VIEW mesure_hydro AS
    SELECT * FROM z1_mes.mesure_hydro
    UNION ALL
    SELECT * FROM z2_mes.mesure_hydro;
CREATE VIEW mesure AS
    SELECT id_mesure, code_capteur, instant_mesure, id_lot FROM mesure_temperature
    UNION ALL
    SELECT id_mesure, code_capteur, instant_mesure, id_lot FROM mesure_air
    UNION ALL
    SELECT id_mesure, code_capteur, instant_mesure, id_lot FROM mesure_hydro;

-- Vue aplatie reprise par generer_bilan_journalier_xml (script 06)
CREATE VIEW v_mesure_plat AS
SELECT mt.instant_mesure::date AS jour, c.code_station, 'temperature' AS grandeur,
       '°C' AS unite, mt.temperature AS valeur
FROM mesure_temperature mt JOIN capteur c ON c.code_capteur = mt.code_capteur
WHERE mt.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mt.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'pm25', 'µg/m3', (ma.valeurs_air).pm25
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'pm10', 'µg/m3', (ma.valeurs_air).pm10
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'no2', 'µg/m3', (ma.valeurs_air).no2
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
WHERE ma.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR ma.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT mh.instant_mesure::date, c.code_station, 'humidite', '%', (mh.valeurs_hydro).humidite
FROM mesure_hydro mh JOIN capteur c ON c.code_capteur = mh.code_capteur
WHERE mh.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mh.instant_mesure::date <= c.date_retrait)
UNION ALL
SELECT mh.instant_mesure::date, c.code_station, 'pluie', 'mm', (mh.valeurs_hydro).pluie
FROM mesure_hydro mh JOIN capteur c ON c.code_capteur = mh.code_capteur
WHERE mh.instant_mesure::date >= c.date_mise_en_service
  AND (c.date_retrait IS NULL OR mh.instant_mesure::date <= c.date_retrait);

-- ----------------------------------------------------------------------------
-- 4. Routage automatique : une mesure insérée depuis le centre est stockée
--    physiquement dans la BONNE zone, sans que l'utilisateur la précise
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION router_mesure_temperature() RETURNS trigger AS $$
DECLARE v_zone smallint;
BEGIN
    SELECT s.zone INTO v_zone FROM station s
    JOIN capteur c ON c.code_station = s.code_station
    WHERE c.code_capteur = NEW.code_capteur;
    IF v_zone = 1 THEN
        INSERT INTO z1_mes.mesure_temperature (id_mesure, code_capteur, instant_mesure, temperature, id_lot)
        VALUES (nextval('seq_mesure_z1'), NEW.code_capteur, NEW.instant_mesure, NEW.temperature, NEW.id_lot);
    ELSIF v_zone = 2 THEN
        INSERT INTO z2_mes.mesure_temperature (id_mesure, code_capteur, instant_mesure, temperature, id_lot)
        VALUES (nextval('seq_mesure_z2'), NEW.code_capteur, NEW.instant_mesure, NEW.temperature, NEW.id_lot);
    ELSE
        RAISE EXCEPTION 'Capteur % inconnu du référentiel', NEW.code_capteur;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION router_mesure_air() RETURNS trigger AS $$
DECLARE v_zone smallint;
BEGIN
    SELECT s.zone INTO v_zone FROM station s
    JOIN capteur c ON c.code_station = s.code_station
    WHERE c.code_capteur = NEW.code_capteur;
    IF v_zone = 1 THEN
        INSERT INTO z1_mes.mesure_air (id_mesure, code_capteur, instant_mesure, valeurs_air, id_lot)
        VALUES (nextval('seq_mesure_z1'), NEW.code_capteur, NEW.instant_mesure, NEW.valeurs_air, NEW.id_lot);
    ELSIF v_zone = 2 THEN
        INSERT INTO z2_mes.mesure_air (id_mesure, code_capteur, instant_mesure, valeurs_air, id_lot)
        VALUES (nextval('seq_mesure_z2'), NEW.code_capteur, NEW.instant_mesure, NEW.valeurs_air, NEW.id_lot);
    ELSE
        RAISE EXCEPTION 'Capteur % inconnu du référentiel', NEW.code_capteur;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION router_mesure_hydro() RETURNS trigger AS $$
DECLARE v_zone smallint;
BEGIN
    SELECT s.zone INTO v_zone FROM station s
    JOIN capteur c ON c.code_station = s.code_station
    WHERE c.code_capteur = NEW.code_capteur;
    IF v_zone = 1 THEN
        INSERT INTO z1_mes.mesure_hydro (id_mesure, code_capteur, instant_mesure, valeurs_hydro, id_lot)
        VALUES (nextval('seq_mesure_z1'), NEW.code_capteur, NEW.instant_mesure, NEW.valeurs_hydro, NEW.id_lot);
    ELSIF v_zone = 2 THEN
        INSERT INTO z2_mes.mesure_hydro (id_mesure, code_capteur, instant_mesure, valeurs_hydro, id_lot)
        VALUES (nextval('seq_mesure_z2'), NEW.code_capteur, NEW.instant_mesure, NEW.valeurs_hydro, NEW.id_lot);
    ELSE
        RAISE EXCEPTION 'Capteur % inconnu du référentiel', NEW.code_capteur;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ins_mesure_temperature INSTEAD OF INSERT ON mesure_temperature
    FOR EACH ROW EXECUTE FUNCTION router_mesure_temperature();
CREATE TRIGGER trg_ins_mesure_air INSTEAD OF INSERT ON mesure_air
    FOR EACH ROW EXECUTE FUNCTION router_mesure_air();
CREATE TRIGGER trg_ins_mesure_hydro INSTEAD OF INSERT ON mesure_hydro
    FOR EACH ROW EXECUTE FUNCTION router_mesure_hydro();

-- ----------------------------------------------------------------------------
-- 5. Démonstrations (pour le rapport)
-- ----------------------------------------------------------------------------
-- 5a. Une seule requête SQL voit tout le réseau depuis le centre
SELECT s.zone, count(*) AS nb_mesures
FROM mesure_temperature mt
JOIN capteur c ON c.code_capteur = mt.code_capteur
JOIN station s ON s.code_station = c.code_station
GROUP BY s.zone ORDER BY s.zone;

-- 5b. Insertion transparente : la mesure part toute seule dans la bonne zone
INSERT INTO mesure_temperature (code_capteur, instant_mesure, temperature)
VALUES ('BJ-01-T1', '2026-05-02T06:00:00', 21.5);
SELECT 'zone1' AS stockage, id_mesure, code_capteur, temperature FROM z1_mes.mesure_temperature
WHERE code_capteur = 'BJ-01-T1' AND instant_mesure = '2026-05-02T06:00:00';

-- 5c. Unicité des identifiants sur tout le réseau
SELECT count(*) AS total, count(DISTINCT id_mesure) AS distincts FROM mesure;

-- 5d. Le rapport XML bilan journalier fonctionne depuis le centre (script 06)
SELECT generer_bilan_journalier_xml(DATE '2026-02-01', DATE '2026-02-02');

-- 5e. Plan d'exécution : requête centre -> 1 zone / 1 mois
EXPLAIN (COSTS OFF)
SELECT count(*) FROM mesure_hydro
WHERE instant_mesure >= '2026-02-01' AND instant_mesure < '2026-03-01';
