-- ============================================================================
-- Script 04 : Chargement du Référentiel CSV (officiels) vers le modèle RO
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou
-- Base cible : centre
-- Prérequis : sql/02_schema_ro.sql et sql/03_operations_ro.sql exécutés
-- À lancer depuis la racine du dépôt (chemins relatifs de \copy)
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Tables de staging : reflet EXACT des en-têtes des fichiers officiels
--    stations_A.csv : code,nom,wilaya,zone,latitude,longitude,altitude_m
--    capteurs_A.csv : code,station,type,mise_en_service,date_retrait,etat
--    seuils_A.csv   : type,grandeur,borne,valeur,unite
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS st_station, st_capteur, st_seuil;

CREATE TEMP TABLE st_station (
    code       VARCHAR,
    nom        VARCHAR,
    wilaya     VARCHAR,
    zone       INT,
    latitude   NUMERIC,
    longitude  NUMERIC,
    altitude_m NUMERIC
);

CREATE TEMP TABLE st_capteur (
    code            VARCHAR,
    station         VARCHAR,
    type            VARCHAR,
    mise_en_service DATE,
    date_retrait    TEXT,
    etat            VARCHAR
);

CREATE TEMP TABLE st_seuil (
    type     VARCHAR,
    grandeur VARCHAR,
    borne    VARCHAR,
    valeur   NUMERIC,
    unite    VARCHAR
);

\copy st_station FROM 'data/stations_A.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy st_capteur FROM 'data/capteurs_A.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy st_seuil   FROM 'data/seuils_A.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- ----------------------------------------------------------------------------
-- 2. Transformation plat -> relationnel-objet
-- ----------------------------------------------------------------------------
TRUNCATE station, capteur, capteur_temperature, capteur_air, capteur_hydro, seuil_alerte RESTART IDENTITY CASCADE;

-- 2a. Stations : lat/lon/altitude_m regroupées dans UN SEUL objet t_position
INSERT INTO station (code_station, nom, wilaya, zone, position)
SELECT code, nom, wilaya, zone, ROW(latitude, longitude, altitude_m)::t_position
FROM st_station;

-- 2b. Capteurs : répartis dans la table fille de leur type (héritage INHERITS,
--     ils restent visibles via la table mère 'capteur'). date_retrait vide -> NULL
INSERT INTO capteur_temperature (code_capteur, code_station, type_capteur,
                                 date_mise_en_service, date_retrait, etat)
SELECT code, station, 'temperature'::type_capteur_enum,
       mise_en_service, NULLIF(date_retrait, '')::date, etat
FROM st_capteur WHERE type = 'temperature';

INSERT INTO capteur_air (code_capteur, code_station, type_capteur,
                         date_mise_en_service, date_retrait, etat)
SELECT code, station, 'air'::type_capteur_enum,
       mise_en_service, NULLIF(date_retrait, '')::date, etat
FROM st_capteur WHERE type = 'air';

INSERT INTO capteur_hydro (code_capteur, code_station, type_capteur,
                           date_mise_en_service, date_retrait, etat)
SELECT code, station, 'hydro'::type_capteur_enum,
       mise_en_service, NULLIF(date_retrait, '')::date, etat
FROM st_capteur WHERE type = 'hydro';

-- 2c. Seuils d'alerte (cast explicite vers type_capteur_enum et borne_seuil_enum)
INSERT INTO seuil_alerte (type_capteur, grandeur, borne, valeur, unite)
SELECT type::type_capteur_enum, grandeur, borne::borne_seuil_enum, valeur, unite
FROM st_seuil;

DROP TABLE st_station, st_capteur, st_seuil;

-- ----------------------------------------------------------------------------
-- 3. Vérifications de fin d'Étape 1
-- ----------------------------------------------------------------------------
-- 3a. Polymorphisme : la table mère renvoie les 36 capteurs, quel que soit le type
SELECT 'capteurs (table mère)' AS table_verifiee, count(*) AS effectif FROM capteur
UNION ALL SELECT 'capteur_temperature', count(*) FROM capteur_temperature
UNION ALL SELECT 'capteur_air',         count(*) FROM capteur_air
UNION ALL SELECT 'capteur_hydro',       count(*) FROM capteur_hydro
UNION ALL SELECT 'stations',            count(*) FROM station
UNION ALL SELECT 'seuils_alerte',       count(*) FROM seuil_alerte;

-- 3b. Exemple d'objet composé manipulé d'un bloc
SELECT code_station, nom, wilaya, zone,
       (position).latitude AS lat,
       (position).longitude AS lon,
       (position).altitude AS alt_m
FROM station
WHERE code_station IN ('BJ-01', 'SE-01');

-- 3c. Exécution des opérations de 03_operations_ro.sql sur le référentiel chargé
SELECT distance_stations_km('BJ-01', 'SE-01') AS distance_BJ01_SE01_km;

SELECT depasse_seuil_temperature(41.2)                         AS temp_41_2_depasse,
       depasse_seuil_air(ROW(30.5, 60.0, 80.0)::t_qualite_air) AS air_depasse,
       depasse_seuil_hydro(ROW(55, 12.0)::t_hydrometrie)       AS hydro_depasse;

SELECT * FROM seuils_franchis('temperature', 'valeur', 41.2);
SELECT * FROM seuils_franchis('air', 'pm25', 30.5);

-- 3d. Tests de rejet : la base se protège seule (contraintes CHECK + triggers hiérarchie)
DO $$
BEGIN
    -- Test 1 : capteur rattaché à une station inexistante dans une table fille
    BEGIN
        INSERT INTO capteur_hydro (code_capteur, code_station, type_capteur,
                                   date_mise_en_service, date_retrait, etat)
        VALUES ('XX-00-H1', 'XX-00', 'hydro', DATE '2026-01-01', NULL, 'actif');
        RAISE EXCEPTION 'ECHEC_TEST : capteur orphelin accepté !';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'OK Test 1 : capteur sans station rattachée refusé.';
    END;

    -- Test 2 : position GPS physiquement impossible (latitude = 999)
    BEGIN
        UPDATE station SET position = ROW(999, 0, 0)::t_position WHERE code_station = 'BJ-01';
        RAISE EXCEPTION 'ECHEC_TEST : position impossible acceptée !';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'OK Test 2 : latitude 999 refusée par CHECK.';
    END;

    -- Test 3 : valeur physiquement impossible (humidité = 130 %)
    BEGIN
        INSERT INTO mesure_hydro (code_capteur, instant_mesure, valeurs_hydro)
        VALUES ('BJ-01-H1', TIMESTAMP '2026-01-01 00:00:00', ROW(130, 0)::t_hydrometrie);
        RAISE EXCEPTION 'ECHEC_TEST : humidité 130 %% acceptée !';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'OK Test 3 : humidité 130 %% refusée par CHECK.';
    END;

    -- Test 4 : mesure pour un capteur inexistant ('XX-00-H9')
    BEGIN
        INSERT INTO mesure_hydro (code_capteur, instant_mesure, valeurs_hydro)
        VALUES ('XX-00-H9', TIMESTAMP '2026-01-01 00:00:00', ROW(55, 0)::t_hydrometrie);
        RAISE EXCEPTION 'ECHEC_TEST : mesure sur capteur inconnu acceptée !';
    EXCEPTION
        WHEN foreign_key_violation OR raise_exception THEN
            RAISE NOTICE 'OK Test 4 : mesure sur capteur inconnu refusée.';
    END;
END $$;
