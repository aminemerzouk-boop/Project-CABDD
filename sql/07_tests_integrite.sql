-- =====================================================================
-- 07_tests_integrite.sql  --  Preuves que le schéma se protège seul
-- psql -d centre -f sql/07_tests_integrite.sql   (chaque test doit échouer)
-- =====================================================================

-- Test 1 : mesure pour un capteur inexistant -> REFUSÉ (FK vers la mère)
DO $$
BEGIN
    BEGIN
        INSERT INTO mesure_temperature (capteur_code, instant, valeur)
        VALUES ('XX-00-T9', '2026-01-01T00:00:00', 20);
        RAISE NOTICE 'ECHEC : insertion acceptee !';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'OK : capteur inexistant refusé (FK)';
    END;
END $$;

-- Test 2 : humidité > 100 % -> REFUSÉ par le CHECK de la base
DO $$
BEGIN
    BEGIN
        INSERT INTO mesure_hydro (capteur_code, instant, hydro)
        VALUES ('BJ-01-H1', '2026-01-01T00:00:00', ROW(130, 0)::type_hydro);
        RAISE NOTICE 'ECHEC : valeur impossible acceptee !';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK : humidite=130%% refusée (CHECK)';
    END;
END $$;

-- Test 3 : mesure de température sur un capteur de type air -> REFUSÉ
DO $$
BEGIN
    BEGIN
        INSERT INTO mesure_temperature (capteur_code, instant, valeur)
        VALUES ('BJ-01-A1', '2026-01-01T00:00:00', 20);
        RAISE NOTICE 'ECHEC : incohérence de type acceptee !';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'OK : type de capteur incohérent refusé (trigger)';
    END;
END $$;

-- Test 4 : les opérations définies dans la base fonctionnent en SQL pur
SELECT distance_km(pos, (SELECT pos FROM station WHERE code = 'JJ-01')) AS distance_BJ01_JJ01_km
FROM station WHERE code = 'BJ-01';

SELECT c.code, v.grandeur, v.valeur, depasse_seuil(c.code, v.grandeur, v.valeur) AS depasse
FROM vue_mesure_plat v JOIN capteur c ON c.code = v.capteur_code
WHERE depasse_seuil(c.code, v.grandeur, v.valeur) LIMIT 5;

SELECT valeur AS celsius, celsius_vers_fahrenheit(valeur) AS fahrenheit
FROM vue_mesure_plat WHERE grandeur = 'temperature' LIMIT 3;
