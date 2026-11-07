-- =====================================================================
-- 05b_zone.sql  --  ETAPE 3 : schéma d'une base ZONE (zone1 ou zone2)
-- psql -d zone1 -v zone_num=1 -v zone_offset=0          -f sql/05b_zone.sql
-- psql -d zone2 -v zone_num=2 -v zone_offset=1000000000000 -f sql/05b_zone.sql
-- (le centre, lui, insère avec un offset de 2000000000000 : identifiants
--  uniques sur tout le réseau même si deux zones créent des mesures seules)
--
-- La zone stocke SES mesures uniquement, organisées par MOIS (variante A),
-- et une COPIE locale du référentiel pour contrôler ses mesures seule.
-- Les identifiants sont uniques sur tout le réseau grâce à l'offset de zone.
-- =====================================================================

-- Copie locale du référentiel (structure aplatie, même contenu que centre)
CREATE TABLE station (
    code varchar(8) PRIMARY KEY, nom varchar(60) NOT NULL, wilaya varchar(40) NOT NULL,
    zone smallint NOT NULL CHECK (zone IN (1,2)),
    latitude numeric(9,6), longitude numeric(9,6), altitude numeric(8,2)
);
CREATE TABLE capteur (
    code varchar(12) PRIMARY KEY, station_code varchar(8) NOT NULL REFERENCES station(code),
    type varchar(20) NOT NULL CHECK (type IN ('temperature','air','hydro')),
    mise_en_service date NOT NULL, retrait date, etat varchar(20)
);
CREATE TABLE seuil (
    id serial PRIMARY KEY, type_capteur varchar(20) NOT NULL, grandeur varchar(20) NOT NULL,
    borne varchar(3) NOT NULL CHECK (borne IN ('min','max')),
    valeur numeric(10,2) NOT NULL, unite varchar(10) NOT NULL
);

-- Mesures de la zone, aplaties (grandeur/valeur) et partitionnées PAR MOIS
CREATE SEQUENCE seq_mesure_local START 1000000000;   -- large plage libre sous l'offset

CREATE TABLE mesure (
    id            bigint NOT NULL
                  DEFAULT nextval('seq_mesure_local') + :zone_offset,
    capteur_code  varchar(12) NOT NULL REFERENCES capteur(code),
    instant       timestamp   NOT NULL,
    grandeur      varchar(20) NOT NULL
                  CHECK (grandeur IN ('temperature','pm25','pm10','no2','humidite','pluie')),
    valeur        numeric(10,2) NOT NULL,
    PRIMARY KEY (id, instant, grandeur),
    -- mêmes bornes physiques que le centre : la zone se protège aussi seule
    CONSTRAINT valeur_physique CHECK (
        (grandeur = 'temperature' AND valeur BETWEEN -60 AND 60)
     OR (grandeur IN ('pm25')     AND valeur BETWEEN 0 AND 500)
     OR (grandeur IN ('pm10','no2') AND valeur BETWEEN 0 AND 1000)
     OR (grandeur = 'humidite'    AND valeur BETWEEN 0 AND 100)
     OR (grandeur = 'pluie'       AND valeur BETWEEN 0 AND 1000))
) PARTITION BY RANGE (instant);

-- Partitionnement temporel mensuel (variante A)
CREATE TABLE mesure_2026_01 PARTITION OF mesure FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE mesure_2026_02 PARTITION OF mesure FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE mesure_2026_03 PARTITION OF mesure FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE mesure_2026_04 PARTITION OF mesure FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE mesure_2026_05 PARTITION OF mesure FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE mesure_defaut  PARTITION OF mesure DEFAULT;

CREATE INDEX ON mesure (capteur_code, instant);
