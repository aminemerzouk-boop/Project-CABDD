-- ============================================================================
-- Script 07 : Schémas des zones zone1 & zone2, partitionnement MENSUEL et IDs
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable : Megharba Samou (partitions + schéma) & Merzouk Amine (IDs)
-- Exécution :
--   psql -d zone1 -v zone_num=1 -f sql/07_zones_partitions.sql
--   psql -d zone2 -v zone_num=2 -f sql/07_zones_partitions.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Types composés + copie locale du référentiel (nécessaire au contrôle
--    local des mesures : chaque zone valide seule ses propres mesures)
-- ----------------------------------------------------------------------------
CREATE TYPE t_position AS (latitude NUMERIC(9,6), longitude NUMERIC(9,6), altitude NUMERIC(7,2));
CREATE TYPE t_qualite_air AS (pm25 NUMERIC(7,2), pm10 NUMERIC(7,2), no2 NUMERIC(7,2));
CREATE TYPE t_hydrometrie AS (humidite NUMERIC(5,2), pluie NUMERIC(7,2));
CREATE TYPE borne_seuil_enum AS ENUM ('min','max');
CREATE TYPE motif_rejet_enum AS ENUM ('valeur_impossible','valeur_manquante','format_invalide','capteur_inconnu','doublon');

CREATE TABLE station (code_station VARCHAR(10) PRIMARY KEY, nom VARCHAR(100) NOT NULL,
  wilaya VARCHAR(60) NOT NULL, zone SMALLINT NOT NULL CHECK (zone IN (1,2)), position t_position NOT NULL,
  CONSTRAINT pos_ok CHECK ((position).latitude BETWEEN -90 AND 90 AND (position).longitude BETWEEN -180 AND 180));
CREATE TABLE capteur (code_capteur VARCHAR(15) PRIMARY KEY, code_station VARCHAR(10) NOT NULL REFERENCES station(code_station),
  type_capteur VARCHAR(20) NOT NULL CHECK (type_capteur IN ('temperature','air','hydro')),
  date_mise_en_service DATE NOT NULL, date_retrait DATE, etat VARCHAR(30) NOT NULL);
CREATE TABLE capteur_temperature () INHERITS (capteur);
CREATE TABLE capteur_air         () INHERITS (capteur);
CREATE TABLE capteur_hydro       () INHERITS (capteur);
CREATE TABLE seuil_alerte (id_seuil SERIAL PRIMARY KEY, type_capteur VARCHAR(20) NOT NULL,
  grandeur VARCHAR(30) NOT NULL, borne borne_seuil_enum NOT NULL, valeur NUMERIC(10,2) NOT NULL, unite VARCHAR(20) NOT NULL);

-- ----------------------------------------------------------------------------
-- 2. Séquence d'identifiants UNIQUE sur tout le réseau (Merzouk Amine) :
--    zone1 -> IDs IMPAIRS (INCREMENT 2 START 1), zone2 -> IDs PAIRS (START 2)
-- ----------------------------------------------------------------------------
CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH :zone_num;

-- ----------------------------------------------------------------------------
-- 3. Tables de mesures PARTITIONNÉES PAR MOIS (Variante A)
--    Trois tables typées, partitionnées par RANGE sur instant_mesure.
--    La clé primaire inclut la clé de partition (exigence PostgreSQL).
-- ----------------------------------------------------------------------------
CREATE TABLE mesure_temperature (
    id_mesure BIGINT NOT NULL DEFAULT nextval('seq_mesure'),
    code_capteur VARCHAR(15) NOT NULL REFERENCES capteur(code_capteur),
    instant_mesure TIMESTAMP NOT NULL,
    temperature NUMERIC(5,2) CHECK (temperature BETWEEN -60 AND 65),
    id_lot INT,
    PRIMARY KEY (id_mesure, instant_mesure)
) PARTITION BY RANGE (instant_mesure);

CREATE TABLE mesure_air (
    id_mesure BIGINT NOT NULL DEFAULT nextval('seq_mesure'),
    code_capteur VARCHAR(15) NOT NULL REFERENCES capteur(code_capteur),
    instant_mesure TIMESTAMP NOT NULL,
    valeurs_air t_qualite_air,
    id_lot INT,
    PRIMARY KEY (id_mesure, instant_mesure),
    CONSTRAINT air_ok CHECK ((valeurs_air).pm25 >= 0 AND (valeurs_air).pm10 >= 0 AND (valeurs_air).no2 >= 0)
) PARTITION BY RANGE (instant_mesure);

CREATE TABLE mesure_hydro (
    id_mesure BIGINT NOT NULL DEFAULT nextval('seq_mesure'),
    code_capteur VARCHAR(15) NOT NULL REFERENCES capteur(code_capteur),
    instant_mesure TIMESTAMP NOT NULL,
    valeurs_hydro t_hydrometrie,
    id_lot INT,
    PRIMARY KEY (id_mesure, instant_mesure),
    CONSTRAINT hydro_ok CHECK ((valeurs_hydro).humidite BETWEEN 0 AND 100 AND (valeurs_hydro).pluie >= 0)
) PARTITION BY RANGE (instant_mesure);

-- Partitions mensuelles 2026_01 .. 2026_04 + DEFAULT (démonstrations futures)
DO $$
DECLARE
    t text;                  -- nom de la table typée
    m text;                  -- nom de la partition
    d date;                  -- début du mois
    fin date;
BEGIN
    FOREACH t IN ARRAY ARRAY['mesure_temperature','mesure_air','mesure_hydro'] LOOP
        d := DATE '2026-01-01';
        WHILE d < DATE '2026-05-01' LOOP
            fin := d + INTERVAL '1 month';
            m := t || '_2026_' || to_char(d, 'MM');
            EXECUTE format('CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
                           m, t, d, fin);
            d := fin;
        END LOOP;
        EXECUTE format('CREATE TABLE %I_default PARTITION OF %I DEFAULT', t, t);
    END LOOP;
END $$;

CREATE INDEX ON mesure_temperature (code_capteur, instant_mesure);
CREATE INDEX ON mesure_air         (code_capteur, instant_mesure);
CREATE INDEX ON mesure_hydro       (code_capteur, instant_mesure);

-- ----------------------------------------------------------------------------
-- 4. Contrainte de ZONE : aucune mesure d'une station hors de la zone
--    (la zone ne stocke que ses propres mesures)
-- ----------------------------------------------------------------------------
-- la zone courante est stockée dans une table de config (persistante)
CREATE TABLE config_zone (zone_num INT PRIMARY KEY);
INSERT INTO config_zone VALUES (:'zone_num');

CREATE OR REPLACE FUNCTION verif_zone() RETURNS trigger AS $$
BEGIN
    IF (SELECT s.zone FROM station s JOIN capteur c ON c.code_station = s.code_station
        WHERE c.code_capteur = NEW.code_capteur) <> (SELECT zone_num FROM config_zone) THEN
        RAISE EXCEPTION 'La mesure du capteur % appartient à une autre zone', NEW.code_capteur;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_zone_temperature BEFORE INSERT ON mesure_temperature
    FOR EACH ROW EXECUTE FUNCTION verif_zone();
CREATE TRIGGER trg_zone_air BEFORE INSERT ON mesure_air
    FOR EACH ROW EXECUTE FUNCTION verif_zone();
CREATE TRIGGER trg_zone_hydro BEFORE INSERT ON mesure_hydro
    FOR EACH ROW EXECUTE FUNCTION verif_zone();

-- ----------------------------------------------------------------------------
-- 5. Vue aplatie locale (réutilisée par la tâche 09 pour la fédération)
-- ----------------------------------------------------------------------------
CREATE VIEW v_mesure_plat AS
SELECT mt.instant_mesure::date AS jour, c.code_station, 'temperature' AS grandeur,
       '°C' AS unite, mt.temperature AS valeur
FROM mesure_temperature mt JOIN capteur c ON c.code_capteur = mt.code_capteur
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'pm25', 'µg/m3', (ma.valeurs_air).pm25
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'pm10', 'µg/m3', (ma.valeurs_air).pm10
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
UNION ALL
SELECT ma.instant_mesure::date, c.code_station, 'no2', 'µg/m3', (ma.valeurs_air).no2
FROM mesure_air ma JOIN capteur c ON c.code_capteur = ma.code_capteur
UNION ALL
SELECT mh.instant_mesure::date, c.code_station, 'humidite', '%', (mh.valeurs_hydro).humidite
FROM mesure_hydro mh JOIN capteur c ON c.code_capteur = mh.code_capteur
UNION ALL
SELECT mh.instant_mesure::date, c.code_station, 'pluie', 'mm', (mh.valeurs_hydro).pluie
FROM mesure_hydro mh JOIN capteur c ON c.code_capteur = mh.code_capteur;

-- ----------------------------------------------------------------------------
-- 6. Vérification : partitions créées + élagage (partition pruning)
-- ----------------------------------------------------------------------------
SELECT inhparent::regclass AS table_mere, inhrelid::regclass AS partition
FROM pg_inherits WHERE inhparent::regclass::text LIKE 'mesure_%'
ORDER BY 1, 2;

-- Une requête sur UN mois ne lit QUE la partition de ce mois :
EXPLAIN (COSTS OFF)
SELECT count(*) FROM mesure_hydro
WHERE instant_mesure >= '2026-02-01' AND instant_mesure < '2026-03-01';
