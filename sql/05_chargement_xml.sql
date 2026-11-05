-- ============================================================================
-- Script 05 : Chargement 100 % SQL des lots XML & Isolement (Étape 2)
-- Mini-projet CABDD (ING 4 GL) — Variante A (valeurs en attributs XML)
-- Binôme : Merzouk Amine & Megharba Samou
-- Responsable principal : Merzouk Amine
-- ============================================================================

\connect centre

-- ----------------------------------------------------------------------------
-- 1. Lecture brute de data/lots_A.xml et conservation des lots d'origine
-- ----------------------------------------------------------------------------
-- Format Variante A :
--   <lots>
--     <lot station="BJ-01" envoi="2026-02-15T00:05:00">
--       <mesure capteur="BJ-01-T1" instant="..." type="temperature" valeur="14.6"/>
--       <mesure capteur="BJ-01-A1" instant="..." type="air" pm25="16.7" pm10="37.2" no2="22.9"/>
--       <mesure capteur="BJ-01-H1" instant="..." type="hydro" humidite="55" pluie="0.0"/>
--     </lot>
--   </lots>
--
-- TODO (Merzouk Amine) :
--   - Charger le document XML complet en pur SQL (pg_read_file / XMLPARSE DOCUMENT)
--   - Découper via XMLTABLE('/lots/lot' ...) et conserver chaque <lot> intact dans lot_brut

-- ----------------------------------------------------------------------------
-- 2. Interrogation directe des lots bruts XML (sans passer par les tables mesures)
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Requête/Fonction XPath 1 : retrouver les lots contenant une mesure d'un capteur donné
--     (ex. xpath_exists('//mesure[@capteur = ...]', contenu_xml))
--   - Requête/Fonction XPath 2 : compter le nombre de <mesure> contenues dans chaque lot

-- ----------------------------------------------------------------------------
-- 3. Pipeline de qualification, aiguillage et isolement sans perte
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Extraire chaque noeud <mesure> avec sa forme XML d'origine (PASSING ... COLUMNS mesure_xml XML PATH '.')
--   - Détecter et classer les 5 motifs d'anomalies dans mesure_isolee :
--       1. 'capteur_inconnu'   : attribut capteur absent du référentiel capteur*
--       2. 'valeur_manquante'  : attribut attendu absent ou vide selon le type (valeur / pm25,pm10,no2 / humidite,pluie / instant)
--       3. 'format_invalide'   : instant ou nombre non convertible (regex numérique / timestamp invalide)
--       4. 'valeur_impossible' : viole les bornes physiques (ex. humidite > 100 ou < 0, pluie < 0, PM < 0, code erreur capteur)
--       5. 'doublon'           : couple (capteur, instant) déjà reçu dans un lot antérieur ou répété dans le même lot
--   - Insérer les mesures valides dans les tables de mesures (avec bloc EXCEPTION de sécurité pour toute erreur imprévue)

-- ----------------------------------------------------------------------------
-- 4. Contrôle d'exhaustivité (Aucune mesure perdue)
-- ----------------------------------------------------------------------------
-- TODO (Merzouk Amine) :
--   - Requête de contrôle affichant :
--       * total_xml       (compté directement en XPath sur lot_brut)
--       * total_valides   (somme des tables de mesures)
--       * total_isolees   (ventilé par motif dans mesure_isolee)
--       * assertion : total_valides + total_isolees = total_xml
