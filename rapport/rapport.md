# Rapport du Mini-Projet CABDD — Réseau de Capteurs Environnementaux (Variante A)

- **Module :** Concepts Avancés de Bases de Données (CABDD) — Dr S. Chabane - Mechiouri
- **Université de Béjaïa** — Faculté des Sciences Exactes — Département Informatique — **ING 4 GL (2026/2027)**
- **Binôme :** **Merzouk Amine** & **Megharba Samou**
- **Variante :** **Variante A** (Zone 1 : Béjaïa, Jijel | Zone 2 : Sétif, Bordj Bou Arréridj | Capteur spécifique : Hydrométrie | Partitions mensuelles | Bilan journalier XML)

---

## Introduction & Architecture des Scripts

Ce mini-projet met en œuvre sous **PostgreSQL 18** la base de données d'un réseau national de surveillance environnementale comptant **12 stations** et **36 capteurs** répartis sur quatre wilayas et deux zones autonomes (`zone1` : Béjaïa, Jijel ; `zone2` : Sétif, Bordj Bou Arréridj), fédérées par une base centrale (`centre`).  
L'intégralité du système est reconstruite sans erreur sur une installation vierge par l'exécution ordonnée des dix scripts `sql/01_init_bases.sql` à `sql/10_tests_et_plans.sql`.

---

## Étape 1 — Modélisation Relationnelle-Objet (`centre`)

### 1.1 Choix des types composés (`t_position`, `t_qualite_air`, `t_hydrometrie`)
Plutôt que d'éclater les grandeurs en colonnes indépendantes comme dans un schéma relationnel plat, nous avons défini trois types composés (`CREATE TYPE`) regroupant les attributs qui forment un **tout physique indissociable** :
1. **`t_position(latitude, longitude, altitude)`** dans `station` : une localisation tridimensionnelle n'a de sens géographique que complète. La représenter comme un seul objet permet de valider sa cohérence d'un bloc et de la passer directement comme argument unique à l'opération `distance_km(pos1, pos2)`.
2. **`t_qualite_air(pm25, pm10, no2)`** dans `mesure_air` : un relevé tri-horaire d'un analyseur d'air produit simultanément trois concentrations en $\mu\text{g/m}^3$. Les encapsuler garantit qu'une mesure d'air ne peut pas être partiellement renseignée et s'évalue d'un seul bloc face aux seuils (`depasse_seuil_air`).
3. **`t_hydrometrie(humidite, pluie)`** dans `mesure_hydro` *(spécifique Variante A)* : associe l'humidité relative instantanée ($\%$) et le cumul pluviométrique ($\text{mm}$) relevés au même instant par la sonde hydrométrique.

En revanche, l'identifiant du capteur, l'instant de mesure et le lot d'origine restent des colonnes relationnelles de la table mère `mesure`, car ils servent de clés d'indexation, d'unicité temporelle et de partitionnement à l'Étape 3.

### 1.2 Hiérarchie de capteurs, intégrité des mesures et comparaison Oracle vs PostgreSQL

#### Architecture d'héritage et auto-protection
La généralisation est modélisée par deux hiérarchies parallèles via le mécanisme **`INHERITS`** de PostgreSQL :
- **`capteur`** (table mère : code, station, type, dates de mise en service et de retrait, état) spécialisée en **`capteur_temperature`** (unité, plage thermique), **`capteur_air`** (polluants suivis, unité) et **`capteur_hydro`** (unités d'humidité/pluie, pas de cumul de 3 h). Interroger `SELECT * FROM capteur` restitue polymorphiquement les **36 capteurs**.
- **`mesure`** (table mère : `id_mesure`, `code_capteur`, `instant_mesure`, `id_lot`) spécialisée en **`mesure_temperature`**, **`mesure_air`** et **`mesure_hydro`**, chacune dotée de contraintes `CHECK` refusant dès l'insertion toute valeur physiquement impossible (ex. humidité hors $[0, 100]\,\%$, pluie $< 0$, concentrations négatives, température hors $[-60, 60]\,^\circ\text{C}$).

#### Garantie réelle de l'intégrité et vérification
Sous PostgreSQL, l'héritage `INHERITS` présente une **limite structurelle connue** : les contraintes `PRIMARY KEY`, `UNIQUE` et `FOREIGN KEY` définies sur une table mère ne se propagent pas aux tables filles, et une clause `REFERENCES capteur(code_capteur)` ne vérifie que la table physique mère `ONLY capteur` (vide puisque les capteurs sont insérés dans les sous-tables filles).  
Pour garantir une intégrité **réelle et sans faille**, nous avons combiné :
1. Des clés primaires, contraintes `UNIQUE (code_capteur, instant_mesure)` et clés étrangères vers `station` déclarées explicitement sur chaque table fille ;
2. Trois triggers PL/pgSQL transversaux : `fn_unicite_globale_capteur` (empêchant qu'un même `code_capteur` apparaisse dans deux sous-tables différentes), `fn_integrite_mesure_capteur` (vérifiant à chaque insertion/mise à jour de mesure que le capteur existe dans la hiérarchie `capteur*` **et** que son type correspond exactement à la sous-table de mesure visée) et `fn_protection_suppression_capteur` (interdisant de supprimer un capteur référencé par des mesures).
3. **Vérification expérimentale (`04_referentiel_csv.sql`)** : quatre tests automatisés en blocs transactionnels prouvent le rejet effectif par le SGBD d'un capteur sans station (`foreign_key_violation`), d'une latitude à `999` (`check_violation`), d'une humidité à `130 %` (`check_violation`) et d'une mesure rattachée à un capteur inexistant `XX-00-H9` (`foreign_key_violation`).

#### Comparaison entre la syntaxe Oracle vue en cours et PostgreSQL
Avec le modèle objet-relationnel d'**Oracle**, l'écriture aurait été plus directe sur quatre points :
- **Sous-typage d'objets (`CREATE TYPE t_capteur_hydro UNDER t_capteur` avec `NOT FINAL`)** et **tables d'objets (`CREATE TABLE capteur OF t_capteur`)** : Oracle stocke nativement toute la hiérarchie dans une table polymorphe unique munie d'un index de clé primaire global, sans nécessiter de triggers d'unicité inter-tables.
- **Associations typées par pointeurs `REF` et contrainte `SCOPE IS capteur`** : remplacent les clés étrangères relationnelles et fonctionnent sur tous les sous-types d'objets.
- **Méthodes encapsulées (`MEMBER FUNCTION distance_km`, `MEMBER FUNCTION depasse_seuil`)** attachées directement à la définition du type objet (`s1.position.distance_km(s2.position)`), tandis que sous PostgreSQL `CREATE TYPE` ne supporte que des attributs de données, obligeant à définir des fonctions SQL/PLpgSQL externes prenant le type composé en paramètre.

### 1.3 Chargement du référentiel CSV et opérations en base
*(Section Megharba Samou — `sql/03_operations_ro.sql` & `sql/04_referentiel_csv.sql`)*
- Référentiel chargé depuis les trois fichiers plats officiels : **12 stations**, **36 capteurs** (12 par type, incluant `BJ-02-A1` mis en service le `2026-02-02` et `JJ-02-T1` retiré le `2026-03-17` à l'état `hors_service`), et **6 seuils d'alerte**.
- Opérations sur objets : `distance_km` / `distance_stations_km` (Haversine), `depasse_seuil_*` / `seuils_franchis` (tenant compte de la grandeur `'valeur'` pour la température dans `seuils_A.csv`), `celsius_vers_fahrenheit`, `pluie_mm_vers_pouces` et `point_de_rosee`.

---

## Étape 2 — Échanges XML et Qualité des Données (100 % SQL)

### 2.1 Chargement de `lots_A.xml`, conservation brute et isolement des anomalies

Le script `sql/05_chargement_xml.sql` lit `data/lots_A.xml` intégralement en SQL/psql (`\lo_import` + `XMLPARSE DOCUMENT` + `XMLTABLE`), sans aucun script externe. Chaque élément `<lot>` est d'abord archivé tel quel dans `lot_brut`, puis ses éléments `<mesure>` sont qualifiés selon un ordre de priorité déterministe.

#### Bilan chiffré exact obtenu sur `data/lots_A.xml`

| Indicateur de chargement | Effectif | Détail |
| :--- | :---: | :--- |
| Lots journaliers archivés dans `lot_brut` | **1 440** | 12 stations $\times$ 120 jours (01/01 $\rightarrow$ 30/04/2026) |
| **Total des mesures extraites du XML** | **33 974** | Compté directement en XPath sur `lot_brut` |
| **Mesures valides chargées (`mesure*`)** | **33 280** | `10 952` temp. + `11 043` air + `11 285` hydro |
| **Mesures isolées (`mesure_isolee`)** | **694** | Avec lot, XML d'origine et motif précis |
| — `valeur_impossible` | **296** | Ex. `999.9`, `-300.0`, `-9999.0 °C`, humidité `-5 %` / `140 %`, pluie ou PM $< 0$ |
| — `valeur_manquante` | **194** | Attribut attendu (`valeur`, `pluie`, `no2`, `pm25`…) absent ou vide |
| — `format_invalide` | **174** | Virgule décimale (`84,0`, `14,9`) ou date invalide (`2026-01-32`, `T46:00:00`) |
| — `capteur_inconnu` | **15** | Capteurs hors référentiel (`JJ-05-H1`, `BJ-01-T2`, `SE-08-A1`…) |
| — `doublon` | **15** | Couple `(capteur, instant)` déjà reçu plus tôt |
| **Vérification `valides + isolées = total`** | **33 974 = 33 974** | **Aucune mesure perdue (`aucune_mesure_perdue = true`)** |

#### Réponses aux questions de l'Étape 2
1. **Réaction face à une mesure contenant une erreur non prévue :** `charger_lots_xml()` combine une qualification préventive et un filet transactionnel PL/pgSQL (`BEGIN ... EXCEPTION WHEN others`). Si le lot contient une anomalie imprévue qui franchit le filtre initial mais échoue à l'insertion (contrainte interne, dépassement numérique…), le bloc bascule automatiquement en insertion unitaire encadrée par `EXCEPTION WHEN others` : **seule la mesure fautive est capturée et envoyée dans `mesure_isolee`** avec le message PostgreSQL (`SQLERRM`), sans interrompre le chargement des autres mesures valides.
2. **Distinction entre un doublon et une nouvelle mesure :** Une mesure est identifiée métier par le couple naturel **`(code_capteur, instant_mesure)`** (un capteur ne produit qu'un relevé par échéance tri-horaire). Une mesure valide sur les critères 1 à 4 est marquée `doublon` soit si ce couple existe déjà dans `mesure` (renvoi d'un lot antérieur), soit si son rang `ROW_NUMBER() OVER (PARTITION BY capteur, instant ORDER BY rid)` au sein du fichier en cours est $> 1$ (seule la première occurrence est insérée, les suivantes sont isolées).
3. **Intérêt de conserver les lots bruts alors que les mesures sont en tables :** (a) **Audit et preuve d'origine** non altérée de ce qu'a réellement transmis chaque station ; (b) **Capacité de rejeu** : si un capteur était temporairement non déclaré lors de la réception nocturne (`capteur_inconnu`) puis ajouté au référentiel le lendemain, on peut retraiter le lot brut ; (c) **Interrogation XPath directe** (`lots_contenant_capteur`, `compter_mesures_par_lot`) y compris sur les lots comportant des mesures rejetées absentes des tables relationnelles.

### 2.2 Rapport XML « Bilan journalier » (Variante A)
*(Section Megharba Samou — `sql/06_rapport_xml.sql`)*
- Justification de la structure XML `<bilanJournalier>` $\rightarrow$ `<jour>` $\rightarrow$ `<station>` $\rightarrow$ `<grandeur>` (attributs d'identification compacts + sous-éléments `<min>`, `<max>`, `<moyenne>`).
- Filtrage selon la période d'activité réelle des capteurs (`date_mise_en_service <= jour < date_retrait`).
- *(Insérer ici un extrait XML généré par `generer_bilan_journalier_xml`).*

---

## Étape 3 — Répartition entre `centre`, `zone1` et `zone2`

### 3.1 Identifiants uniques globaux et propagation du référentiel

#### Unicité des identifiants sans coordination centrale
Pour empêcher toute collision d'`id_mesure` entre des insertions autonomes dans `zone1` et `zone2` sans dépendre d'un serveur central de séquences (qui briserait l'autonomie des zones en cas de coupure réseau), nous utilisons un **partitionnement arithmétique pair/impair** :
- `zone1` utilise `CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH 1` $\rightarrow$ génère uniquement des identifiants **impairs** ($1, 3, 5, \dots$) ;
- `zone2` utilise `CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH 2` $\rightarrow$ génère uniquement des identifiants **pairs** ($2, 4, 6, \dots$).  
Les ensembles $2\mathbb{N}+1$ et $2\mathbb{N}+2$ étant disjoints, deux mesures créées indépendamment ne peuvent jamais porter le même identifiant, y compris lorsqu'une insertion lancée depuis `centre` est routée vers sa zone cible.

#### Mécanisme de propagation et périmètre des modifications propagées
Dans `sql/08_propagation_referentiel.sql`, `centre` monte les tables du référentiel de `zone1` et `zone2` via `postgres_fdw` (`z1_ref`, `z2_ref`). Comme PostgreSQL ne propage pas les triggers le long d'une hiérarchie `INHERITS`, les triggers `AFTER INSERT OR UPDATE OR DELETE` sont attachés explicitement sur `station`, `seuil_alerte`, `capteur` **ainsi que sur chacune des trois tables filles** (`capteur_temperature`, `capteur_air`, `capteur_hydro`). La synchronisation procède par **`UPDATE` en place suivi d'un `INSERT` si absent** (et non `DELETE` + `INSERT`), ce qui préserve les clés étrangères des mesures déjà stockées dans les zones.

- **Modifications propagées automatiquement :**
  - Ajout ou mise à jour d'une **station** (nom, wilaya, zone, position `t_position`) ;
  - Ajout d'un **capteur** (quel que soit son sous-type) et toute modification de son cycle de vie (`etat` passant à `hors_service`, renseignement d'une `date_retrait`, rectification de `date_mise_en_service`) ;
  - Ajout, ajustement ou suppression d'un **seuil d'alerte** ;
  - Suppression d'une station ou d'un capteur **uniquement s'il ne possède encore aucune mesure** dans les zones.
- **Modifications NON propagées :**
  - Les **suppressions de stations ou de capteurs ayant déjà des mesures locales** dans `zone1` ou `zone2` (bloquées par l'intégrité référentielle locale de la zone, ce qui annule proprement la transaction distribuée et protège l'historique) ;
  - Les **attributs métrologiques propres aux sous-tables filles** si une zone utilise une table `capteur` aplatie, ainsi que toute **évolution de structure DDL** (`ALTER TABLE`, nouveaux types composés), que `postgres_fdw` ne réplique jamais automatiquement ;
  - Les tables locales au centre (`lot_brut`, `mesure_isolee`) qui n'appartiennent pas au référentiel distribué.

### 3.2 Partitionnement mensuel, transparence FDW et plans d'exécution
*(Section Megharba Samou — à compléter après `sql/07`, `sql/09` & `sql/10`)*
- Organisation mensuelle `PARTITION BY RANGE (instant_mesure)` dans `zone1` et `zone2`.
- Vue globale transparente sur `centre`, routage automatique `INSTEAD OF INSERT` et génération du Bilan journalier XML depuis `centre`.
- Analyse commentée du plan `EXPLAIN (ANALYZE, VERBOSE)` sur **une seule zone et un seul mois** (*Foreign Scan* ciblé + *Partition Pruning* mensuel) et comportement lorsque l'une des deux zones est indisponible.
