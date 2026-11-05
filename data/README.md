# Données d'entrée — Variante A

Déposez dans ce dossier `data/` les quatre fichiers fournis sur l'espace cours pour la **Variante A** :

1. `stations_A.csv` — Les **12 stations** du réseau avec leur code, nom, wilaya, zone et position (`latitude`, `longitude`, `altitude`) :
   - **Zone 1** : Béjaïa (`BJ-01` à `BJ-03`), Jijel (`JJ-01` à `JJ-03` — selon le préfixe exact du CSV)
   - **Zone 2** : Sétif, Bordj Bou Arréridj
2. `capteurs_A.csv` — Les **36 capteurs** (3 par station : température `-T1`, qualité de l'air `-A1`, hydrométrie `-H1`) avec station de rattachement, type, date de mise en service, date de retrait éventuelle et état.
3. `seuils_A.csv` — Les **seuils d'alerte** (type de capteur, grandeur, borne `min`/`max`, valeur, unité).
4. `lots_A.xml` — Les **lots journaliers de mesures** du **1er janvier au 30 avril 2026** (relevés toutes les 3 heures : `00h, 03h, 06h, 09h, 12h, 15h, 18h, 21h`).

## Rappel du format XML de la Variante A (mesures à plat, valeurs en attributs)

```xml
<lots>
  <lot station="BJ-01" envoi="2026-02-15T00:05:00">
    <mesure capteur="BJ-01-T1" instant="2026-02-14T21:00:00"
            type="temperature" valeur="14.6"/>
    <mesure capteur="BJ-01-A1" instant="2026-02-14T21:00:00"
            type="air" pm25="16.7" pm10="37.2" no2="22.9"/>
    <mesure capteur="BJ-01-H1" instant="2026-02-14T21:00:00"
            type="hydro" humidite="55" pluie="0.0"/>
  </lot>
</lots>
```
