#!/usr/bin/env bash
# =====================================================================
# run_all.sh -- rejoue TOUT le projet (variante A) dans l'ordre, sur une
# installation vierge. Deux modes :
#
#  MODE 1 - cluster unique (3 bases dans le même serveur) :
#     ./run_all.sh --cluster --pg "psql -h 127.0.0.1 -p 5544 -U postgres"
#
#  MODE 2 - Docker (3 conteneurs : centre, zone1, zone2) :
#     docker compose up -d
#     ./run_all.sh --docker
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
XML_PATH="$PWD/data/lots_A.xml"

if [ "$MODE" = "--cluster" ]; then
    PG="${2:-psql -U postgres}"
    echo "== Mode cluster unique =="
    $PG -d postgres -c "DROP DATABASE IF EXISTS centre" -q
    $PG -d postgres -c "DROP DATABASE IF EXISTS zone1"  -q
    $PG -d postgres -c "DROP DATABASE IF EXISTS zone2"  -q
    $PG -d postgres -q -f sql/00_init.sql
    $PG -d centre -v ON_ERROR_STOP=1 -q -f sql/01_schema.sql
    $PG -d centre -v ON_ERROR_STOP=1 -q -f sql/02_referentiel.sql
    $PG -d centre -v ON_ERROR_STOP=1 -q -v xml_path="$XML_PATH" -f sql/03_lots_xml.sql
    $PG -d centre -v ON_ERROR_STOP=1 -q -f sql/04_rapport_xml.sql
    $PG -d zone1  -v ON_ERROR_STOP=1 -q -v zone_num=1 -v zone_offset=0          -f sql/05b_zone.sql
    $PG -d zone2  -v ON_ERROR_STOP=1 -q -v zone_num=2 -v zone_offset=1000000000000 -f sql/05b_zone.sql
    # FDW : les deux zones sont des bases du même cluster
    PORT=$($PG -d postgres -tAc "SHOW port")
    HOST=$($PG -d postgres -tAc "SHOW listen_addresses" | head -1)
    [ "$HOST" = "localhost" ] && HOST=127.0.0.1
    $PG -d centre -v ON_ERROR_STOP=1 -q -f sql/07_tests_integrite.sql
    $PG -d centre -v ON_ERROR_STOP=1 -v z1_host="$HOST" -v z2_host="$HOST" -v z_port="$PORT" \
        -v pg_user=postgres -v pg_pass=postgres -f sql/05_distribution_centre.sql
    $PG -d centre -v ON_ERROR_STOP=1 -q -f sql/06_rapport_centre.sql
    echo "== TERMINE (mode cluster) =="

elif [ "$MODE" = "--docker" ]; then
    echo "== Mode Docker (3 conteneurs) =="
    C="psql -h 127.0.0.1 -p 5433 -U postgres"
    Z1="psql -h 127.0.0.1 -p 5434 -U postgres"
    Z2="psql -h 127.0.0.1 -p 5435 -U postgres"
    $C -d centre -v ON_ERROR_STOP=1 -q -f sql/01_schema.sql
    $C -d centre -v ON_ERROR_STOP=1 -q -f sql/02_referentiel.sql
    $C -d centre -v ON_ERROR_STOP=1 -q -v xml_path=/data/lots_A.xml -f sql/03_lots_xml.sql
    $C -d centre -v ON_ERROR_STOP=1 -q -f sql/04_rapport_xml.sql
    $Z1 -d zone1 -v ON_ERROR_STOP=1 -q -v zone_num=1 -v zone_offset=0          -f sql/05b_zone.sql
    $Z2 -d zone2 -v ON_ERROR_STOP=1 -q -v zone_num=2 -v zone_offset=1000000000000 -f sql/05b_zone.sql
    $C -d centre -v ON_ERROR_STOP=1 -q -f sql/07_tests_integrite.sql
    $C -d centre -v ON_ERROR_STOP=1 -v z1_host=zone1 -v z2_host=zone2 -v z_port=5432 \
        -v pg_user=postgres -v pg_pass=postgres -f sql/05_distribution_centre.sql
    $C -d centre -v ON_ERROR_STOP=1 -q -f sql/06_rapport_centre.sql
    echo "== TERMINE (mode docker) =="
else
    echo "Usage: $0 --cluster [commande psql] | --docker"
    exit 1
fi
