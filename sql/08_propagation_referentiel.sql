-- ============================================================================
-- Script 08 : Unicité Globale des IDs & Propagation du Référentiel (Étape 3)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Merzouk Amine
-- Prérequis : sql/07_zones_partitions.sql exécuté (bases zone1 et zone2 prêtes)
-- ============================================================================

-- Paramètres de connexion FDW avec valeurs par défaut automatiques
\if :{?pg_host}
\else
    \set pg_host '127.0.0.1'
\endif
\if :{?pg_port}
\else
    SELECT current_setting('port') AS pg_port \gset
\endif
\if :{?pg_user}
\else
    SELECT current_user AS pg_user \gset
\endif
\if :{?pg_pass}
\else
    \set pg_pass 'postgresql'
\endif

-- ============================================================================
-- 1. Garantie d'identifiants de mesures uniques sur tout le réseau
--    - zone1 : identifiants IMPAIRS (1, 3, 5, ...)
--    - zone2 : identifiants PAIRS   (2, 4, 6, ...)
--    Aucune collision possible même en création autonome dans chaque zone.
-- ============================================================================

\connect zone1
CREATE SEQUENCE IF NOT EXISTS seq_mesure INCREMENT BY 2 START WITH 1;

\connect zone2
CREATE SEQUENCE IF NOT EXISTS seq_mesure INCREMENT BY 2 START WITH 2;

-- ============================================================================
-- 2. Configuration de postgres_fdw sur « centre » vers « zone1 » et « zone2 »
-- ============================================================================

\connect centre
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Nettoyage idempotent des anciens triggers/schémas distants si réexécution
DROP TRIGGER IF EXISTS trg_propager_station      ON station;
DROP TRIGGER IF EXISTS trg_propager_capteur_mere ON capteur;
DROP TRIGGER IF EXISTS trg_propager_capteur_temp ON capteur_temperature;
DROP TRIGGER IF EXISTS trg_propager_capteur_air  ON capteur_air;
DROP TRIGGER IF EXISTS trg_propager_capteur_hyd  ON capteur_hydro;
DROP TRIGGER IF EXISTS trg_propager_seuil        ON seuil_alerte;

DROP SCHEMA IF EXISTS z1_ref CASCADE;
DROP SCHEMA IF EXISTS z2_ref CASCADE;
DROP SERVER IF EXISTS srv_zone1 CASCADE;
DROP SERVER IF EXISTS srv_zone2 CASCADE;

-- Déclaration des deux serveurs distants (use_remote_estimate activé pour EXPLAIN)
CREATE SERVER srv_zone1
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'pg_host', port :'pg_port', dbname 'zone1', use_remote_estimate 'true');

CREATE SERVER srv_zone2
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'pg_host', port :'pg_port', dbname 'zone2', use_remote_estimate 'true');

CREATE USER MAPPING FOR CURRENT_USER
    SERVER srv_zone1
    OPTIONS (user :'pg_user', password :'pg_pass');

CREATE USER MAPPING FOR CURRENT_USER
    SERVER srv_zone2
    OPTIONS (user :'pg_user', password :'pg_pass');

-- Import des tables du référentiel distant dans deux schémas dédiés z1_ref et z2_ref
CREATE SCHEMA z1_ref;
CREATE SCHEMA z2_ref;

IMPORT FOREIGN SCHEMA public
    LIMIT TO (station, capteur, capteur_temperature, capteur_air, capteur_hydro, seuil_alerte)
    FROM SERVER srv_zone1 INTO z1_ref;

IMPORT FOREIGN SCHEMA public
    LIMIT TO (station, capteur, capteur_temperature, capteur_air, capteur_hydro, seuil_alerte)
    FROM SERVER srv_zone2 INTO z2_ref;

-- ============================================================================
-- 3. Fonctions d'écriture distante sans perte d'intégrité référentielle
--    (UPDATE en place puis INSERT si absent : compatible postgres_fdw et ne
--     casse jamais les clés étrangères des mesures déjà stockées en zone)
-- ============================================================================

CREATE OR REPLACE PROCEDURE sync_station_vers_zone(
    p_schema       TEXT,
    p_old_code     VARCHAR,
    p_code_station VARCHAR,
    p_nom          VARCHAR,
    p_wilaya       VARCHAR,
    p_zone         SMALLINT,
    p_position     t_position
) AS $$
DECLARE
    v_rows INT;
BEGIN
    EXECUTE format(
        'UPDATE %I.station
            SET code_station = $1, nom = $2, wilaya = $3, zone = $4, position = $5
          WHERE code_station = $6',
        p_schema
    ) USING p_code_station, p_nom, p_wilaya, p_zone, p_position, coalesce(p_old_code, p_code_station);

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        EXECUTE format(
            'INSERT INTO %I.station (code_station, nom, wilaya, zone, position)
             VALUES ($1, $2, $3, $4, $5)',
            p_schema
        ) USING p_code_station, p_nom, p_wilaya, p_zone, p_position;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sync_capteur_vers_zone(
    p_schema        TEXT,
    p_old_code      VARCHAR,
    p_code_capteur  VARCHAR,
    p_code_station  VARCHAR,
    p_type_capteur  type_capteur_enum,
    p_mise_service  DATE,
    p_date_retrait  DATE,
    p_etat          VARCHAR
) AS $$
DECLARE
    v_cible TEXT;
    v_rows  INT;
BEGIN
    -- Cible la sous-table fille si la hiérarchie existe dans la zone, sinon capteur
    v_cible := CASE p_type_capteur
        WHEN 'temperature' THEN 'capteur_temperature'
        WHEN 'air'         THEN 'capteur_air'
        WHEN 'hydro'       THEN 'capteur_hydro'
    END;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = p_schema AND table_name = v_cible
    ) THEN
        v_cible := 'capteur';
    END IF;

    EXECUTE format(
        'UPDATE %I.%I
            SET code_capteur = $1, code_station = $2, type_capteur = $3,
                date_mise_en_service = $4, date_retrait = $5, etat = $6
          WHERE code_capteur = $7',
        p_schema, v_cible
    ) USING p_code_capteur, p_code_station, p_type_capteur,
            p_mise_service, p_date_retrait, p_etat, coalesce(p_old_code, p_code_capteur);

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        EXECUTE format(
            'INSERT INTO %I.%I (code_capteur, code_station, type_capteur,
                                date_mise_en_service, date_retrait, etat)
             VALUES ($1, $2, $3, $4, $5, $6)',
            p_schema, v_cible
        ) USING p_code_capteur, p_code_station, p_type_capteur,
                p_mise_service, p_date_retrait, p_etat;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sync_seuil_vers_zone(
    p_schema       TEXT,
    p_old_id       INT,
    p_id_seuil     INT,
    p_type_capteur type_capteur_enum,
    p_grandeur     VARCHAR,
    p_borne        borne_seuil_enum,
    p_valeur       NUMERIC,
    p_unite        VARCHAR
) AS $$
DECLARE
    v_rows INT;
BEGIN
    EXECUTE format(
        'UPDATE %I.seuil_alerte
            SET id_seuil = $1, type_capteur = $2, grandeur = $3,
                borne = $4, valeur = $5, unite = $6
          WHERE id_seuil = $7',
        p_schema
    ) USING p_id_seuil, p_type_capteur, p_grandeur,
            p_borne, p_valeur, p_unite, coalesce(p_old_id, p_id_seuil);

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        EXECUTE format(
            'INSERT INTO %I.seuil_alerte (id_seuil, type_capteur, grandeur, borne, valeur, unite)
             VALUES ($1, $2, $3, $4, $5, $6)',
            p_schema
        ) USING p_id_seuil, p_type_capteur, p_grandeur, p_borne, p_valeur, p_unite;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. Synchronisation initiale complète du référentiel de centre -> zone1 & zone2
-- ============================================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM station ORDER BY code_station LOOP
        CALL sync_station_vers_zone('z1_ref', r.code_station, r.code_station, r.nom, r.wilaya, r.zone, r.position);
        CALL sync_station_vers_zone('z2_ref', r.code_station, r.code_station, r.nom, r.wilaya, r.zone, r.position);
    END LOOP;

    FOR r IN SELECT * FROM capteur ORDER BY code_capteur LOOP
        CALL sync_capteur_vers_zone('z1_ref', r.code_capteur, r.code_capteur, r.code_station,
                                    r.type_capteur, r.date_mise_en_service, r.date_retrait, r.etat);
        CALL sync_capteur_vers_zone('z2_ref', r.code_capteur, r.code_capteur, r.code_station,
                                    r.type_capteur, r.date_mise_en_service, r.date_retrait, r.etat);
    END LOOP;

    FOR r IN SELECT * FROM seuil_alerte ORDER BY id_seuil LOOP
        CALL sync_seuil_vers_zone('z1_ref', r.id_seuil, r.id_seuil, r.type_capteur,
                                  r.grandeur, r.borne, r.valeur, r.unite);
        CALL sync_seuil_vers_zone('z2_ref', r.id_seuil, r.id_seuil, r.type_capteur,
                                  r.grandeur, r.borne, r.valeur, r.unite);
    END LOOP;
END;
$$;

-- ============================================================================
-- 5. Triggers de propagation automatique (station, hiérarchie capteur*, seuils)
--    IMPORTANT : Sous PostgreSQL, les triggers ne sont PAS hérités via INHERITS,
--    on attache donc explicitement le trigger sur chaque sous-table de capteur !
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_propager_station()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM z1_ref.station WHERE code_station = OLD.code_station;
        DELETE FROM z2_ref.station WHERE code_station = OLD.code_station;
        RETURN OLD;
    END IF;

    CALL sync_station_vers_zone(
        'z1_ref',
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.code_station ELSE NULL END,
        NEW.code_station, NEW.nom, NEW.wilaya, NEW.zone, NEW.position
    );
    CALL sync_station_vers_zone(
        'z2_ref',
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.code_station ELSE NULL END,
        NEW.code_station, NEW.nom, NEW.wilaya, NEW.zone, NEW.position
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_propager_capteur()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM z1_ref.capteur WHERE code_capteur = OLD.code_capteur;
        DELETE FROM z2_ref.capteur WHERE code_capteur = OLD.code_capteur;
        RETURN OLD;
    END IF;

    CALL sync_capteur_vers_zone(
        'z1_ref',
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.code_capteur ELSE NULL END,
        NEW.code_capteur, NEW.code_station, NEW.type_capteur,
        NEW.date_mise_en_service, NEW.date_retrait, NEW.etat
    );
    CALL sync_capteur_vers_zone(
        'z2_ref',
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.code_capteur ELSE NULL END,
        NEW.code_capteur, NEW.code_station, NEW.type_capteur,
        NEW.date_mise_en_service, NEW.date_retrait, NEW.etat
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_propager_seuil()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM z1_ref.seuil_alerte WHERE id_seuil = OLD.id_seuil;
        DELETE FROM z2_ref.seuil_alerte WHERE id_seuil = OLD.id_seuil;
        RETURN OLD;
    END IF;

    CALL sync_seuil_vers_zone(
        'z1_ref',
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.id_seuil ELSE NULL END,
        NEW.id_seuil, NEW.type_capteur, NEW.grandeur, NEW.borne, NEW.valeur, NEW.unite
    );
    CALL sync_seuil_vers_zone(
        'z2_ref',
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.id_seuil ELSE NULL END,
        NEW.id_seuil, NEW.type_capteur, NEW.grandeur, NEW.borne, NEW.valeur, NEW.unite
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_propager_station
    AFTER INSERT OR UPDATE OR DELETE ON station
    FOR EACH ROW EXECUTE FUNCTION fn_propager_station();

CREATE TRIGGER trg_propager_capteur_mere
    AFTER INSERT OR UPDATE OR DELETE ON capteur
    FOR EACH ROW EXECUTE FUNCTION fn_propager_capteur();

CREATE TRIGGER trg_propager_capteur_temp
    AFTER INSERT OR UPDATE OR DELETE ON capteur_temperature
    FOR EACH ROW EXECUTE FUNCTION fn_propager_capteur();

CREATE TRIGGER trg_propager_capteur_air
    AFTER INSERT OR UPDATE OR DELETE ON capteur_air
    FOR EACH ROW EXECUTE FUNCTION fn_propager_capteur();

CREATE TRIGGER trg_propager_capteur_hyd
    AFTER INSERT OR UPDATE OR DELETE ON capteur_hydro
    FOR EACH ROW EXECUTE FUNCTION fn_propager_capteur();

CREATE TRIGGER trg_propager_seuil
    AFTER INSERT OR UPDATE OR DELETE ON seuil_alerte
    FOR EACH ROW EXECUTE FUNCTION fn_propager_seuil();

-- ============================================================================
-- 6. Contrôle de synchronisation du référentiel sur les 3 bases
-- ============================================================================
SELECT 'centre' AS base,
       (SELECT count(*) FROM station)      AS nb_stations,
       (SELECT count(*) FROM capteur)      AS nb_capteurs,
       (SELECT count(*) FROM seuil_alerte) AS nb_seuils
UNION ALL
SELECT 'zone1',
       (SELECT count(*) FROM z1_ref.station),
       (SELECT count(*) FROM z1_ref.capteur),
       (SELECT count(*) FROM z1_ref.seuil_alerte)
UNION ALL
SELECT 'zone2',
       (SELECT count(*) FROM z2_ref.station),
       (SELECT count(*) FROM z2_ref.capteur),
       (SELECT count(*) FROM z2_ref.seuil_alerte);
