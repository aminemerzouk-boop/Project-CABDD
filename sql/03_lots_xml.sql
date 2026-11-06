-- =====================================================================
-- 03_lots_xml.sql  --  ETAPE 2 : chargement des lots XML, 100 % en SQL
-- psql -d centre -v ON_ERROR_STOP=1 -v xml_path="/chemin/absolu/data/lots_A.xml" \
--        -f sql/03_lots_xml.sql
--
-- Principe : aucune mesure n'est perdue. Chaque <mesure> du fichier est
-- soit insérée dans la table typée correspondante, soit placée dans
-- mesure_isolee avec son lot d'origine, sa forme XML d'origine et le
-- motif du rejet (une des 5 sortes d'erreurs prévues).
-- =====================================================================

-- Fonctions utilitaires de validation de format (SQL pur + plpgsql)
CREATE OR REPLACE FUNCTION txt_est_nombre(t text) RETURNS boolean AS $$
    SELECT t ~ '^-?[0-9]+([.][0-9]+)?$'
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION txt_est_date_iso(t text) RETURNS boolean AS $$
BEGIN
    -- format ISO attendu ET date réellement valide (ex. pas de 25:00, pas de 30 février)
    IF t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN
        RETURN false;
    END IF;
    PERFORM t::timestamp;
    RETURN true;
EXCEPTION WHEN others THEN
    RETURN false;
END $$ LANGUAGE plpgsql IMMUTABLE;

-- ---------------------------------------------------------------------
-- 1. Lecture du fichier et découpage en lots bruts (conservés en XML)
-- ---------------------------------------------------------------------
TRUNCATE mesure_isolee, lot_brut;
ALTER SEQUENCE seq_mesure RESTART WITH 1;
ALTER SEQUENCE seq_isole  RESTART WITH 1;

INSERT INTO lot_brut (id, station, envoi, contenu)
SELECT row_number() OVER (),
       (xpath('/lot/@station', l.lot))[1]::text,
       (xpath('/lot/@envoi',   l.lot))[1]::text::timestamp,
       l.lot                                            -- le lot XML brut, tel quel
FROM (SELECT unnest(xpath('/lots/lot', pg_read_file(:'xml_path')::xml)) AS lot) l;

-- ---------------------------------------------------------------------
-- 2. Extraction de toutes les mesures (une ligne par <mesure>)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE brut_mesure AS
SELECT row_number() OVER () AS rid,
       lb.id                AS lot_id,
       (xpath('/mesure/@capteur',  m.mes))[1]::text AS capteur,
       (xpath('/mesure/@instant',  m.mes))[1]::text AS instant_txt,
       (xpath('/mesure/@valeur',   m.mes))[1]::text AS valeur,
       (xpath('/mesure/@pm25',     m.mes))[1]::text AS pm25,
       (xpath('/mesure/@pm10',     m.mes))[1]::text AS pm10,
       (xpath('/mesure/@no2',      m.mes))[1]::text AS no2,
       (xpath('/mesure/@humidite', m.mes))[1]::text AS humidite,
       (xpath('/mesure/@pluie',    m.mes))[1]::text AS pluie,
       m.mes                AS xml_mesure
FROM lot_brut lb,
     unnest(xpath('/lot/mesure', lb.contenu)) AS m(mes);

-- ---------------------------------------------------------------------
-- 3. Classification : chaque mesure reçoit un motif ou est valide
--    (ordre de priorité : capteur inconnu > format > manquante >
--     impossible > doublon)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE classe AS
SELECT b.rid, b.lot_id, b.capteur, b.instant_txt, b.valeur, b.pm25, b.pm10,
       b.no2, b.humidite, b.pluie, b.xml_mesure,
       c.type AS type_ref,
       CASE
         -- 4. capteur inconnu : absent du référentiel
         WHEN c.code IS NULL THEN 'capteur_inconnu'
         -- 3. format invalide : date illisible ou nombre illisible
         WHEN NOT txt_est_date_iso(b.instant_txt)
           OR (c.type = 'temperature' AND NOT txt_est_nombre(b.valeur))
           OR (c.type = 'air'  AND (NOT txt_est_nombre(b.pm25)
                                OR NOT txt_est_nombre(b.pm10)
                                OR NOT txt_est_nombre(b.no2)))
           OR (c.type = 'hydro' AND (NOT txt_est_nombre(b.humidite)
                                OR NOT txt_est_nombre(b.pluie)))
              THEN 'format_invalide'
         -- 2. valeur manquante : attribut attendu absent
         WHEN (c.type = 'temperature' AND b.valeur   IS NULL)
           OR (c.type = 'air'  AND (b.pm25 IS NULL OR b.pm10 IS NULL OR b.no2 IS NULL))
           OR (c.type = 'hydro' AND (b.humidite IS NULL OR b.pluie IS NULL))
              THEN 'valeur_manquante'
         -- 1. valeur impossible (mêmes bornes que les CHECK des tables)
         WHEN (c.type = 'temperature' AND b.valeur::numeric NOT BETWEEN -60 AND 60)
           OR (c.type = 'air'  AND (b.pm25::numeric < 0 OR b.pm25::numeric > 500
                                OR b.pm10::numeric < 0 OR b.pm10::numeric > 1000
                                OR b.no2::numeric  < 0 OR b.no2::numeric  > 1000))
           OR (c.type = 'hydro' AND (b.humidite::numeric NOT BETWEEN 0 AND 100
                                 OR b.pluie::numeric NOT BETWEEN 0 AND 1000))
              THEN 'valeur_impossible'
         -- 5. doublon : (capteur, instant) déjà en base au moment du chargement
         WHEN EXISTS (SELECT 1 FROM mesure m
                      WHERE m.capteur_code = b.capteur
                        AND m.instant = b.instant_txt::timestamp)
              THEN 'doublon'
         ELSE NULL                                   -- mesure valide
       END AS motif
FROM brut_mesure b
LEFT JOIN capteur c ON c.code = b.capteur;

-- doublons internes au lot/fichier : on ne garde que la 1ère occurrence
UPDATE classe c SET motif = 'doublon'
WHERE c.motif IS NULL
  AND c.rid <> (SELECT min(x.rid) FROM classe x
                WHERE x.motif IS NULL
                  AND x.capteur = c.capteur
                  AND x.instant_txt = c.instant_txt);

-- ---------------------------------------------------------------------
-- 4. Insertion des mesures valides dans la table typée correspondante
--    (les CHECK de l'étape 1 garantissent qu'aucune valeur impossible
--     ne peut passer : double protection)
-- ---------------------------------------------------------------------
INSERT INTO mesure_temperature (id, capteur_code, instant, valeur)
SELECT nextval('seq_mesure'), capteur, instant_txt::timestamp, valeur::numeric
FROM classe WHERE motif IS NULL AND type_ref = 'temperature';

INSERT INTO mesure_air (id, capteur_code, instant, air)
SELECT nextval('seq_mesure'), capteur, instant_txt::timestamp,
       ROW(pm25::numeric, pm10::numeric, no2::numeric)::type_air
FROM classe WHERE motif IS NULL AND type_ref = 'air';

INSERT INTO mesure_hydro (id, capteur_code, instant, hydro)
SELECT nextval('seq_mesure'), capteur, instant_txt::timestamp,
       ROW(humidite::numeric, pluie::numeric)::type_hydro
FROM classe WHERE motif IS NULL AND type_ref = 'hydro';

-- ---------------------------------------------------------------------
-- 5. Isolement des mesures corrompues (forme d'origine + lot + motif)
-- ---------------------------------------------------------------------
INSERT INTO mesure_isolee (id, lot_id, capteur_txt, instant_txt, motif, xml_original)
SELECT nextval('seq_isole'), lot_id, capteur, instant_txt, motif, xml_mesure
FROM classe WHERE motif IS NOT NULL;

-- ---------------------------------------------------------------------
-- 6. Contrôle : aucune mesure perdue  (valides + isolées = total fichier)
-- ---------------------------------------------------------------------
SELECT (SELECT count(*) FROM brut_mesure)                          AS total_fichier,
       (SELECT count(*) FROM mesure)                               AS mesures_valides,
       (SELECT count(*) FROM mesure_isolee)                        AS mesures_isolees,
       (SELECT count(*) FROM mesure) + (SELECT count(*) FROM mesure_isolee)
                                                                   AS somme,
       (SELECT count(*) FROM brut_mesure)
         = (SELECT count(*) FROM mesure) + (SELECT count(*) FROM mesure_isolee)
                                                                   AS controle_ok;

SELECT motif, count(*) FROM mesure_isolee GROUP BY motif ORDER BY motif;

-- ---------------------------------------------------------------------
-- 7. Les lots bruts restent interrogeables directement en XML
-- ---------------------------------------------------------------------
-- 7a. Lots contenant au moins une mesure d'un capteur donné :
SELECT id, station, envoi
FROM lot_brut
WHERE array_length(xpath('/lot/mesure[@capteur="BJ-01-T1"]', contenu), 1) > 0
LIMIT 5;

-- 7b. Nombre de mesures de chaque lot :
SELECT id, station, envoi,
       array_length(xpath('/lot/mesure', contenu), 1) AS nb_mesures
FROM lot_brut
LIMIT 5;
