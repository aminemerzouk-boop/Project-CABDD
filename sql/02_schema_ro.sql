-- ============================================================================
-- Script 02 : Schéma Relationnel-Objet du Centre National (Étape 1)
-- Mini-projet CABDD (ING 4 GL) — Variante A
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Merzouk Amine
-- Base cible : centre
-- ============================================================================

\connect centre

-- Nettoyage idempotent en cas de réexécution isolée du script 02
DROP TABLE IF EXISTS mesure_temperature, mesure_air, mesure_hydro, mesure CASCADE;
DROP TABLE IF EXISTS mesure_isolee, lot_brut CASCADE;
DROP TABLE IF EXISTS capteur_temperature, capteur_air, capteur_hydro, capteur CASCADE;
DROP TABLE IF EXISTS seuil_alerte, station CASCADE;
DROP SEQUENCE IF EXISTS seq_mesure CASCADE;
DROP TYPE IF EXISTS t_hydrometrie, t_qualite_air, t_position CASCADE;
DROP TYPE IF EXISTS motif_rejet_enum, borne_seuil_enum, type_capteur_enum CASCADE;

-- ============================================================================
-- 1. Énumérations métier
-- ============================================================================
CREATE TYPE type_capteur_enum AS ENUM (
    'temperature',
    'air',
    'hydro'
);

CREATE TYPE borne_seuil_enum AS ENUM (
    'min',
    'max'
);

CREATE TYPE motif_rejet_enum AS ENUM (
    'valeur_impossible',
    'valeur_manquante',
    'format_invalide',
    'capteur_inconnu',
    'doublon'
);

-- ============================================================================
-- 2. Types composés (Objets structurés manipulables d'un seul bloc)
-- ============================================================================
-- Position géographique 3D d'une station
CREATE TYPE t_position AS (
    latitude  NUMERIC(9,6),
    longitude NUMERIC(9,6),
    altitude  NUMERIC(8,2)
);

-- Observation multi-composantes de qualité de l'air (µg/m3)
CREATE TYPE t_qualite_air AS (
    pm25 NUMERIC(8,2),
    pm10 NUMERIC(8,2),
    no2  NUMERIC(8,2)
);

-- Observation hydrométrique spécifique à la Variante A (% et mm/3h)
CREATE TYPE t_hydrometrie AS (
    humidite NUMERIC(6,2),
    pluie    NUMERIC(8,2)
);

-- ============================================================================
-- 3. Référentiel du réseau : Stations, Hiérarchie de Capteurs et Seuils
-- ============================================================================

-- 3.1 Table des stations (12 stations réparties en 2 zones)
CREATE TABLE station (
    code_station VARCHAR(10)  PRIMARY KEY,
    nom          VARCHAR(100) NOT NULL,
    wilaya       VARCHAR(60)  NOT NULL,
    zone         SMALLINT     NOT NULL CHECK (zone IN (1, 2)),
    position     t_position   NOT NULL,
    CONSTRAINT chk_station_position CHECK (
        (position).latitude  IS NOT NULL AND
        (position).longitude IS NOT NULL AND
        (position).altitude  IS NOT NULL AND
        (position).latitude  BETWEEN -90  AND 90  AND
        (position).longitude BETWEEN -180 AND 180 AND
        (position).altitude  BETWEEN -500 AND 9000
    )
);

-- 3.2 Hiérarchie de capteurs (généralisation par INHERITS)
--     Interroger SELECT * FROM capteur restitue tous les capteurs du réseau.
CREATE TABLE capteur (
    code_capteur         VARCHAR(15)       PRIMARY KEY,
    code_station         VARCHAR(10)       NOT NULL REFERENCES station(code_station),
    type_capteur         type_capteur_enum NOT NULL,
    date_mise_en_service DATE              NOT NULL,
    date_retrait         DATE,
    etat                 VARCHAR(30)       NOT NULL,
    CONSTRAINT chk_capteur_dates CHECK (
        date_retrait IS NULL OR date_retrait >= date_mise_en_service
    ),
    CONSTRAINT chk_capteur_etat CHECK (
        etat IN ('actif', 'hors_service', 'maintenance', 'retire', 'defaillant')
    )
);

-- Sous-table des capteurs de température (ajoute ses attributs métrologiques propres)
CREATE TABLE capteur_temperature (
    unite_mesure VARCHAR(10)  NOT NULL DEFAULT '°C',
    plage_min    NUMERIC(5,2) NOT NULL DEFAULT -60.00,
    plage_max    NUMERIC(5,2) NOT NULL DEFAULT 60.00,
    PRIMARY KEY (code_capteur),
    FOREIGN KEY (code_station) REFERENCES station(code_station),
    CONSTRAINT chk_type_temperature CHECK (type_capteur = 'temperature')
) INHERITS (capteur);

-- Sous-table des capteurs de qualité de l'air
CREATE TABLE capteur_air (
    polluants_suivis    VARCHAR(40) NOT NULL DEFAULT 'PM2.5,PM10,NO2',
    unite_concentration VARCHAR(10) NOT NULL DEFAULT 'µg/m3',
    PRIMARY KEY (code_capteur),
    FOREIGN KEY (code_station) REFERENCES station(code_station),
    CONSTRAINT chk_type_air CHECK (type_capteur = 'air')
) INHERITS (capteur);

-- Sous-table des capteurs hydrométriques (spécifique Variante A)
CREATE TABLE capteur_hydro (
    unite_humidite   VARCHAR(5)  NOT NULL DEFAULT '%',
    unite_pluie      VARCHAR(10) NOT NULL DEFAULT 'mm',
    pas_cumul_heures SMALLINT    NOT NULL DEFAULT 3,
    PRIMARY KEY (code_capteur),
    FOREIGN KEY (code_station) REFERENCES station(code_station),
    CONSTRAINT chk_type_hydro CHECK (type_capteur = 'hydro')
) INHERITS (capteur);

-- 3.3 Seuils d'alerte du référentiel
CREATE TABLE seuil_alerte (
    id_seuil     SERIAL            PRIMARY KEY,
    type_capteur type_capteur_enum NOT NULL,
    grandeur     VARCHAR(30)       NOT NULL,
    borne        borne_seuil_enum  NOT NULL,
    valeur       NUMERIC(10,2)     NOT NULL,
    unite        VARCHAR(20)       NOT NULL,
    UNIQUE (type_capteur, grandeur, borne)
);

-- ============================================================================
-- 4. Lots Bruts XML, Espace d'Isolement et Hiérarchie de Mesures
-- ============================================================================

-- 4.1 Conservation intégrale des lots XML reçus
CREATE TABLE lot_brut (
    id_lot       BIGSERIAL   PRIMARY KEY,
    code_station VARCHAR(10) NOT NULL,
    date_envoi   TIMESTAMP   NOT NULL,
    contenu_xml  XML         NOT NULL
);

CREATE INDEX idx_lot_brut_station_envoi ON lot_brut (code_station, date_envoi);

-- 4.2 Espace d'isolement des mesures rejetées (forme XML d'origine + lot + motif)
CREATE TABLE mesure_isolee (
    id_rejet         BIGSERIAL        PRIMARY KEY,
    id_lot           BIGINT           NOT NULL REFERENCES lot_brut(id_lot) ON DELETE CASCADE,
    code_station_lot VARCHAR(15),
    code_capteur_txt TEXT,
    instant_txt      TEXT,
    mesure_xml       XML              NOT NULL,
    motif            motif_rejet_enum NOT NULL,
    detail_motif     TEXT,
    date_rejet       TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_mesure_isolee_motif ON mesure_isolee (motif);
CREATE INDEX idx_mesure_isolee_lot   ON mesure_isolee (id_lot);

-- 4.3 Hiérarchie des mesures valides (auto-protégées par CHECK)
CREATE SEQUENCE seq_mesure START WITH 1 INCREMENT BY 1;

CREATE TABLE mesure (
    id_mesure      BIGINT      PRIMARY KEY DEFAULT nextval('seq_mesure'),
    code_capteur   VARCHAR(15) NOT NULL,
    instant_mesure TIMESTAMP   NOT NULL,
    id_lot         BIGINT      REFERENCES lot_brut(id_lot),
    UNIQUE (code_capteur, instant_mesure)
);

CREATE TABLE mesure_temperature (
    temperature NUMERIC(6,2) NOT NULL,
    PRIMARY KEY (id_mesure),
    UNIQUE (code_capteur, instant_mesure),
    FOREIGN KEY (id_lot) REFERENCES lot_brut(id_lot),
    CONSTRAINT chk_temperature_physique CHECK (
        temperature BETWEEN -60 AND 60
    )
) INHERITS (mesure);

CREATE TABLE mesure_air (
    valeurs_air t_qualite_air NOT NULL,
    PRIMARY KEY (id_mesure),
    UNIQUE (code_capteur, instant_mesure),
    FOREIGN KEY (id_lot) REFERENCES lot_brut(id_lot),
    CONSTRAINT chk_air_physique CHECK (
        (valeurs_air).pm25 IS NOT NULL AND
        (valeurs_air).pm10 IS NOT NULL AND
        (valeurs_air).no2  IS NOT NULL AND
        (valeurs_air).pm25 BETWEEN 0 AND 500  AND
        (valeurs_air).pm10 BETWEEN 0 AND 1000 AND
        (valeurs_air).no2  BETWEEN 0 AND 1000
    )
) INHERITS (mesure);

CREATE TABLE mesure_hydro (
    valeurs_hydro t_hydrometrie NOT NULL,
    PRIMARY KEY (id_mesure),
    UNIQUE (code_capteur, instant_mesure),
    FOREIGN KEY (id_lot) REFERENCES lot_brut(id_lot),
    CONSTRAINT chk_hydro_physique CHECK (
        (valeurs_hydro).humidite IS NOT NULL AND
        (valeurs_hydro).pluie    IS NOT NULL AND
        (valeurs_hydro).humidite BETWEEN 0 AND 100 AND
        (valeurs_hydro).pluie    BETWEEN 0 AND 500
    )
) INHERITS (mesure);

CREATE INDEX idx_mesure_temp_instant  ON mesure_temperature (instant_mesure);
CREATE INDEX idx_mesure_air_instant   ON mesure_air         (instant_mesure);
CREATE INDEX idx_mesure_hydro_instant ON mesure_hydro       (instant_mesure);

-- ============================================================================
-- 5. Triggers PL/pgSQL verrouillant l'intégrité sur la hiérarchie INHERITS
--    (Sous PostgreSQL, PK/UNIQUE/FK ne se propagent pas entre tables INHERITS)
-- ============================================================================

-- 5.1 Unicité globale de code_capteur sur toute la hiérarchie capteur*
CREATE OR REPLACE FUNCTION fn_unicite_globale_capteur()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.code_capteur IS DISTINCT FROM OLD.code_capteur THEN
        IF EXISTS (SELECT 1 FROM capteur WHERE code_capteur = NEW.code_capteur) THEN
            RAISE EXCEPTION 'Le code capteur % existe deja dans la hierarchie capteur.', NEW.code_capteur
                USING ERRCODE = 'unique_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_unicite_capteur_mere
    BEFORE INSERT OR UPDATE OF code_capteur ON capteur
    FOR EACH ROW EXECUTE FUNCTION fn_unicite_globale_capteur();

CREATE TRIGGER trg_unicite_capteur_temp
    BEFORE INSERT OR UPDATE OF code_capteur ON capteur_temperature
    FOR EACH ROW EXECUTE FUNCTION fn_unicite_globale_capteur();

CREATE TRIGGER trg_unicite_capteur_air
    BEFORE INSERT OR UPDATE OF code_capteur ON capteur_air
    FOR EACH ROW EXECUTE FUNCTION fn_unicite_globale_capteur();

CREATE TRIGGER trg_unicite_capteur_hydro
    BEFORE INSERT OR UPDATE OF code_capteur ON capteur_hydro
    FOR EACH ROW EXECUTE FUNCTION fn_unicite_globale_capteur();

-- 5.2 Protection contre la suppression d'un capteur déjà référencé par des mesures
CREATE OR REPLACE FUNCTION fn_protection_suppression_capteur()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' OR NEW.code_capteur IS DISTINCT FROM OLD.code_capteur THEN
        IF EXISTS (SELECT 1 FROM mesure WHERE code_capteur = OLD.code_capteur) THEN
            RAISE EXCEPTION 'Suppression/renommage refuse : le capteur % possede des mesures enregistrees.', OLD.code_capteur
                USING ERRCODE = 'foreign_key_violation';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_no_del_capteur_mere
    BEFORE DELETE OR UPDATE OF code_capteur ON capteur
    FOR EACH ROW EXECUTE FUNCTION fn_protection_suppression_capteur();

CREATE TRIGGER trg_no_del_capteur_temp
    BEFORE DELETE OR UPDATE OF code_capteur ON capteur_temperature
    FOR EACH ROW EXECUTE FUNCTION fn_protection_suppression_capteur();

CREATE TRIGGER trg_no_del_capteur_air
    BEFORE DELETE OR UPDATE OF code_capteur ON capteur_air
    FOR EACH ROW EXECUTE FUNCTION fn_protection_suppression_capteur();

CREATE TRIGGER trg_no_del_capteur_hydro
    BEFORE DELETE OR UPDATE OF code_capteur ON capteur_hydro
    FOR EACH ROW EXECUTE FUNCTION fn_protection_suppression_capteur();

-- 5.3 Vérification d'existence et de cohérence de type du capteur lors d'une mesure
CREATE OR REPLACE FUNCTION fn_integrite_mesure_capteur()
RETURNS TRIGGER AS $$
DECLARE
    v_type type_capteur_enum;
BEGIN
    SELECT c.type_capteur INTO v_type
    FROM capteur c
    WHERE c.code_capteur = NEW.code_capteur;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mesure refusee : le capteur % est absent du referentiel.', NEW.code_capteur
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF (TG_TABLE_NAME = 'mesure_temperature' AND v_type <> 'temperature')
    OR (TG_TABLE_NAME = 'mesure_air'         AND v_type <> 'air')
    OR (TG_TABLE_NAME = 'mesure_hydro'       AND v_type <> 'hydro') THEN
        RAISE EXCEPTION 'Incoherence de type : le capteur % est de type %, incompatible avec la table %.',
            NEW.code_capteur, v_type, TG_TABLE_NAME
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_fk_mesure_mere
    BEFORE INSERT OR UPDATE OF code_capteur ON mesure
    FOR EACH ROW EXECUTE FUNCTION fn_integrite_mesure_capteur();

CREATE TRIGGER trg_fk_mesure_temp
    BEFORE INSERT OR UPDATE OF code_capteur ON mesure_temperature
    FOR EACH ROW EXECUTE FUNCTION fn_integrite_mesure_capteur();

CREATE TRIGGER trg_fk_mesure_air
    BEFORE INSERT OR UPDATE OF code_capteur ON mesure_air
    FOR EACH ROW EXECUTE FUNCTION fn_integrite_mesure_capteur();

CREATE TRIGGER trg_fk_mesure_hydro
    BEFORE INSERT OR UPDATE OF code_capteur ON mesure_hydro
    FOR EACH ROW EXECUTE FUNCTION fn_integrite_mesure_capteur();
