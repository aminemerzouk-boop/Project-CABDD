-- =====================================================================
-- 01_schema.sql  --  ETAPE 1 : schéma relationnel-objet (base 'centre')
-- psql -d centre -f sql/01_schema.sql
--
-- Choix forts :
--  * types composés (position, mesure_air, mesure_hydro) : une valeur
--    structurée manipulable d'un bloc, jamais éclatée en colonnes.
--  * hiérarchie de capteurs et de mesures par HERITAGE de tables :
--    interroger la table mère renvoie tous les objets, quel que soit le type.
--  * contraintes CHECK : la base refuse seule toute valeur physiquement
--    impossible ; FK vers la table mère capteur : toute mesure doit porter
--    sur un capteur existant, à n'importe quel niveau de la hiérarchie.
--  * fonctions SQL : distance, test de seuil, conversion d'unité.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Types composés (objets)
-- ---------------------------------------------------------------------
CREATE TYPE type_position AS (
    latitude  numeric(9,6),
    longitude numeric(9,6),
    altitude  numeric(8,2)          -- mètres
);

CREATE TYPE type_air AS (         -- qualité de l'air : un tout à 3 composantes
    pm25 numeric(8,2),
    pm10 numeric(8,2),
    no2  numeric(8,2)
);

CREATE TYPE type_hydro AS (       -- hydrométrie (variante A)
    humidite numeric(6,2),          -- humidité relative, %
    pluie    numeric(8,2)           -- pluie tombée depuis la mesure précédente, mm
);

-- ---------------------------------------------------------------------
-- 2. Stations
-- ---------------------------------------------------------------------
CREATE TABLE station (
    code      varchar(8)  PRIMARY KEY,          -- ex. BJ-01
    nom       varchar(60) NOT NULL,
    wilaya    varchar(40) NOT NULL,
    zone      smallint    NOT NULL CHECK (zone IN (1, 2)),
    pos       type_position    NOT NULL,
    -- la base refuse une position incohérente, dès l'insertion
    CONSTRAINT position_valide CHECK (
        (pos).latitude  BETWEEN -90  AND 90   AND
        (pos).longitude BETWEEN -180 AND 180  AND
        (pos).altitude  BETWEEN -500 AND 9000
    )
);

-- ---------------------------------------------------------------------
-- 3. Hiérarchie de capteurs (héritage)
-- ---------------------------------------------------------------------
CREATE TABLE capteur (                          -- informations communes à tous
    code           varchar(12) PRIMARY KEY,     -- ex. BJ-01-T1
    station_code   varchar(8)  NOT NULL REFERENCES station(code),
    type           varchar(20) NOT NULL
                   CHECK (type IN ('temperature','air','hydro')),
    mise_en_service date       NOT NULL,
    retrait        date,                        -- NULL = toujours en service
    etat           varchar(20) NOT NULL
                   CHECK (etat IN ('actif','hors_service','defaillant','retire')),
    CONSTRAINT dates_coherentes CHECK (retrait IS NULL OR retrait >= mise_en_service)
);

CREATE TABLE capteur_temperature () INHERITS (capteur);
CREATE TABLE capteur_air         () INHERITS (capteur);
CREATE TABLE capteur_hydro       () INHERITS (capteur);

-- chaque fils ne contient que son propre type (cohérence de la hiérarchie)
ALTER TABLE capteur_temperature ADD CONSTRAINT type_ok CHECK (type = 'temperature');
ALTER TABLE capteur_air         ADD CONSTRAINT type_ok CHECK (type = 'air');
ALTER TABLE capteur_hydro       ADD CONSTRAINT type_ok CHECK (type = 'hydro');

-- ---------------------------------------------------------------------
-- 4. Seuils d'alerte (référentiel)
-- ---------------------------------------------------------------------
CREATE TABLE seuil (
    id           serial PRIMARY KEY,
    type_capteur varchar(20) NOT NULL
                 CHECK (type_capteur IN ('temperature','air','hydro')),
    grandeur     varchar(20) NOT NULL,          -- temperature, pm25, pm10, no2, humidite, pluie
    borne        varchar(3)  NOT NULL CHECK (borne IN ('min','max')),
    valeur       numeric(10,2) NOT NULL,
    unite        varchar(10) NOT NULL
);

-- ---------------------------------------------------------------------
-- 5. Hiérarchie de mesures + protection par CHECK
--    Une mesure ne peut concerner qu'un capteur existant (FK vers la
--    table MERE : tout niveau de la hiérarchie est accepté), et chaque
--    fils refuse les valeurs physiquement impossibles.
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_mesure START 1;

CREATE TABLE mesure (
    id            bigint    PRIMARY KEY DEFAULT nextval('seq_mesure'),
    capteur_code  varchar(12) NOT NULL REFERENCES capteur(code),  -- mère de la hiérarchie
    instant       timestamp NOT NULL
);

CREATE TABLE mesure_temperature (
    valeur numeric(6,2),
    CONSTRAINT temperature_physique CHECK (valeur BETWEEN -60 AND 60)   -- °C
) INHERITS (mesure);

CREATE TABLE mesure_air (
    air type_air,
    CONSTRAINT air_physique CHECK (
        (air).pm25 IS NOT NULL AND (air).pm10 IS NOT NULL AND (air).no2 IS NOT NULL
        AND (air).pm25 >= 0 AND (air).pm25 <= 500
        AND (air).pm10 >= 0 AND (air).pm10 <= 1000
        AND (air).no2  >= 0 AND (air).no2  <= 1000
    )
) INHERITS (mesure);

CREATE TABLE mesure_hydro (
    hydro type_hydro,
    CONSTRAINT hydro_physique CHECK (          -- variante A : humidité 0..100 %
        (hydro).humidite IS NOT NULL AND (hydro).pluie IS NOT NULL
        AND (hydro).humidite BETWEEN 0 AND 100
        AND (hydro).pluie    BETWEEN 0 AND 1000
    )
) INHERITS (mesure);

-- Cohérence croisée : une mesure typée doit porter sur un capteur de même type.
CREATE OR REPLACE FUNCTION verif_type_capteur() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM capteur c
                   WHERE c.code = NEW.capteur_code
                     AND c.type = CASE TG_TABLE_NAME
                                    WHEN 'mesure_temperature' THEN 'temperature'
                                    WHEN 'mesure_air'         THEN 'air'
                                    WHEN 'mesure_hydro'       THEN 'hydro'
                                  END) THEN
        RAISE EXCEPTION 'Le capteur % n''est pas de type %', NEW.capteur_code, TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_type_temperature BEFORE INSERT ON mesure_temperature
    FOR EACH ROW EXECUTE FUNCTION verif_type_capteur();
CREATE TRIGGER trg_type_air BEFORE INSERT ON mesure_air
    FOR EACH ROW EXECUTE FUNCTION verif_type_capteur();
CREATE TRIGGER trg_type_hydro BEFORE INSERT ON mesure_hydro
    FOR EACH ROW EXECUTE FUNCTION verif_type_capteur();

-- ---------------------------------------------------------------------
-- 6. Espace d'isolement des mesures corrompues (étape 2)
--    conserve la forme d'origine, le lot et le motif du rejet.
-- ---------------------------------------------------------------------
CREATE TABLE lot_brut (
    id       bigint PRIMARY KEY,
    station  varchar(8)  NOT NULL,
    envoi    timestamp   NOT NULL,
    contenu  xml         NOT NULL      -- lot XML brut, interrogeable tel quel
);

CREATE TABLE mesure_isolee (
    id           bigint PRIMARY KEY,
    lot_id       bigint    NOT NULL REFERENCES lot_brut(id),
    capteur_txt  varchar(12),
    instant_txt  varchar(40),
    motif        varchar(20) NOT NULL CHECK (motif IN (
                     'valeur_impossible','valeur_manquante',
                     'format_invalide','capteur_inconnu','doublon')),
    xml_original xml NOT NULL          -- la mesure telle que reçue
);

CREATE SEQUENCE seq_isole START 1;

-- ---------------------------------------------------------------------
-- 7. Opérations définies dans la base
-- ---------------------------------------------------------------------
-- Distance en kilomètres entre deux positions (formule de Haversine)
CREATE OR REPLACE FUNCTION distance_km(p1 type_position, p2 type_position) RETURNS numeric AS $$
    SELECT round(6371 * acos(
             least(1, greatest(-1,
               sin(radians((p1).latitude)) * sin(radians((p2).latitude))
             + cos(radians((p1).latitude)) * cos(radians((p2).latitude))
             * cos(radians((p2).longitude - (p1).longitude))))
           )::numeric, 3)
$$ LANGUAGE sql IMMUTABLE;

-- TRUE si la valeur dépasse un seuil du référentiel pour ce capteur/grandeur
CREATE OR REPLACE FUNCTION depasse_seuil(p_capteur varchar, p_grandeur varchar,
                                         p_valeur numeric) RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1
        FROM seuil s JOIN capteur c ON c.type = s.type_capteur
        WHERE c.code = p_capteur
          AND s.grandeur = p_grandeur
          AND ((s.borne = 'max' AND p_valeur > s.valeur)
            OR (s.borne = 'min' AND p_valeur < s.valeur))
    )
$$ LANGUAGE sql STABLE;

-- Conversion d'unité (variante A : °C -> °F ; bonus : mm -> cm de pluie)
CREATE OR REPLACE FUNCTION celsius_vers_fahrenheit(t numeric) RETURNS numeric AS $$
    SELECT round((t * 9 / 5 + 32)::numeric, 2)
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION mm_vers_cm(mm numeric) RETURNS numeric AS $$
    SELECT round((mm / 10)::numeric, 2)
$$ LANGUAGE sql IMMUTABLE;

-- Vue aplatie des mesures (toute la hiérarchie, une grandeur par ligne)
CREATE VIEW vue_mesure_plat AS
SELECT m.id, m.capteur_code, c.station_code, c.type AS type_capteur,
       m.instant, 'temperature' AS grandeur, mt.valeur
FROM mesure m
JOIN capteur c ON c.code = m.capteur_code
JOIN mesure_temperature mt ON mt.id = m.id
UNION ALL
SELECT m.id, m.capteur_code, c.station_code, c.type, m.instant, 'pm25',  (ma.air).pm25
FROM mesure m JOIN capteur c ON c.code = m.capteur_code
JOIN mesure_air ma ON ma.id = m.id
UNION ALL
SELECT m.id, m.capteur_code, c.station_code, c.type, m.instant, 'pm10',  (ma.air).pm10
FROM mesure m JOIN capteur c ON c.code = m.capteur_code
JOIN mesure_air ma ON ma.id = m.id
UNION ALL
SELECT m.id, m.capteur_code, c.station_code, c.type, m.instant, 'no2',   (ma.air).no2
FROM mesure m JOIN capteur c ON c.code = m.capteur_code
JOIN mesure_air ma ON ma.id = m.id
UNION ALL
SELECT m.id, m.capteur_code, c.station_code, c.type, m.instant, 'humidite', (mh.hydro).humidite
FROM mesure m JOIN capteur c ON c.code = m.capteur_code
JOIN mesure_hydro mh ON mh.id = m.id
UNION ALL
SELECT m.id, m.capteur_code, c.station_code, c.type, m.instant, 'pluie',    (mh.hydro).pluie
FROM mesure m JOIN capteur c ON c.code = m.capteur_code
JOIN mesure_hydro mh ON mh.id = m.id;
