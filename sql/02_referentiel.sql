-- =====================================================================
-- 02_referentiel.sql  --  ETAPE 1 (suite) : chargement du référentiel CSV
-- psql -d centre -v ON_ERROR_STOP=1 -f sql/02_referentiel.sql
-- (à lancer depuis la racine du projet : les chemins sont relatifs)
-- =====================================================================

-- Tables de transit (format plat des fichiers fournis)
DROP TABLE IF EXISTS st_station, st_capteur, st_seuil;
CREATE TABLE st_station (
    code varchar(8), nom varchar(60), wilaya varchar(40), zone int,
    latitude numeric, longitude numeric, altitude numeric
);
CREATE TABLE st_capteur (
    code varchar(12), station varchar(8), type varchar(20),
    mise_en_service date, retrait text, etat varchar(20)
);
CREATE TABLE st_seuil (
    type_capteur varchar(20), grandeur varchar(20), borne varchar(3),
    valeur numeric, unite varchar(10)
);

\copy st_station  FROM 'data/stations_A.csv' WITH (FORMAT csv, HEADER true)
\copy st_capteur  FROM 'data/capteurs_A.csv'  WITH (FORMAT csv, HEADER true)
\copy st_seuil    FROM 'data/seuils_A.csv'    WITH (FORMAT csv, HEADER true)

-- Passage du plat au relationnel-objet --------------------------------
TRUNCATE station, capteur, capteur_temperature, capteur_air, capteur_hydro, seuil CASCADE;

INSERT INTO station (code, nom, wilaya, zone, pos)
SELECT code, nom, wilaya, zone,
       ROW(latitude, longitude, altitude)::type_position
FROM st_station;

-- chaque capteur est inséré dans le fils correspondant de la hiérarchie
-- (il reste visible via la table mère 'capteur')
INSERT INTO capteur_temperature (code, station_code, type, mise_en_service, retrait, etat)
SELECT code, station, type, mise_en_service,
       NULLIF(retrait, '')::date, etat
FROM st_capteur WHERE type = 'temperature';

INSERT INTO capteur_air (code, station_code, type, mise_en_service, retrait, etat)
SELECT code, station, type, mise_en_service,
       NULLIF(retrait, '')::date, etat
FROM st_capteur WHERE type = 'air';

INSERT INTO capteur_hydro (code, station_code, type, mise_en_service, retrait, etat)
SELECT code, station, type, mise_en_service,
       NULLIF(retrait, '')::date, etat
FROM st_capteur WHERE type = 'hydro';

INSERT INTO seuil (type_capteur, grandeur, borne, valeur, unite)
SELECT type_capteur, grandeur, borne, valeur, unite FROM st_seuil;

DROP TABLE st_station, st_capteur, st_seuil;

-- Contrôles de chargement
SELECT 'stations' AS table, count(*) FROM station
UNION ALL SELECT 'capteurs (tous niveaux)', count(*) FROM capteur
UNION ALL SELECT 'capteurs temperature', count(*) FROM capteur_temperature
UNION ALL SELECT 'capteurs air', count(*) FROM capteur_air
UNION ALL SELECT 'capteurs hydro', count(*) FROM capteur_hydro
UNION ALL SELECT 'seuils', count(*) FROM seuil;
