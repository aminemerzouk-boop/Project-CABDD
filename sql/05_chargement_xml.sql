-- ============================================================================
-- Script 05 : Chargement 100 % SQL des lots XML & Isolement (Etape 2)
-- Mini-projet CABDD (ING 4 GL) - Variante A (mesures a plat, attributs XML)
-- Binome : Merzouk Amine & Megharba Samou
-- Responsable principal : Merzouk Amine
-- Base cible : centre
-- A lancer depuis la racine du depot (chemin relatif data/lots_A.xml)
-- ============================================================================

\connect centre

-- ============================================================================
-- 1. Fonctions utilitaires de conversion securisee (sans lever d'exception)
-- ============================================================================

CREATE OR REPLACE FUNCTION to_numeric_safe(p_txt TEXT)
RETURNS NUMERIC AS $$
BEGIN
    IF p_txt IS NULL OR p_txt !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
        RETURN NULL;
    END IF;
    RETURN p_txt::numeric;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION to_timestamp_iso_safe(p_txt TEXT)
RETURNS TIMESTAMP AS $$
BEGIN
    IF p_txt IS NULL OR p_txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN
        RETURN NULL;
    END IF;
    RETURN p_txt::timestamp;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- 2. Procedure SQL/PLpgSQL d'ingestion et de qualification sans aucune perte
--    (Reutilisable aussi en demonstration sur tout nouveau flux XML)
-- ============================================================================

CREATE OR REPLACE FUNCTION charger_lots_xml(p_doc_xml XML)
RETURNS TABLE (
    lots_inseres    BIGINT,
    mesures_lues    BIGINT,
    mesures_valides BIGINT,
    mesures_isolees BIGINT
) AS $$
DECLARE
    v_lots_inseres    BIGINT := 0;
    v_mesures_lues    BIGINT := 0;
    v_mesures_valides BIGINT := 0;
    v_mesures_isolees BIGINT := 0;
    r                 RECORD;
BEGIN
    SET LOCAL client_min_messages = warning;
    DROP TABLE IF EXISTS tmp_nouveaux_lots;
    DROP TABLE IF EXISTS tmp_mesures_extraites;
    DROP TABLE IF EXISTS tmp_mesures_qualifiees;
    SET LOCAL client_min_messages = notice;

    -- 2.1 Decoupage des elements <lot> et conservation intacte dans lot_brut
    CREATE TEMP TABLE tmp_nouveaux_lots (
        id_lot       BIGINT,
        code_station VARCHAR(10),
        date_envoi   TIMESTAMP,
        contenu_xml  XML
    ) ON COMMIT DROP;

    WITH lots_lus AS (
        SELECT xt.rang_lot,
               xt.code_station,
               xt.date_envoi,
               xt.contenu_xml
        FROM XMLTABLE(
                 '/lots/lot'
                 PASSING p_doc_xml
                 COLUMNS
                     rang_lot     FOR ORDINALITY,
                     code_station VARCHAR(10) PATH '@station',
                     date_envoi   TIMESTAMP   PATH '@envoi',
                     contenu_xml  XML         PATH '.'
             ) AS xt
        ORDER BY xt.rang_lot
    ),
    ins_lots AS (
        INSERT INTO lot_brut (code_station, date_envoi, contenu_xml)
        SELECT code_station, date_envoi, contenu_xml
        FROM lots_lus
        RETURNING id_lot, code_station, date_envoi, contenu_xml
    )
    INSERT INTO tmp_nouveaux_lots
    SELECT id_lot, code_station, date_envoi, contenu_xml
    FROM ins_lots;

    SELECT count(*) INTO v_lots_inseres FROM tmp_nouveaux_lots;

    -- 2.2 Extraction a plat de toutes les balises <mesure .../> des lots recus
    CREATE TEMP TABLE tmp_mesures_extraites ON COMMIT DROP AS
    SELECT row_number() OVER (ORDER BY nl.id_lot, mx.rang_mesure) AS rid,
           nl.id_lot,
           nl.code_station AS code_station_lot,
           mx.capteur_txt,
           mx.instant_txt,
           mx.type_txt,
           mx.valeur_txt,
           mx.pm25_txt,
           mx.pm10_txt,
           mx.no2_txt,
           mx.humidite_txt,
           mx.pluie_txt,
           mx.mesure_xml
    FROM tmp_nouveaux_lots nl,
         XMLTABLE(
             '/lot/mesure'
             PASSING nl.contenu_xml
             COLUMNS
                 rang_mesure  FOR ORDINALITY,
                 capteur_txt  TEXT PATH '@capteur',
                 instant_txt  TEXT PATH '@instant',
                 type_txt     TEXT PATH '@type',
                 valeur_txt   TEXT PATH '@valeur',
                 pm25_txt     TEXT PATH '@pm25',
                 pm10_txt     TEXT PATH '@pm10',
                 no2_txt      TEXT PATH '@no2',
                 humidite_txt TEXT PATH '@humidite',
                 pluie_txt    TEXT PATH '@pluie',
                 mesure_xml   XML  PATH '.'
         ) AS mx;

    SELECT count(*) INTO v_mesures_lues FROM tmp_mesures_extraites;

    -- 2.3 Qualification selon les 5 motifs officiels de l'enonce :
    --     Ordre logique : capteur_inconnu -> valeur_manquante -> format_invalide
    --                     -> valeur_impossible -> doublon (en base ou intra-flux)
    CREATE TEMP TABLE tmp_mesures_qualifiees ON COMMIT DROP AS
    SELECT b.rid,
           b.id_lot,
           b.code_station_lot,
           b.capteur_txt,
           b.instant_txt,
           b.type_txt,
           b.mesure_xml,
           c.type_capteur AS type_ref,
           to_timestamp_iso_safe(b.instant_txt) AS instant_ts,
           to_numeric_safe(b.valeur_txt)        AS temp_num,
           to_numeric_safe(b.pm25_txt)          AS pm25_num,
           to_numeric_safe(b.pm10_txt)          AS pm10_num,
           to_numeric_safe(b.no2_txt)           AS no2_num,
           to_numeric_safe(b.humidite_txt)      AS hum_num,
           to_numeric_safe(b.pluie_txt)         AS pluie_num,
           CASE
               -- (1) Capteur absent du referentiel
               WHEN b.capteur_txt IS NULL OR btrim(b.capteur_txt) = '' OR c.code_capteur IS NULL
                   THEN 'capteur_inconnu'::motif_rejet_enum

               -- (2) Grandeur ou attribut obligatoire absent / vide
               WHEN b.instant_txt IS NULL OR btrim(b.instant_txt) = ''
                 OR b.type_txt    IS NULL OR btrim(b.type_txt)    = ''
                 OR (c.type_capteur = 'temperature' AND (b.valeur_txt IS NULL OR btrim(b.valeur_txt) = ''))
                 OR (c.type_capteur = 'air' AND (
                        b.pm25_txt IS NULL OR btrim(b.pm25_txt) = '' OR
                        b.pm10_txt IS NULL OR btrim(b.pm10_txt) = '' OR
                        b.no2_txt  IS NULL OR btrim(b.no2_txt)  = ''
                    ))
                 OR (c.type_capteur = 'hydro' AND (
                        b.humidite_txt IS NULL OR btrim(b.humidite_txt) = '' OR
                        b.pluie_txt    IS NULL OR btrim(b.pluie_txt)    = ''
                    ))
                   THEN 'valeur_manquante'::motif_rejet_enum

               -- (3) Format invalide (date non ISO/calendrier invalide, virgule decimale, type incoherent)
               WHEN to_timestamp_iso_safe(b.instant_txt) IS NULL
                 OR b.type_txt <> c.type_capteur::text
                 OR (c.type_capteur = 'temperature' AND to_numeric_safe(b.valeur_txt) IS NULL)
                 OR (c.type_capteur = 'air' AND (
                        to_numeric_safe(b.pm25_txt) IS NULL OR
                        to_numeric_safe(b.pm10_txt) IS NULL OR
                        to_numeric_safe(b.no2_txt)  IS NULL
                    ))
                 OR (c.type_capteur = 'hydro' AND (
                        to_numeric_safe(b.humidite_txt) IS NULL OR
                        to_numeric_safe(b.pluie_txt)    IS NULL
                    ))
                   THEN 'format_invalide'::motif_rejet_enum

               -- (4) Valeur physiquement impossible (hors bornes metrologiques)
               WHEN (c.type_capteur = 'temperature' AND to_numeric_safe(b.valeur_txt) NOT BETWEEN -60 AND 60)
                 OR (c.type_capteur = 'air' AND (
                        to_numeric_safe(b.pm25_txt) NOT BETWEEN 0 AND 500  OR
                        to_numeric_safe(b.pm10_txt) NOT BETWEEN 0 AND 1000 OR
                        to_numeric_safe(b.no2_txt)  NOT BETWEEN 0 AND 1000
                    ))
                 OR (c.type_capteur = 'hydro' AND (
                        to_numeric_safe(b.humidite_txt) NOT BETWEEN 0 AND 100 OR
                        to_numeric_safe(b.pluie_txt)    NOT BETWEEN 0 AND 500
                    ))
                   THEN 'valeur_impossible'::motif_rejet_enum

               -- (5a) Doublon par rapport aux mesures deja presentes en base
               WHEN EXISTS (
                   SELECT 1 FROM mesure m
                   WHERE m.code_capteur   = b.capteur_txt
                     AND m.instant_mesure = to_timestamp_iso_safe(b.instant_txt)
               )
                   THEN 'doublon'::motif_rejet_enum

               ELSE NULL
           END AS motif,
           NULL::text AS detail_motif
    FROM tmp_mesures_extraites b
    LEFT JOIN capteur c ON c.code_capteur = b.capteur_txt;

    -- (5b) Doublons internes au flux XML : seule la 1re occurrence (min rid) est retenue
    WITH rangs_doublons AS (
        SELECT rid,
               row_number() OVER (
                   PARTITION BY capteur_txt, instant_ts
                   ORDER BY rid
               ) AS rn
        FROM tmp_mesures_qualifiees
        WHERE motif IS NULL
    )
    UPDATE tmp_mesures_qualifiees q
       SET motif        = 'doublon'::motif_rejet_enum,
           detail_motif = 'Mesure deja recue plus tot dans le meme flux XML (couple capteur/instant duplique).'
      FROM rangs_doublons d
     WHERE q.rid = d.rid
       AND d.rn > 1;

    -- Renseignement d'un detail explicatif pour chaque anomalie detectee
    UPDATE tmp_mesures_qualifiees
       SET detail_motif = CASE motif
           WHEN 'capteur_inconnu'   THEN 'Capteur absent du referentiel : ' || coalesce(capteur_txt, 'NULL')
           WHEN 'valeur_manquante'  THEN 'Attribut obligatoire manquant ou vide dans <mesure/>'
           WHEN 'format_invalide'   THEN 'Format de nombre (ex. virgule) ou timestamp ISO invalide'
           WHEN 'valeur_impossible' THEN 'Grandeur hors limites physiques autorisees par le schema'
           WHEN 'doublon'           THEN coalesce(detail_motif, 'Couple (capteur, instant) deja present en base')
       END
     WHERE motif IS NOT NULL
       AND detail_motif IS NULL;

    -- 2.4 Insertion des mesures rejetees dans l'espace d'isolement
    INSERT INTO mesure_isolee (
        id_lot, code_station_lot, code_capteur_txt, instant_txt,
        mesure_xml, motif, detail_motif
    )
    SELECT id_lot, code_station_lot, capteur_txt, instant_txt,
           mesure_xml, motif, detail_motif
    FROM tmp_mesures_qualifiees
    WHERE motif IS NOT NULL
    ORDER BY rid;

    -- 2.5 Insertion des mesures valides (mode ensembliste rapide + filet de
    --     securite ligne par ligne si une erreur imprevue survient)
    BEGIN
        INSERT INTO mesure_temperature (code_capteur, instant_mesure, id_lot, temperature)
        SELECT capteur_txt, instant_ts, id_lot, temp_num
        FROM tmp_mesures_qualifiees
        WHERE motif IS NULL AND type_ref = 'temperature'
        ORDER BY rid;

        INSERT INTO mesure_air (code_capteur, instant_mesure, id_lot, valeurs_air)
        SELECT capteur_txt, instant_ts, id_lot,
               ROW(pm25_num, pm10_num, no2_num)::t_qualite_air
        FROM tmp_mesures_qualifiees
        WHERE motif IS NULL AND type_ref = 'air'
        ORDER BY rid;

        INSERT INTO mesure_hydro (code_capteur, instant_mesure, id_lot, valeurs_hydro)
        SELECT capteur_txt, instant_ts, id_lot,
               ROW(hum_num, pluie_num)::t_hydrometrie
        FROM tmp_mesures_qualifiees
        WHERE motif IS NULL AND type_ref = 'hydro'
        ORDER BY rid;

        SELECT count(*) INTO v_mesures_valides
        FROM tmp_mesures_qualifiees
        WHERE motif IS NULL;

    EXCEPTION WHEN others THEN
        -- Repli granulaire : si le fichier contient une anomalie totalement imprevue,
        -- seule la mesure fautive est isolee et toutes les autres sont chargees !
        v_mesures_valides := 0;
        FOR r IN
            SELECT * FROM tmp_mesures_qualifiees WHERE motif IS NULL ORDER BY rid
        LOOP
            BEGIN
                IF r.type_ref = 'temperature' THEN
                    INSERT INTO mesure_temperature (code_capteur, instant_mesure, id_lot, temperature)
                    VALUES (r.capteur_txt, r.instant_ts, r.id_lot, r.temp_num);
                ELSIF r.type_ref = 'air' THEN
                    INSERT INTO mesure_air (code_capteur, instant_mesure, id_lot, valeurs_air)
                    VALUES (r.capteur_txt, r.instant_ts, r.id_lot, ROW(r.pm25_num, r.pm10_num, r.no2_num)::t_qualite_air);
                ELSIF r.type_ref = 'hydro' THEN
                    INSERT INTO mesure_hydro (code_capteur, instant_mesure, id_lot, valeurs_hydro)
                    VALUES (r.capteur_txt, r.instant_ts, r.id_lot, ROW(r.hum_num, r.pluie_num)::t_hydrometrie);
                END IF;
                v_mesures_valides := v_mesures_valides + 1;
            EXCEPTION WHEN others THEN
                INSERT INTO mesure_isolee (
                    id_lot, code_station_lot, code_capteur_txt, instant_txt,
                    mesure_xml, motif, detail_motif
                )
                VALUES (
                    r.id_lot, r.code_station_lot, r.capteur_txt, r.instant_txt,
                    r.mesure_xml, 'valeur_impossible',
                    'Erreur imprevue interceptee a l''insertion : ' || SQLERRM
                );
            END;
        END LOOP;
    END;

    v_mesures_isolees := v_mesures_lues - v_mesures_valides;

    RETURN QUERY
    SELECT v_lots_inseres, v_mesures_lues, v_mesures_valides, v_mesures_isolees;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. Fonctions d'interrogation directe des lots bruts XML (XPath pur)
--    Sans passer par les tables de mesures !
-- ============================================================================

-- 3.1 Retrouver les lots contenant au moins une mesure d'un capteur donne
CREATE OR REPLACE FUNCTION lots_contenant_capteur(p_code_capteur VARCHAR)
RETURNS TABLE (
    id_lot             BIGINT,
    code_station       VARCHAR,
    date_envoi         TIMESTAMP,
    nb_mesures_capteur INT
) AS $$
    SELECT lb.id_lot,
           lb.code_station,
           lb.date_envoi,
           coalesce(
               array_length(
                   xpath('/lot/mesure[@capteur="' || replace(p_code_capteur, '"', '') || '"]', lb.contenu_xml),
                   1
               ),
               0
           ) AS nb_mesures_capteur
    FROM lot_brut lb
    WHERE xpath_exists(
              '/lot/mesure[@capteur="' || replace(p_code_capteur, '"', '') || '"]',
              lb.contenu_xml
          )
    ORDER BY lb.date_envoi, lb.id_lot;
$$ LANGUAGE sql STABLE;

-- 3.2 Compter les mesures contenues dans chaque lot brut XML
CREATE OR REPLACE FUNCTION compter_mesures_par_lot()
RETURNS TABLE (
    id_lot       BIGINT,
    code_station VARCHAR,
    date_envoi   TIMESTAMP,
    nb_mesures   INT
) AS $$
    SELECT lb.id_lot,
           lb.code_station,
           lb.date_envoi,
           coalesce(array_length(xpath('/lot/mesure', lb.contenu_xml), 1), 0) AS nb_mesures
    FROM lot_brut lb
    ORDER BY lb.id_lot;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 4. Chargement effectif de data/lots_A.xml (100 % SQL / psql portable)
--    \lo_import lit le fichier cote client psql, puis \set xml_oid sauvegarde
--    immediatement :LASTOID avant que la requete suivante ne le reinitialise.
-- ============================================================================

TRUNCATE mesure_temperature, mesure_air, mesure_hydro, mesure, mesure_isolee, lot_brut RESTART IDENTITY CASCADE;
ALTER SEQUENCE seq_mesure RESTART WITH 1;

\lo_import 'data/lots_A.xml'
\set xml_oid :LASTOID

CREATE TEMP TABLE tmp_fichier_lots_xml AS
SELECT xmlparse(DOCUMENT convert_from(lo_get(:'xml_oid'::oid), 'UTF8')) AS doc_xml;

SELECT lo_unlink(:'xml_oid'::oid) AS nettoyage_objet_temporaire;

-- Execution du pipeline d'ingestion sur data/lots_A.xml
SELECT * FROM charger_lots_xml((SELECT doc_xml FROM tmp_fichier_lots_xml));

DROP TABLE tmp_fichier_lots_xml;

-- ============================================================================
-- 5. Controles d'exhaustivite et demonstrations XPath sur les lots bruts
-- ============================================================================

-- 5.1 Preuve "Aucune mesure perdue" : valides + isolees = total XML (lu en XPath)
WITH decompte AS (
    SELECT (SELECT sum(nb_mesures) FROM compter_mesures_par_lot()) AS total_dans_lots_xml,
           (SELECT count(*) FROM mesure)                           AS mesures_valides,
           (SELECT count(*) FROM mesure_isolee)                    AS mesures_isolees
)
SELECT total_dans_lots_xml,
       mesures_valides,
       mesures_isolees,
       (mesures_valides + mesures_isolees)                        AS somme_valides_plus_isolees,
       (total_dans_lots_xml = mesures_valides + mesures_isolees)  AS aucune_mesure_perdue
FROM decompte;

-- 5.2 Ventilation des mesures valides par sous-table typee
SELECT 'mesure_temperature' AS table_cible, count(*) AS effectif FROM mesure_temperature
UNION ALL SELECT 'mesure_air',   count(*) FROM mesure_air
UNION ALL SELECT 'mesure_hydro', count(*) FROM mesure_hydro
UNION ALL SELECT 'TOTAL VALIDES (table mere mesure)', count(*) FROM mesure;

-- 5.3 Ventilation des mesures isolees selon les 5 motifs de rejet
SELECT motif, count(*) AS nb_rejets
FROM mesure_isolee
GROUP BY motif
ORDER BY nb_rejets DESC, motif;

-- 5.4 Interrogation XPath directe sur lot_brut (sans passer par les tables de mesures) :
--     a) Lots contenant une mesure du capteur BJ-02-A1 (mis en service le 02/02/2026)
SELECT count(*) AS nb_lots_avec_BJ_02_A1,
       min(date_envoi) AS premier_envoi,
       max(date_envoi) AS dernier_envoi
FROM lots_contenant_capteur('BJ-02-A1');

--     b) Apercu des 5 premiers lots contenant BJ-01-H1
SELECT * FROM lots_contenant_capteur('BJ-01-H1') LIMIT 5;

--     c) Apercu du comptage direct des mesures des 5 premiers lots bruts
SELECT * FROM compter_mesures_par_lot() LIMIT 5;
