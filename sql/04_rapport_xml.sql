-- =====================================================================
-- 04_rapport_xml.sql  --  ETAPE 2 (suite) : rapport XML bilan journalier
-- (variante A : pour chaque jour, station et grandeur -> min, max,
--  moyenne et nombre de mesures valides utilisées)
-- psql -d centre -v ON_ERROR_STOP=1 -f sql/04_rapport_xml.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION rapport_bilan_journalier(p_debut date, p_fin date)
RETURNS xml LANGUAGE sql AS $$
WITH jours AS (
    SELECT generate_series(p_debut, p_fin, interval '1 day')::date AS jour
),
stats AS (   -- agrégats par jour / station / grandeur sur les mesures valides
    SELECT v.instant::date AS jour, v.station_code, v.grandeur,
           min(v.valeur) AS min, max(v.valeur) AS max,
           avg(v.valeur) AS moyenne, count(*) AS nb
    FROM vue_mesure_plat v
    WHERE v.instant::date BETWEEN p_debut AND p_fin
    GROUP BY v.instant::date, v.station_code, v.grandeur
)
SELECT xmlelement(
         NAME rapport,
         xmlattributes('bilan-journalier' AS type,
                       'variante-A'      AS variante,
                       p_debut::text     AS periode_debut,
                       p_fin::text       AS periode_fin),
         (SELECT xmlagg(
                   xmlelement(NAME jour, xmlattributes(j.jour::text AS date),
                     (SELECT xmlagg(
                               xmlelement(NAME station,
                                 xmlattributes(s.code AS code, s.wilaya AS wilaya),
                                 (SELECT xmlagg(
                                           xmlelement(NAME grandeur,
                                             xmlattributes(
                                               g.grandeur        AS nom,
                                               round(g.min,2)::text   AS min,
                                               round(g.max,2)::text   AS max,
                                               round(g.moyenne,2)::text AS moyenne,
                                               g.nb::text          AS nb_mesures))
                                           ORDER BY g.grandeur)
                                  FROM stats g
                                  WHERE g.jour = j.jour AND g.station_code = s.code)))
                      FROM station s
                      WHERE EXISTS (SELECT 1 FROM stats g
                                    WHERE g.jour = j.jour AND g.station_code = s.code)))
                  ORDER BY j.jour)
          FROM jours j))
$$;

-- Rapport de janvier 2026 (période passée en paramètre)
SELECT rapport_bilan_journalier('2026-01-01'::date, '2026-01-31'::date);

-- Export dans un fichier (depuis la racine du projet)
\copy (SELECT rapport_bilan_journalier('2026-01-01'::date, '2026-01-31'::date)::text) TO 'rapport_janvier.xml'
