# Mini-projet CABDD — Réseau de capteurs environnementaux (**Variante A**)

Module *Concepts avancés de BD* — ING 4 GL 2026/2027, Université de Béjaïa.

## Variante A retenue
| Élément | Choix |
|---|---|
| Zone 1 | Béjaïa (BJ), Jijel (JJ) |
| Zone 2 | Sétif (ST), Bordj Bou Arréridj (BBA) |
| Capteur spécifique | **Hydrométrie (H1)** : humidité relative (%), pluie (mm) |
| Organisation temporelle | **Partitionnement mensuel** dans les zones |
| Format des lots | Mesures à plat, **valeurs en attributs** (`<mesure capteur=... instant=... valeur=.../>`) |
| Rapport XML | **Bilan journalier** : min, max, moyenne, nombre de mesures par jour/station/grandeur |

## Outils nécessaires
- **Docker + docker compose** : 3 conteneurs `postgres:16` (`centre`, `zone1`, `zone2`) — voir `docker-compose.yml`
- **VS Code** + extensions recommandées (`.vscode/extensions.json`) : client PostgreSQL (connexions préconfigurées dans `.vscode/settings.json`), XML (RedHat), Docker
- **Git** : versioning des scripts SQL numérotés
- **psql** (client PostgreSQL, embarqué dans les conteneurs ou installé localement)
- **Python 3 (stdlib)** : uniquement pour générer les fichiers de données de démo (`data/generer_donnees.py`) — les fichiers officiels sont sur l'espace cours ; remplacer `data/*_A.*` par ceux-ci si disponibles

## Arborescence
```
├── docker-compose.yml          # 3 conteneurs PostgreSQL (ports 5433/5434/5435)
├── run_all.sh                  # rejoue tout le projet dans l'ordre (modes --docker / --cluster)
├── data/
│   ├── generer_donnees.py      # générateur des fichiers de la variante A
│   ├── stations_A.csv          # 12 stations
│   ├── capteurs_A.csv          # 36 capteurs
│   ├── seuils_A.csv            # 8 seuils d'alerte
│   └── lots_A.xml              # 1440 lots (34 576 mesures, 16 corrompues) [généré, gitignoré]
├── sql/
│   ├── 00_init.sql             # création des 3 bases (mode cluster unique)
│   ├── 01_schema.sql           # étape 1 : schéma relationnel-objet (centre)
│   ├── 02_referentiel.sql      # étape 1 : chargement CSV du référentiel
│   ├── 03_lots_xml.sql         # étape 2 : chargement XML 100% SQL + isolement
│   ├── 04_rapport_xml.sql      # étape 2 : rapport XML bilan journalier
│   ├── 05b_zone.sql            # étape 3 : schéma d'une zone (partitionnement mensuel)
│   ├── 05_distribution_centre.sql  # étape 3 : FDW, transparence, propagation du référentiel
│   ├── 06_rapport_centre.sql   # étape 3 : rapport + démonstrations depuis le centre
│   └── 07_tests_integrite.sql  # preuves que le schéma se protège seul
└── rapport/rapport.md          # rapport (3 étapes, ≤ 10 pages)
```

## Exécution rapide
```bash
# 1. Générer les données (si les fichiers officiels ne sont pas fournis)
python3 data/generer_donnees.py

# 2. Mode Docker (recommandé) — 3 conteneurs indépendants
docker compose up -d
./run_all.sh --docker

#    OU mode cluster unique (3 bases dans un seul serveur PostgreSQL)
./run_all.sh --cluster "psql -h 127.0.0.1 -p 5432 -U postgres"

# 3. Connexion manuelle à une base
psql -h 127.0.0.1 -p 5433 -U postgres -d centre
```
