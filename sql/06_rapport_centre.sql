-- =====================================================================
-- 06_rapport_centre.sql  --  ETAPE 3 (suite) : rapport XML depuis le centre
-- psql -d centre -v ON_ERROR_STOP=1 -f sql/06_rapport_centre.sql
-- =====================================================================

-- Le rapport de l'étape 2 fonctionne tel quel depuis le centre :
-- vue_mesure_plat a été redéfinie sur la vue distribuée 'mesure'.
SELECT rapport_bilan_journalier('2026-02-01'::date, '2026-02-28'::date);

\copy (SELECT rapport_bilan_journalier('2026-02-01'::date, '2026-02-28'::date)::text) TO 'rapport_fevrier_centre.xml'

-- ---------------------------------------------------------------------
-- Démonstrations de transparence (à commenter avec EXPLAIN dans le rapport)
-- ---------------------------------------------------------------------

-- 1. Une seule requête SQL interroge les deux zones comme si c'était local
SELECT st.zone, count(*) AS nb_mesures, round(avg(v.valeur),2) AS moyenne
FROM vue_mesure_plat v JOIN station st ON st.code = v.station_code
WHERE v.grandeur = 'temperature' AND v.instant >= '2026-03-01' AND v.instant < '2026-04-01'
GROUP BY st.zone ORDER BY st.zone;

-- 2. Plan d'exécution : une requête sur UNE zone et UN mois ne parcourt
--    que la partition concernée de la zone visée
EXPLAIN (COSTS OFF)
SELECT count(*), avg(valeur) FROM mesure
WHERE grandeur = 'humidite' AND instant >= '2026-02-01' AND instant < '2026-03-01';

-- 3. Insertion depuis le centre : stockée physiquement dans la bonne zone
INSERT INTO mesure (capteur_code, instant, grandeur, valeur)
VALUES ('BJ-01-T1', '2026-05-02T06:00:00', 'temperature', 21.5);
SELECT id, capteur_code, instant, grandeur, valeur FROM z1.mesure
WHERE instant >= '2026-05-01' AND capteur_code = 'BJ-01-T1';

-- 4. Propagation du référentiel : une station ajoutée au centre
--    apparaît automatiquement dans les deux zones
INSERT INTO station (code, nom, wilaya, zone, pos)
VALUES ('BJ-04', 'Station Béjaïa 4', 'Béjaïa', 1, ROW(36.71, 5.05, 200)::type_position);
SELECT 'centre' AS base, count(*) FROM station WHERE code = 'BJ-04'
UNION ALL SELECT 'zone1', count(*) FROM z1.station WHERE code = 'BJ-04'
UNION ALL SELECT 'zone2', count(*) FROM z2.station WHERE code = 'BJ-04';

-- 5. Unicité des identifiants sur tout le réseau
SELECT count(*) AS total_lignes, count(DISTINCT (capteur_code, instant, grandeur)) AS mesures_distinctes FROM mesure;
