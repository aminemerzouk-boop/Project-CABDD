-- =====================================================================
-- 00_init.sql  --  Création des trois bases (à exécuter sur la base 'postgres')
-- Mode cluster unique :  psql -d postgres -f sql/00_init.sql
-- En mode Docker (3 conteneurs), chaque conteneur héberge UNE base :
--   centre -> base 'centre', zone1 -> 'zone1', zone2 -> 'zone2' (déjà créées
--   par POSTGRES_DB dans docker-compose.yml ; ce script est alors inutile).
-- =====================================================================
SELECT 'creation des bases' AS etape;

CREATE DATABASE centre;
CREATE DATABASE zone1;
CREATE DATABASE zone2;
