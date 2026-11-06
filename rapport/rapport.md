# Rapport du mini-projet — Réseau de capteurs environnementaux
## Variante A (hydrométrie, partitionnement mensuel, bilan journalier)

**Module :** Concepts avancés de BD — ING 4 GL 2026/2027
**SGBD :** PostgreSQL 16/18 · **Architecture :** 3 bases (`centre`, `zone1`, `zone2`)
**Données traitées :** 1 440 lots XML (12 stations × 120 jours), **34 576 mesures** reçues.

---

## Étape 1 — Modélisation du réseau (schéma relationnel-objet)

### 1.1 Objets composés
Trois types composés ont été définis (`sql/01_schema.sql`) :

- `type_position(latitude, longitude, altitude)` pour la position d'une station ;
- `type_air(pm25, pm10, no2)` pour une mesure de qualité de l'air ;
- `type_hydro(humidite, pluie)` pour une mesure d'hydrométrie (variante A).

**Pourquoi un type plutôt que des colonnes ?** Une position ou une mesure d'air forme *un tout sémantique* : on la manipule d'un bloc (`(pos).latitude`, `ROW(...)::type_air`), on la passe à une fonction (`distance_km(p1, p2)`), et sa cohérence interne (3 composantes toujours présentes ensemble) est garantie par le type lui-même. C'est exactement ce que la syntaxe Oracle (`OBJECT`, `VARRAY`) permettrait d'écrire nativement ; avec PostgreSQL, les *composite types* + la notation `(col).champ` jouent le même rôle.

### 1.2 Hiérarchie de capteurs (héritage de tables)
```
capteur (code, station_code, type, mise_en_service, retrait, etat)
├── capteur_temperature
├── capteur_air
└── capteur_hydro
```
`SELECT * FROM capteur` renvoie **les 36 capteurs quel que soit leur type** : la généralisation est réelle. Chaque table fille ajoute une contrainte `CHECK (type = '...')` qui empêche d'y insérer un capteur d'un autre type. La table `mesure` est également hiérarchisée (`mesure_temperature`, `mesure_air`, `mesure_hydro`).

### 1.3 Un schéma qui se protège seul
- **Valeur impossible** : `CHECK` sur chaque table fille — ex. `mesure_hydro` impose `humidite BETWEEN 0 AND 100`, `pluie BETWEEN 0 AND 1000` ; la base **refuse l'insert** (test 2 de `07_tests_integrite.sql` : `humidite=130` → `check_violation`).
- **Capteur inexistant** : `mesure.capteur_code REFERENCES capteur(code)` — la FK porte sur la table *mère*, donc tout niveau de la hiérarchie est accepté et tout capteur inconnu est refusé (test 1).
- **Cohérence croisée** : un trigger `verif_type_capteur()` refuse une mesure de température sur un capteur de type air (test 3).
- **Position invalide** : `CHECK` sur `station` (latitudes/longitudes/altitude bornées).

### 1.4 Opérations définies dans la base
- `distance_km(p1, p2)` — formule de Haversine sur les objets `type_position` (ex. BJ-01 ↔ JJ-01 = **64,084 km**) ;
- `depasse_seuil(capteur, grandeur, valeur)` — teste la valeur contre le référentiel `seuil` (borne min/max) ;
- `celsius_vers_fahrenheit(t)` et `mm_vers_cm(mm)` — conversions d'unité pour la variante A.

Toutes s'utilisent dans une requête SQL ordinaire, ex. :
```sql
SELECT c.code, v.grandeur, v.valeur, depasse_seuil(c.code, v.grandeur, v.valeur)
FROM vue_mesure_plat v JOIN capteur c ON c.code = v.capteur_code
WHERE depasse_seuil(c.code, v.grandeur, v.valeur);
```

### 1.5 Réponses aux questions de l'étape 1
- **Hiérarchie et intégrité des mesures :** oui — la FK vers la table mère couvre tous les descendants (vérifié par le test 1), et le trigger de type ferme la dernière faille (test 3).
- **Syntaxe Oracle :** `CREATE TYPE ... AS OBJECT`, `REF`, méthodes `MEMBER FUNCTION` auraient permis d'écrire les opérations *dans* le type. PostgreSQL n'a pas de méthodes sur les types composés ; on écrit des fonctions SQL qui *prennent* les objets en paramètre — c'est l'équivalent fonctionnel.

---

## Étape 2 — Faire entrer les données (XML, 100 % en SQL)

### 2.1 Chargement sans programme externe
`sql/03_lots_xml.sql` lit le fichier avec `pg_read_file()`, découpe les lots avec `xpath('/lots/lot', ...)`, et chaque `<mesure>` avec `xpath('/lot/mesure', ...)`. Aucun Python, aucune conversion préalable : tout est SQL (`INSERT ... SELECT` sur des `unnest(xpath(...))`).

### 2.2 Aucune mesure perdue — isolement 100 %
Chaque mesure est classée par un `CASE` de validation (ordre de priorité : capteur inconnu → format invalide → valeur manquante → valeur impossible → doublon) puis :
- valide → insérée dans la table typée correspondante ;
- corrompue → insérée dans `mesure_isolee` avec **son lot, sa forme XML d'origine et le motif**.

**Résultat obtenu :** `total_fichier = 34 576 = 34 560 valides + 16 isolées` → `controle_ok = t`.

| Motif | Nombre |
|---|---|
| valeur_impossible | 6 |
| valeur_manquante | 3 |
| format_invalide | 3 |
| capteur_inconnu | 2 |
| doublon | 2 |

### 2.3 Lots bruts interrogeables
La table `lot_brut` conserve chaque lot en `xml`. Exemples exécutés :
```sql
-- lots contenant une mesure du capteur BJ-01-T1
SELECT * FROM lot_brut
WHERE array_length(xpath('/lot/mesure[@capteur="BJ-01-T1"]', contenu), 1) > 0;
-- nombre de mesures par lot
SELECT id, station, array_length(xpath('/lot/mesure', contenu), 1) FROM lot_brut;
```

### 2.4 Rapport XML (bilan journalier, variante A)
`rapport_bilan_journalier(p_debut, p_fin)` (dans `04_rapport_xml.sql`) produit, par une seule requête :
```xml
<rapport type="bilan-journalier" variante="variante-A" periode_debut="2026-01-01" periode_fin="2026-01-31">
  <jour date="2026-01-01">
    <station code="BJ-01" wilaya="Béjaïa">
      <grandeur nom="humidite" min="15.00" max="79.60" moyenne="46.70" nb_mesures="8"/>
      <grandeur nom="temperature" min="2.50" max="28.50" moyenne="18.73" nb_mesures="8"/>
      ...
```
**Justification de la structure :** imbrication `jour → station → grandeur` car le bilan est *par jour, par station et par grandeur* ; les agrégats (min/max/moyenne/nb) sont des **attributs** de `<grandeur>` car ce sont des valeurs scalaires étiquetées, tandis que les entités (jour, station) sont des éléments portant leur identité en attribut (`date`, `code`).

### 2.5 Réponses aux questions de l'étape 2
- **Erreur imprévue :** le `CASE` renvoie `NULL` (valide) uniquement si tous les tests passent ; une erreur *non prévue* bascule dans le `CHECK` de la table cible à l'insert, qui lève une exception — le chargement d'un lot isolé ne fait jamais échouer les autres mesures (elles sont classées individuellement).
- **Doublon vs nouvelle mesure :** un doublon est une mesure dont le couple `(capteur, instant)` existe déjà (en base ou déjà vu dans le même lot) — on garde la première occurrence (`min(rid)`), les suivantes sont isolées avec le motif `doublon`.
- **Pourquoi garder les lots bruts :** les tables de mesures ont *perdu la forme d'origine* (après validation/aplatissage) ; les lots bruts servent de preuve, permettent de réinterroger le flux tel quel (capteur donné, comptage par lot) et de réparer manuellement une mesure isolée.

---

## Étape 3 — Répartir sans perdre la vue d'ensemble

### 3.1 Les trois bases
- `centre` : référentiel complet (seule base où il est modifié) + **vue transparente** sur toutes les mesures ;
- `zone1` / `zone2` : mesures de leur zone uniquement, **partitionnées par mois** (`mesure_2026_01` … `mesure_defaut`), copie locale du référentiel.

### 3.2 Partitionnement temporel (mensuel, variante A)
Dans chaque zone, `mesure` est `PARTITION BY RANGE (instant)` avec une partition par mois. **Preuve d'élagage** (plan exécuté sur `zone1`) :
```
EXPLAIN SELECT count(*), avg(valeur) FROM mesure
WHERE grandeur='humidite' AND instant >= '2026-02-01' AND instant < '2026-03-01';
→ Seq Scan on mesure_2026_02 mesure        -- SEULE la partition de février est lue
```
Une requête sur un mois ne parcourt donc que les données de ce mois.

### 3.3 Transparence pour le centre (postgres_fdw)
Depuis `centre`, des tables distantes (`z1.mesure`, `z2.mesure`, etc.) sont déclarées via `postgres_fdw` ; la vue `mesure` = `z1.mesure UNION ALL z2.mesure`. **Résultat :** `SELECT count(*) FROM mesure` depuis le centre renvoie **69 120 lignes** (les 34 560 mesures valides × leurs grandeurs) comme si tout était local. Répartition constatée pour mars 2026 : zone 1 = 1 488 températures, zone 2 = 1 488.

**Écriture transparente :** un trigger `INSTEAD OF INSERT` sur la vue `mesure` route la mesure vers la bonne zone (d'après la zone de la station du capteur) — test : `INSERT INTO mesure ... VALUES ('BJ-01-T1', ...)` atterrit physiquement dans `zone1` avec l'id `2000000000001`.

### 3.4 Référentiel propagé automatiquement
Des triggers `AFTER INSERT/UPDATE/DELETE` sur `station`, `capteur`, `seuil` (hérités par les tables filles) répliquent chaque modification vers `z1.*` et `z2.*`. **Test :** la station `BJ-04` ajoutée au centre apparaît aussitôt dans les deux zones (`centre=1, zone1=1, zone2=1`). Les mesures, elles, ne sont **pas** propagées (chaque zone garde l'autonomie de ses données).

### 3.5 Identifiants uniques sur tout le réseau
Schéma par plages : zone 1 → offset `0`, zone 2 → offset `10^12`, centre → offset `2×10^12` (séquence `seq_mesure_centre`). Deux mesures créées indépendamment dans deux zones ne peuvent jamais partager leur id. **Vérifié :** `count(*) = count(DISTINCT (capteur_code, instant, grandeur)) = 69 121`.

### 3.6 Rapport XML depuis le centre
`06_rapport_centre.sql` réutilise `rapport_bilan_journalier()` telle quelle (la vue `vue_mesure_plat` a été redéfinie sur la vue distribuée) : le rapport de février 2026 est produit depuis `centre` sur les données réparties.

### 3.7 Réponses aux questions de l'étape 3
- **Requête centre sur 1 zone + 1 mois :** côté centre, le plan montre `Foreign Scan` vers la zone visée ; côté zone, l'élagage ne garde que la partition du mois (cf. §3.2).
- **Zone indisponible :** la requête du centre échoue sur la partie distante concernée (FDW = accès distant synchrone) ; l'autre zone reste interrogeable individuellement (`SELECT ... FROM z1.mesure`).
- **Ce qui est propagé :** stations, capteurs, seuils (insert/update/delete). **Ce qui ne l'est pas :** les mesures (restent locales à leur zone) et les lots bruts/mesures isolées (spécifiques au centre).

---

## Résultats récapitulatifs
| Indicateur | Valeur |
|---|---|
| Mesures reçues (fichier XML) | 34 576 |
| Mesures valides chargées | 34 560 |
| Mesures isolées (100 % des corrompues) | 16 |
| Contrôle valides + isolées = total | ✅ 34 576 = 34 576 |
| Stations / capteurs / seuils | 12 / 36 / 8 |
| Lignes vues du centre (réseau entier) | 69 120 (+1 de test) |
| Insertions refusées par la base (tests) | 3/3 ✅ |
| Rapport XML généré depuis le centre | ✅ (janvier et février 2026) |

## Limites et améliorations possibles
- Le chargement XML par `xpath` en masse est fonctionnel mais peut être accéléré (table `xmltable` + index) sur de très gros volumes.
- Si une zone tombe, aucune dégradation automatique : on pourrait ajouter une vue de secours ou de la réplication logique en complément du FDW.
