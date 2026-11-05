# Plan du Rapport Final (Maximum 10 pages) — Variante A
**Binôme :** Merzouk Amine & Megharba Samou  
**Règle d'or de l'énoncé :** *Le rapport fait 10 pages au maximum, est organisé selon les 3 étapes, présente les choix de conception, répond aux questions de chaque étape et donne les résultats obtenus. **Il ne recopie pas les scripts SQL.***

---

## Répartition de la rédaction (5 pages Amine / 5 pages Samou)

### Page 1 (0,5 page) — Introduction & Architecture Générale *(Merzouk Amine & Megharba Samou)*
- Rappel synthétique de la **Variante A** :
  - **Zone 1** : Béjaïa, Jijel | **Zone 2** : Sétif, Bordj Bou Arréridj (12 stations, 36 capteurs).
  - Capteur spécifique : **Hydrométrie** (`humidite` en %, `pluie` en mm).
  - Partitionnement temporel : **par mois**.
  - Rapport XML : **Bilan journalier** (`min`, `max`, `moyenne`, `nb_mesures` par jour, station et grandeur).
- Vue d'ensemble de la chaîne de scripts numérotés (`01` à `10`).

---

### Section 1 — Modélisation Relationnelle-Objet (~3 pages)

#### 1.1 Choix des types composés (`t_position`, `t_qualite_air`, `t_hydrometrie`) *(Merzouk Amine — ~1 page)*
- **Question de l'énoncé :** *Pourquoi avoir regroupé telle information dans un type plutôt que dans plusieurs colonnes ?*
- Éléments de réponse : cohésion sémantique d'une observation multi-composantes (ex. une mesure de qualité de l'air `PM2.5/PM10/NO2` ou hydrométrique `humidité/pluie` forme un vecteur indissociable ; une position 3D `lat/lon/alt` se passe d'un seul bloc aux fonctions géométriques comme `distance_km`).

#### 1.2 Hiérarchie de capteurs, intégrité et comparaison Oracle vs PostgreSQL *(Merzouk Amine — ~1 page)*
- **Question 1 de l'énoncé :** *Votre hiérarchie garantit-elle réellement l'intégrité des mesures, et comment l'avez-vous vérifié ?*
  - Expliquer la limite native de `INHERITS` dans PostgreSQL (les contraintes `PRIMARY KEY`, `UNIQUE` et `FOREIGN KEY` de la table mère `capteur` ne couvrent pas automatiquement les tables filles `capteur_temperature`, `capteur_air`, `capteur_hydro`) et les **triggers PL/pgSQL** mis en place + résultats des tests d'insertion refusés.
- **Question 2 de l'énoncé :** *Qu'est-ce que la syntaxe Oracle vue en cours aurait permis d'écrire plus simplement, et qu'avez-vous dû faire autrement avec PostgreSQL ?*
  - Comparer `CREATE TYPE ... UNDER ... NOT FINAL`, tables d'objets (`CREATE TABLE OF`), références typées `REF` avec `SCOPE IS` et `MEMBER FUNCTION` d'Oracle avec `CREATE TYPE` composite + `INHERITS` + fonctions SQL/PLpgSQL externes + triggers d'intégrité dans PostgreSQL.

#### 1.3 Opérations en base et transformation du référentiel CSV *(Megharba Samou — ~1 page)*
- Passage du format plat CSV (`stations_A.csv`, `capteurs_A.csv`, `seuils_A.csv`) aux objets composés et sous-tables de capteurs.
- Présentation et résultats d'exécution des opérations :
  1. `distance_km` (formule de Haversine entre deux stations de Béjaïa/Sétif).
  2. Détection de dépassement des seuils du référentiel.
  3. Conversions d'unités (`°C` $\rightarrow$ `°F`, `mm` $\rightarrow$ `pouces`, point de rosée / humidex).

---

### Section 2 — Échanges XML et Qualité des Données (~3 pages)

#### 2.1 Chargement 100 % SQL de `lots_A.xml` et bilan d'isolement *(Merzouk Amine — ~1,5 page)*
- Tableau récapitulatif obligatoire des résultats obtenus sur `lots_A.xml` :
  - Nombre total de mesures dans le fichier XML ;
  - Nombre de mesures valides insérées (ventilées par type : température, air, hydrométrie) ;
  - Nombre de mesures isolées ventilées selon les **5 motifs** (`valeur_impossible`, `valeur_manquante`, `format_invalide`, `capteur_inconnu`, `doublon`) ;
  - Vérification de l'égalité stricte : `valides + isolées = total`.
- **Question 1 de l'énoncé :** *Comment votre chargement réagit-il si l'on ajoute au fichier une mesure contenant une erreur que vous n'avez pas prévue ?* (Bloc `EXCEPTION WHEN OTHERS` en PL/pgSQL ou capture sécurisée isolant la mesure sans annuler tout le lot).
- **Question 2 de l'énoncé :** *Comment distinguez-vous un doublon d'une nouvelle mesure ?* (Clé métier `(code_capteur, instant_mesure)` : à la fois entre deux lots distincts et à l'intérieur d'un même lot via `ROW_NUMBER() OVER (PARTITION BY capteur, instant ...)`).
- **Question 3 de l'énoncé :** *Pourquoi conserver les lots bruts alors que les mesures sont déjà en tables ?* (Traçabilité/audit légal, rejeu après correction d'une règle métier ou ajout tardif d'un capteur au référentiel, interrogation XPath directe).

#### 2.2 Génération du rapport XML « Bilan journalier » (Variante A) *(Megharba Samou — ~1,5 page)*
- Justification de la structure XML retenue (choix entre éléments et attributs : attributs pour les identifiants/dates/unités compacts, éléments imbriqués pour la hiérarchie `<bilanJournalier> -> <jour> -> <station> -> <grandeur>`).
- Prise en compte des dates de mise en service et de retrait des capteurs.
- **Extrait commenté** du document XML généré sur une période de test.

---

### Section 3 — Répartition entre `centre`, `zone1` et `zone2` (~3,5 pages)

#### 3.1 Propagation du référentiel et unicité globale des identifiants *(Merzouk Amine — ~1,5 page)*
- Mécanisme d'identifiants uniques sans coordination centrale (séquences impaires sur `zone1`, paires sur `zone2`).
- Architecture de propagation `centre` $\rightarrow$ `zone1`, `zone2`.
- **Question de l'énoncé :** *Quelles modifications du référentiel sont propagées, et lesquelles ne le sont pas ?* (INSERT/UPDATE sur stations, capteurs, états, dates de retrait, seuils vs suppressions bloquées par des mesures existantes ou changements DDL de structure).

#### 3.2 Partitionnement mensuel, transparence FDW et plans d'exécution *(Megharba Samou — ~2 pages)*
- Organisation par mois dans `zone1` et `zone2` (`PARTITION BY RANGE (instant_mesure)`) + vue globale sur `centre` et trigger `INSTEAD OF INSERT` routant automatiquement chaque mesure vers sa zone.
- **Question 1 de l'énoncé :** *Que se passe-t-il, concrètement, quand le centre exécute une requête sur une seule zone et un seul mois ? Montrez-le avec les plans d'exécution.*
  - Commenter la sortie de `EXPLAIN (ANALYZE, VERBOSE)` : filtrage distant (`Remote SQL` pushdown via `postgres_fdw`), élimination de la zone non concernée si contrainte/vue partitionnée, et *Partition Pruning* mensuel sur la zone cible (1 seule partition mensuelle lue au lieu de toutes).
- **Question 2 de l'énoncé :** *Que deviennent les requêtes du centre si une zone est indisponible ?*
  - Montrer par l'expérience (arrêt/coupure du serveur distant d'une zone) ce qui échoue (vue globale parcourant les deux zones, rapport global, propagation synchrone) et dans quel cas une requête ciblée peut ou non aboutir.
- Validation du rapport XML Bilan journalier exécuté depuis `centre`.
