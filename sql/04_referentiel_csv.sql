-- ============================================================================
-- Script 04 : Chargement du Référentiel CSV (officiels) vers le modèle RO
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou
-- Base cible : centre
-- Prérequis : sql/02_schema_ro.sql exécuté (types composés, tables station,
--             hiérarchie capteur*, seuil_alerte)
-- A lancer depuis la racine du dépôt (chemins relatifs de \copy)
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Tables de staging : reflet EXACT des en-têtes des fichiers officiels
--    stations_A.csv : code,nom,wilaya,zone,latitude,longitude,altitude_m
--    capteurs_A.csv : code,station,type,mise_en_service,date_retrait,etat
--    seuils_A.csv   : type,grandeur,borne,valeur,unite
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS st_station, st_capteur, st_seuil;
CREATE TEMP TABLE st_station(code varchar, nom varchar, wilaya varchar, zone int,
                             latitude numeric, longitude numeric, altitude_m numeric);
CREATE TEMP TABLE st_capteur(code varchar, station varchar, type varchar,
                             mise_en_service date, date_retrait text, etat varchar);
CREATE TEMP TABLE st_seuil(type varchar, grandeur varchar, borne varchar,
                           valeur numeric, unite varchar);

\copy st_station FROM 'data/stations_A.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy st_capteur FROM 'data/capteurs_A.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy st_seuil   FROM 'data/seuils_A.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- ----------------------------------------------------------------------------
-- 2. Transformation plat -> relationnel-objet
-- ----------------------------------------------------------------------------
TRUNCATE station, capteur, capteur_temperature, capteur_air, capteur_hydro, seuil_alerte CASCADE;

-- 2a. Stations : lat/lon/altitude_m regroupées dans UN SEUL objet t_position
INSERT INTO station (code_station, nom, wilaya, zone, position)
SELECT code, nom, wilaya, zone, ROW(latitude, longitude, altitude_m)::t_position
FROM st_station;

-- 2b. Capteurs : répartis dans la table fille de leur type (héritage INHERITS,
--     ils restent visibles via la table mère 'capteur'). date_retrait vide -> NULL
INSERT INTO capteur_temperature (code_capteur, code_station, type_capteur,
                                 date_mise_en_service, date_retrait, etat)
SELECT code, station, 'temperature', mise_en_service, NULLIF(date_retrait, '')::date, etat
FROM st_capteur WHERE type = 'temperature';

INSERT INTO capteur_air (code_capteur, code_station, type_capteur,
                         date_mise_en_service, date_retrait, etat)
SELECT code, station, 'air', mise_en_service, NULLIF(date_retrait, '')::date, etat
FROM st_capteur WHERE type = 'air';

INSERT INTO capteur_hydro (code_capteur, code_station, type_capteur,
                           date_mise_en_service, date_retrait, etat)
SELECT code, station, 'hydro', mise_en_service, NULLIF(date_retrait, '')::date, etat
FROM st_capteur WHERE type = 'hydro';

-- 2c. Seuils d'alerte
INSERT INTO seuil_alerte (type_capteur, grandeur, borne, valeur, unite)
SELECT type, grandeur, borne::borne_seuil_enum, valeur, unite FROM st_seuil;

DROP TABLE st_station, st_capteur, st_seuil;

-- ----------------------------------------------------------------------------
-- 3. Vérifications de fin d'Étape 1
-- ----------------------------------------------------------------------------
-- 3a. Polymorphisme : la table mère renvoie les 36 capteurs, quel que soit le type
SELECT 'capteurs (table mère)' AS test, count(*) AS resultat FROM capteur
UNION ALL SELECT 'capteur_temperature', count(*) FROM capteur_temperature
UNION ALL SELECT 'capteur_air',         count(*) FROM capteur_air
UNION ALL SELECT 'capteur_hydro',       count(*) FROM capteur_hydro
UNION ALL SELECT 'stations',            count(*) FROM station
UNION ALL SELECT 'seuils',              count(*) FROM seuil_alerte;

-- 3b. Exemple d'objet composé manipulé d'un bloc
SELECT code_station, (position).latitude AS lat, (position).longitude AS lon,
       (position).altitude AS alt_m, zone
FROM station WHERE code_station IN ('BJ-01', 'SE-01');

-- 3c. Les opérations de la tâche 03 fonctionnent sur le référentiel chargé
SELECT distance_stations_km('BJ-01', 'SE-01') AS distance_BJ01_SE01_km;
SELECT * FROM seuils_franchis('temperature', 'valeur', 41.2);   -- seuil max 35 °C franchi

-- 3d. Tests de rejet : la base se protège seule
DO $$
BEGIN
    BEGIN
        -- NB : avec INHERITS, la FK déclarée sur la table mère n'est pas héritée
        -- par les filles : ce test vise la table mère (les triggers de 02
        -- couvriront les insertions directes dans les filles)
        INSERT INTO capteur (code_capteur, code_station, type_capteur,
                             date_mise_en_service, date_retrait, etat)
        VALUES ('XX-00-H1', 'XX-00', 'hydro', DATE '2026-01-01', NULL, 'actif');
        RAISE NOTICE 'ECHEC : capteur orphelin accepté !';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK : capteur sans station rattachée refusé (FK)';
    END;
    BEGIN
        UPDATE station SET position = ROW(999, 0, 0)::t_position WHERE code_station = 'BJ-01';
        RAISE NOTICE 'ECHEC : position impossible acceptée !';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK : latitude 999 refusée par le CHECK';
    END;
END $$;
