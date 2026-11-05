# Contrat de Conception Partagé — Variante A
**Binôme :** Merzouk Amine & Megharba Samou  
**Module :** Concepts Avancés de Bases de Données (ING 4 GL — Université de Béjaïa)

Ce document fige les noms des bases, types composés, tables et fonctions afin que **Merzouk Amine** et **Megharba Samou** puissent développer leurs scripts SQL **en parallèle sans conflit ni incompatibilité**.

---

## 1. Les 3 bases PostgreSQL (Étape 3)

| Nom exact de la base | Rôle | Wilayas couvertes (Variante A) |
| :--- | :--- | :--- |
| `centre` | Référentiel maître + vue globale transparente des mesures + génération du rapport XML global | Toutes (vue fédérée) |
| `zone1` | Copie locale du référentiel + mesures partitionnées **par mois** de la Zone 1 | **Béjaïa, Jijel** |
| `zone2` | Copie locale du référentiel + mesures partitionnées **par mois** de la Zone 2 | **Sétif, Bordj Bou Arréridj** |

*(Remarque : aux Étapes 1 et 2, tout s'exécute d'abord dans `centre` ou un schéma local avant bascule des mesures vers `zone1` et `zone2` à l'Étape 3 ; lors d'une exécution complète de `01` à `10`, le référentiel vit sur `centre`, est propagé vers `zone1`/`zone2`, et les mesures sont stockées dans `zone1`/`zone2`.)*

---

## 2. Types composés et énumérations (Étape 1 — Merzouk Amine)

### Énumérations (`CREATE TYPE ... AS ENUM`)
- `type_capteur_enum` : `'temperature'`, `'air'`, `'hydro'`
- `borne_seuil_enum` : `'min'`, `'max'` *(à ajuster selon les valeurs exactes de `seuils_A.csv` : `'minimum'`/`'maximum'` ou `'min'`/`'max'`)*
- `motif_rejet_enum` :
  1. `'valeur_impossible'`
  2. `'valeur_manquante'`
  3. `'format_invalide'`
  4. `'capteur_inconnu'`
  5. `'doublon'`

### Types composés (`CREATE TYPE ... AS (...)`)
1. **`t_position`** *(utilisé dans `station`)* :
   - `latitude NUMERIC(9,6)`
   - `longitude NUMERIC(9,6)`
   - `altitude NUMERIC(7,2)`
2. **`t_qualite_air`** *(utilisé dans les mesures de qualité de l'air)* :
   - `pm25 NUMERIC(7,2)` *(en µg/m³, $\ge 0$)*
   - `pm10 NUMERIC(7,2)` *(en µg/m³, $\ge 0$ et cohérent avec `pm25`)*
   - `no2 NUMERIC(7,2)` *(en µg/m³, $\ge 0$)*
3. **`t_hydrometrie`** *(spécifique **Variante A**, utilisé dans les mesures hydrométriques)* :
   - `humidite NUMERIC(5,2)` *(en %, entre `0` et `100`)*
   - `pluie NUMERIC(7,2)` *(en mm tombés depuis la mesure précédente, $\ge 0$)*

---

## 3. Tables du Référentiel et Hiérarchie de Capteurs

### Table `station`
- `code_station VARCHAR(10) PRIMARY KEY` *(ex. `'BJ-01'`)*
- `nom VARCHAR(100) NOT NULL`
- `wilaya VARCHAR(60) NOT NULL`
- `zone SMALLINT NOT NULL CHECK (zone IN (1, 2))`
- `position t_position NOT NULL` *(avec contrainte `CHECK` validant latitude $\in [-90, 90]$, longitude $\in [-180, 180]$, altitude plausible)*

### Hiérarchie `capteur` (`INHERITS`)
- Table mère **`capteur`** :
  - `code_capteur VARCHAR(15) PRIMARY KEY` *(ex. `'BJ-01-T1'`)*
  - `code_station VARCHAR(10) NOT NULL REFERENCES station(code_station)`
  - `type_capteur type_capteur_enum NOT NULL`
  - `date_mise_en_service DATE NOT NULL`
  - `date_retrait DATE` *(NULL si toujours en service, `CHECK (date_retrait IS NULL OR date_retrait >= date_mise_en_service)`)*
  - `etat VARCHAR(30) NOT NULL`
- Tables filles héritant de `capteur` (`INHERITS (capteur)`) :
  - **`capteur_temperature`** (`CHECK (type_capteur = 'temperature')`, attributs métrologiques propres éventuels : unité `'°C'`, plage physique)
  - **`capteur_air`** (`CHECK (type_capteur = 'air')`, composantes suivies `'PM2.5, PM10, NO2'`)
  - **`capteur_hydro`** (`CHECK (type_capteur = 'hydro')`, composantes suivies `'humidite (%), pluie (mm)'`)
- **Attention PostgreSQL (`INHERITS`)** : Merzouk Amine implémente les triggers garantissant :
  1. L'unicité globale de `code_capteur` sur toute la hiérarchie `capteur*`.
  2. La vérification d'intégrité référentielle lorsqu'une mesure référence un capteur présent dans une table fille.

### Table `seuil_alerte`
- `id_seuil SERIAL PRIMARY KEY`
- `type_capteur type_capteur_enum NOT NULL`
- `grandeur VARCHAR(30) NOT NULL` *(`'temperature'`, `'pm25'`, `'pm10'`, `'no2'`, `'humidite'`, `'pluie'`)*
- `borne borne_seuil_enum NOT NULL`
- `valeur NUMERIC(10,2) NOT NULL`
- `unite VARCHAR(20) NOT NULL`

---

## 4. Tables des Mesures, Lots Bruts et Espace d'Isolement

### Stratégie d'identifiants uniques sur tout le réseau (Étape 3 — Merzouk Amine)
Pour garantir que deux mesures créées indépendamment dans `zone1` et `zone2` n'aient **jamais** le même `id_mesure` :
- Dans `zone1` : `CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH 1;` *(identifiants impairs : 1, 3, 5, ...)*
- Dans `zone2` : `CREATE SEQUENCE seq_mesure INCREMENT BY 2 START WITH 2;` *(identifiants pairs : 2, 4, 6, ...)*

### Tables de mesures (partitionnées par mois dans `zone1` et `zone2` sur `instant_mesure`)
Trois tables typées (ou hiérarchie de mesures) reliées au type de capteur correspondant :
1. **`mesure_temperature`** : `(id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP, temperature NUMERIC(5,2), id_lot INT)` — `UNIQUE (code_capteur, instant_mesure)`
2. **`mesure_air`** : `(id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP, valeurs_air t_qualite_air, id_lot INT)` — `UNIQUE (code_capteur, instant_mesure)`
3. **`mesure_hydro`** : `(id_mesure BIGINT, code_capteur VARCHAR(15), instant_mesure TIMESTAMP, valeurs_hydro t_hydrometrie, id_lot INT)` — `UNIQUE (code_capteur, instant_mesure)`

### Conservation XML et Isolement (Étape 2 — Merzouk Amine)
- **`lot_brut`** :
  - `id_lot BIGSERIAL PRIMARY KEY`
  - `code_station VARCHAR(10)`
  - `date_envoi TIMESTAMP`
  - `contenu_xml XML NOT NULL` *(l'élément `<lot ...>...</lot>` d'origine conservé tel quel)*
- **`mesure_isolee`** :
  - `id_rejet BIGSERIAL PRIMARY KEY`
  - `id_lot BIGINT REFERENCES lot_brut(id_lot)`
  - `code_station_lot VARCHAR(20)`
  - `mesure_xml XML NOT NULL` *(forme XML d'origine de `<mesure .../>`)*
  - `motif motif_rejet_enum NOT NULL`
  - `detail_motif TEXT`
  - `date_rejet TIMESTAMP DEFAULT CURRENT_TIMESTAMP`

---

## 5. Signatures des Opérations et du Rapport XML (Megharba Samou)

1. **Distance entre deux stations (en km)** :
   - `distance_km(pos1 t_position, pos2 t_position) RETURNS NUMERIC`
   - Surcharge pratique : `distance_stations_km(code_st1 VARCHAR, code_st2 VARCHAR) RETURNS NUMERIC`
2. **Test de dépassement de seuil** :
   - `depasse_seuil_temperature(val NUMERIC) RETURNS BOOLEAN`
   - `depasse_seuil_air(val t_qualite_air) RETURNS BOOLEAN`
   - `depasse_seuil_hydro(val t_hydrometrie) RETURNS BOOLEAN`
   *(ou fonction unifiée retournant la liste des seuils franchis)*
3. **Conversions d'unités (adaptées à la Variante A)** :
   - `celsius_vers_fahrenheit(temp_c NUMERIC) RETURNS NUMERIC`
   - `hydrometrie_imp(val t_hydrometrie) RETURNS RECORD` *(pluie `mm` $\rightarrow$ `pouces`, + calcul du point de rosée ou indice humidex combinant température et `t_hydrometrie`)*
4. **Rapport XML Bilan Journalier (Variante A)** :
   - `generer_bilan_journalier_xml(p_date_debut DATE, p_date_fin DATE) RETURNS XML`
   - Fonctionne localement à l'Étape 2, puis sur les vues fédérées de `centre` à l'Étape 3.
