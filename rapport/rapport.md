# Rapport du Mini-Projet CABDD — Réseau de Capteurs Environnementaux (Variante A)

- **Module :** Concepts Avancés de Bases de Données (CABDD) — Dr S. Chabane - Mechiouri
- **Université de Béjaïa** — Faculté des Sciences Exactes — Département Informatique — **ING 4 GL (2026/2027)**
- **Binôme :** **Merzouk Amine** & **Megharba Samou**
- **Variante :** **Variante A** (Zone 1 : Béjaïa, Jijel | Zone 2 : Sétif, Bordj Bou Arréridj | Capteur spécifique : Hydrométrie | Partitions mensuelles | Bilan journalier XML)

---

## Introduction & Architecture des Scripts

Le projet implémente sous **PostgreSQL 18** la gestion complète d'un réseau national de 12 stations environnementales (36 capteurs) réparties en deux zones géographiques autonomes pilotées par un centre national.  
L'ensemble est reconstruit sans erreur sur une installation vierge par l'exécution séquentielle des scripts numérotés `sql/01_init_bases.sql` à `sql/10_tests_et_plans.sql`.

---

## Étape 1 — Modélisation Relationnelle-Objet (`centre`)

### 1.1 Choix des types composés (`t_position`, `t_qualite_air`, `t_hydrometrie`)
*(Section Merzouk Amine — à compléter après `sql/02_schema_ro.sql`)*
- Pourquoi regrouper `(latitude, longitude, altitude)` dans `t_position`, `(pm25, pm10, no2)` dans `t_qualite_air` et `(humidite, pluie)` dans `t_hydrometrie` plutôt que des colonnes isolées : cohésion sémantique d'une observation multi-composantes, manipulation atomique et passage direct aux fonctions métier.

### 1.2 Hiérarchie de capteurs (`INHERITS`), intégrité et comparaison Oracle vs PostgreSQL
*(Section Merzouk Amine — à compléter après `sql/02_schema_ro.sql`)*
- Généralisation `capteur` $\rightarrow$ `capteur_temperature`, `capteur_air`, `capteur_hydro` (`SELECT * FROM capteur` restitue les **36 capteurs**).
- Limites natives de `INHERITS` sous PostgreSQL (non-propagation automatique des `PRIMARY KEY`, `UNIQUE` et `FOREIGN KEY` aux tables filles) et verrouillage complet par contraintes `CHECK` + triggers PL/pgSQL.
- Comparaison avec la syntaxe objet d'Oracle (`CREATE TYPE ... UNDER`, `CREATE TABLE OF`, `REF` / `SCOPE IS`, `MEMBER FUNCTION`).

### 1.3 Chargement du référentiel CSV et opérations en base
*(Section Megharba Samou — `sql/03_operations_ro.sql` & `sql/04_referentiel_csv.sql`)*
- Référentiel chargé depuis les fichiers plats officiels : **12 stations**, **36 capteurs** (dont `BJ-02-A1` mis en service le `2026-02-02` et `JJ-02-T1` retiré le `2026-03-17`), et **6 seuils d'alerte**.
- Opérations sur objets :
  - `distance_km(t_position, t_position)` (Haversine) et `distance_stations_km('BJ-01', 'SE-01')` ;
  - `depasse_seuil_temperature`, `depasse_seuil_air`, `depasse_seuil_hydro` et `seuils_franchis` ;
  - `celsius_vers_fahrenheit`, `pluie_mm_vers_pouces` et `point_de_rosee`.

---

## Étape 2 — Échanges XML et Qualité des Données (100 % SQL)

### 2.1 Chargement de `lots_A.xml`, conservation brute et isolement des anomalies
*(Section Merzouk Amine — à compléter avec les captures d'exécution de `sql/05_chargement_xml.sql`)*

| Indicateur sur `data/lots_A.xml` | Effectif attendu / vérifié |
| :--- | :---: |
| Lots journaliers conservés dans `lot_brut` | **1 440** |
| **Total des mesures lues dans `lots_A.xml`** | **33 974** |
| **Mesures valides insérées en tables** | **33 280** |
| **Mesures rejetées dans `mesure_isolee`** | **694** |
| — dont `valeur_impossible` | 296 |
| — dont `valeur_manquante` | 194 |
| — dont `format_invalide` | 174 |
| — dont `capteur_inconnu` | 15 |
| — dont `doublon` | 15 |
| **Contrôle sans perte (`33 280 + 694 = 33 974`)** | **OK** |

- Réaction face à une erreur imprévue, distinction doublon vs nouvelle mesure, et intérêt de conserver `lot_brut` interrogeable en XPath.

### 2.2 Rapport XML « Bilan journalier » (Variante A)
*(Section Megharba Samou — `sql/06_rapport_xml.sql`)*
- Justification de la hiérarchie `<bilanJournalier debut="..." fin="...">` $\rightarrow$ `<jour>` $\rightarrow$ `<station>` $\rightarrow$ `<grandeur>` avec éléments `<min>`, `<max>`, `<moyenne>` et attribut `nbMesures`.
- Prise en compte stricte des dates de mise en service (`BJ-02-A1`) et de retrait (`JJ-02-T1`).
- *(Insérer ici un extrait commenté généré sur février 2026).*

---

## Étape 3 — Répartition entre `centre`, `zone1` et `zone2`

### 3.1 Identifiants uniques globaux et propagation du référentiel
*(Section Merzouk Amine — à compléter après `sql/07` & `sql/08_propagation_referentiel.sql`)*
- Séquences décalées (impaires sur `zone1`, paires sur `zone2`) garantissant zéro collision sans coordination centrale.
- Propagation automatique `centre` $\rightarrow$ `zone1`, `zone2` via `postgres_fdw` et triggers sur toute la hiérarchie ; analyse des modifications propagées et non propagées.

### 3.2 Partitionnement mensuel, transparence FDW et plans d'exécution
*(Section Megharba Samou — à compléter après `sql/07`, `sql/09` & `sql/10`)*
- Partitionnement `PARTITION BY RANGE (instant_mesure)` par mois dans `zone1` et `zone2`.
- Vues fédérées sur `centre` + routage automatique `INSTEAD OF INSERT` + exécution du Bilan journalier XML depuis `centre`.
- Plans `EXPLAIN (ANALYZE, VERBOSE)` commentés (requête ciblant **1 seule zone** et **1 seul mois**) et comportement lors de l'indisponibilité d'une zone.
