# CABDD — Tableau de bord web (Variante A)

Interface web style macOS connectée à PostgreSQL (données réelles du projet :
référentiel, mesures chargées, zones partitionnées, bilan XML, EXPLAIN).

## Lancement
```bash
# 1. Charger la chaîne SQL 01→09 (voir run_all.ps1 / run_all.sh à la racine)
# 2. Lancer le serveur (Python stdlib uniquement, aucun paquet à installer) :
python app/server.py
# puis ouvrir http://localhost:8000
```

Variables d'environnement : `PORT` (8000), `PGHOST` (127.0.0.1), `PGPORT` (5432),
`PGUSER` (postgres), `PGPASSWORD`, `PSQL` (chemin du client psql).

## API JSON
| Endpoint | Description |
|---|---|
| `/api/kpi` | mesures valides / isolées, stations, capteurs, lots |
| `/api/zones` | mesures réellement stockées en zone1 / zone2 |
| `/api/stations` | référentiel des stations avec zone |
| `/api/bilan?debut=2026-02-01&fin=2026-02-07` | bilan journalier XML depuis le centre |
| `/api/explain` | EXPLAIN ANALYZE pruning mensuel (février 2026) |
| `/api/explain_zone1` | EXPLAIN requête filtrée zone 1 (résilience) |
