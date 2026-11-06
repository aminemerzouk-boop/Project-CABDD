-- =====================================================================
-- 05_distribution_centre.sql  --  ETAPE 3 : distribution (base 'centre')
-- psql -d centre -v ON_ERROR_STOP=1 \
--   -v z1_host=zone1 -v z2_host=zone2 -v pg_user=postgres -v pg_pass=postgres \
--   -f sql/05_distribution_centre.sql
--
-- Met en place postgres_fdw vers zone1/zone2, migre les mesures vers les
-- zones, remplace la table locale 'mesure' par une vue transparente sur
-- tout le réseau, et installe la propagation automatique du référentiel.
-- =====================================================================

-- (ré)exécution propre : on démonte d'abord un éventuel ancien montage
DROP VIEW  IF EXISTS mesure_reseau CASCADE;
-- (les anciennes tables mesure sont supprimées plus bas, APRÈS la migration)
DO $$ BEGIN
    -- on ne démonte 'mesure' que si c'est une VUE (cas d'une réexécution de l'étape 3) ;
    -- en exécution fraîche c'est encore la table de l'étape 2, source de la migration
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'mesure' AND relkind = 'v') THEN
        EXECUTE 'DROP VIEW IF EXISTS mesure CASCADE';
    END IF;
END $$;
DROP TRIGGER IF EXISTS trg_station ON station;
DROP TRIGGER IF EXISTS trg_capteur ON capteur;
DROP TRIGGER IF EXISTS trg_seuil   ON seuil;
DROP FUNCTION IF EXISTS propager_station(), propager_capteur(), propager_seuil(), router_mesure();
DROP SCHEMA IF EXISTS z1 CASCADE;
DROP SCHEMA IF EXISTS z2 CASCADE;
DROP SERVER IF EXISTS srv_zone1 CASCADE;
DROP SERVER IF EXISTS srv_zone2 CASCADE;
DROP SEQUENCE IF EXISTS seq_mesure_centre;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Serveurs distants (un par zone)
CREATE SERVER srv_zone1 FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'z1_host', port :'z_port', dbname 'zone1');
CREATE SERVER srv_zone2 FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'z2_host', port :'z_port', dbname 'zone2');

CREATE USER MAPPING FOR :pg_user SERVER srv_zone1
    OPTIONS (user :'pg_user', password :'pg_pass');
CREATE USER MAPPING FOR :pg_user SERVER srv_zone2
    OPTIONS (user :'pg_user', password :'pg_pass');

-- Tables distantes (référentiel + mesures aplaties des zones)
CREATE SCHEMA IF NOT EXISTS z1;
CREATE SCHEMA IF NOT EXISTS z2;
IMPORT FOREIGN SCHEMA public LIMIT TO (station, capteur, seuil, mesure)
    FROM SERVER srv_zone1 INTO z1;
IMPORT FOREIGN SCHEMA public LIMIT TO (station, capteur, seuil, mesure)
    FROM SERVER srv_zone2 INTO z2;

-- ---------------------------------------------------------------------
-- 1. Synchronisation initiale du référentiel vers les deux zones
--    (ensuite, les triggers la maintiendront automatiquement à jour)
-- ---------------------------------------------------------------------
INSERT INTO z1.station SELECT code, nom, wilaya, zone, (pos).latitude, (pos).longitude, (pos).altitude FROM station;
INSERT INTO z2.station SELECT code, nom, wilaya, zone, (pos).latitude, (pos).longitude, (pos).altitude FROM station;
INSERT INTO z1.capteur SELECT code, station_code, type, mise_en_service, retrait, etat FROM capteur;
INSERT INTO z2.capteur SELECT code, station_code, type, mise_en_service, retrait, etat FROM capteur;
INSERT INTO z1.seuil (id, type_capteur, grandeur, borne, valeur, unite) SELECT id, type_capteur, grandeur, borne, valeur, unite FROM seuil;
INSERT INTO z2.seuil (id, type_capteur, grandeur, borne, valeur, unite) SELECT id, type_capteur, grandeur, borne, valeur, unite FROM seuil;

-- ---------------------------------------------------------------------
-- 2. Migration des mesures locales vers la bonne zone (partitionnées)
--    zone2 : on décale les id de +10^12 pour garantir l'unicité réseau
-- ---------------------------------------------------------------------
INSERT INTO z1.mesure (id, capteur_code, instant, grandeur, valeur)
SELECT v.id, v.capteur_code, v.instant, v.grandeur, v.valeur
FROM vue_mesure_plat v JOIN station st ON st.code = v.station_code
WHERE st.zone = 1;

INSERT INTO z2.mesure (id, capteur_code, instant, grandeur, valeur)
SELECT v.id + 1000000000000, v.capteur_code, v.instant, v.grandeur, v.valeur
FROM vue_mesure_plat v JOIN station st ON st.code = v.station_code
WHERE st.zone = 2;

-- ---------------------------------------------------------------------
-- 3. Le centre ne stocke plus aucune mesure : 'mesure' devient une vue
--    transparente sur tout le réseau (comme si tout était local)
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS vue_mesure_plat;
DROP TABLE IF EXISTS mesure_temperature, mesure_air, mesure_hydro, mesure CASCADE;

CREATE VIEW mesure_reseau AS
    SELECT * FROM z1.mesure
    UNION ALL
    SELECT * FROM z2.mesure;

CREATE VIEW mesure AS SELECT * FROM mesure_reseau;

CREATE VIEW vue_mesure_plat AS
SELECT m.id, m.capteur_code, c.station_code, c.type AS type_capteur,
       m.instant, m.grandeur, m.valeur
FROM mesure m JOIN capteur c ON c.code = m.capteur_code;

-- ---------------------------------------------------------------------
-- 4. Transparence en écriture : une mesure insérée depuis le centre est
--    stockée physiquement dans la bonne zone, sans préciser laquelle.
--    L'identifiant est tiré d'une séquence propre au centre (+2x10^12),
--    donc unique sur tout le réseau.
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_mesure_centre START 1;

CREATE OR REPLACE FUNCTION router_mesure() RETURNS trigger AS $$
DECLARE
    v_zone smallint;
BEGIN
    IF NEW.id IS NULL THEN
        NEW.id := nextval('seq_mesure_centre') + 2000000000000;
    END IF;
    SELECT zone INTO v_zone FROM station WHERE code =
        (SELECT station_code FROM capteur WHERE code = NEW.capteur_code);
    IF v_zone = 1 THEN
        INSERT INTO z1.mesure VALUES (NEW.id, NEW.capteur_code, NEW.instant, NEW.grandeur, NEW.valeur);
    ELSIF v_zone = 2 THEN
        INSERT INTO z2.mesure VALUES (NEW.id, NEW.capteur_code, NEW.instant, NEW.grandeur, NEW.valeur);
    ELSE
        RAISE EXCEPTION 'Capteur % inconnu du référentiel', NEW.capteur_code;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_insert_mesure INSTEAD OF INSERT ON mesure
    FOR EACH ROW EXECUTE FUNCTION router_mesure();

-- ---------------------------------------------------------------------
-- 5. Propagation automatique du référentiel vers les deux zones
--    (ajout/modification/suppression d'une station, d'un capteur, d'un seuil)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION propager_station() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM z1.station WHERE code = OLD.code;
        DELETE FROM z2.station WHERE code = OLD.code;
        RETURN OLD;
    END IF;
    DELETE FROM z1.station WHERE code = NEW.code;
    DELETE FROM z2.station WHERE code = NEW.code;
    INSERT INTO z1.station VALUES (NEW.code, NEW.nom, NEW.wilaya, NEW.zone,
                                  (NEW.pos).latitude, (NEW.pos).longitude, (NEW.pos).altitude);
    INSERT INTO z2.station VALUES (NEW.code, NEW.nom, NEW.wilaya, NEW.zone,
                                  (NEW.pos).latitude, (NEW.pos).longitude, (NEW.pos).altitude);
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION propager_capteur() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM z1.capteur WHERE code = OLD.code;
        DELETE FROM z2.capteur WHERE code = OLD.code;
        RETURN OLD;
    END IF;
    DELETE FROM z1.capteur WHERE code = NEW.code;
    DELETE FROM z2.capteur WHERE code = NEW.code;
    INSERT INTO z1.capteur VALUES (NEW.code, NEW.station_code, NEW.type, NEW.mise_en_service, NEW.retrait, NEW.etat);
    INSERT INTO z2.capteur VALUES (NEW.code, NEW.station_code, NEW.type, NEW.mise_en_service, NEW.retrait, NEW.etat);
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION propager_seuil() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM z1.seuil WHERE id = OLD.id;
        DELETE FROM z2.seuil WHERE id = OLD.id;
        RETURN OLD;
    END IF;
    DELETE FROM z1.seuil WHERE id = NEW.id;
    DELETE FROM z2.seuil WHERE id = NEW.id;
    INSERT INTO z1.seuil (id, type_capteur, grandeur, borne, valeur, unite)
        VALUES (NEW.id, NEW.type_capteur, NEW.grandeur, NEW.borne, NEW.valeur, NEW.unite);
    INSERT INTO z2.seuil (id, type_capteur, grandeur, borne, valeur, unite)
        VALUES (NEW.id, NEW.type_capteur, NEW.grandeur, NEW.borne, NEW.valeur, NEW.unite);
    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- NB : les triggers sont hérités par les tables filles de 'capteur'
CREATE TRIGGER trg_station  AFTER INSERT OR UPDATE OR DELETE ON station
    FOR EACH ROW EXECUTE FUNCTION propager_station();
CREATE TRIGGER trg_capteur  AFTER INSERT OR UPDATE OR DELETE ON capteur
    FOR EACH ROW EXECUTE FUNCTION propager_capteur();
CREATE TRIGGER trg_seuil    AFTER INSERT OR UPDATE OR DELETE ON seuil
    FOR EACH ROW EXECUTE FUNCTION propager_seuil();

-- ---------------------------------------------------------------------
-- 6. Contrôles
-- ---------------------------------------------------------------------
SELECT 'mesures zone1' AS vue, count(*) FROM z1.mesure
UNION ALL SELECT 'mesures zone2', count(*) FROM z2.mesure
UNION ALL SELECT 'mesures vues du centre (transparence)', count(*) FROM mesure
UNION ALL SELECT 'stations zone1', count(*) FROM z1.station
UNION ALL SELECT 'stations zone2', count(*) FROM z2.station;
