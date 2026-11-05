#!/usr/bin/env python3
"""
Générateur des fichiers de données de la VARIANTE A (réseau de capteurs).
Produit dans ce dossier :
  - stations_A.csv   : 12 stations (4 wilayas x 3), avec position et zone
  - capteurs_A.csv   : 36 capteurs (3 par station : T1, A1, H1)
  - seuils_A.csv     : seuils d'alerte par type de capteur / grandeur / borne
  - lots_A.xml       : lots XML du 01/01/2026 au 30/04/2026 (1 lot/station/jour)
                       avec les 5 sortes d'erreurs : valeur impossible, valeur
                       manquante, format invalide, capteur inconnu, doublon.
Usage :  python3 data/generer_donnees.py
"""
import csv
import random
from datetime import date, datetime, timedelta
from pathlib import Path
from xml.sax.saxutils import escape

random.seed(42)  # reproductible

OUT = Path(__file__).resolve().parent

# ---------------------------------------------------------------- stations
# Variante A : zone 1 = Béjaïa, Jijel ; zone 2 = Sétif, Bordj Bou Arréridj
WILAYAS = [
    ("BJ",  "Béjaïa",                 1, 36.7500,  5.0700,  120),
    ("JJ",  "Jijel",                  1, 36.8200,  5.7700,   45),
    ("ST",  "Sétif",                  2, 36.1900,  5.4100, 1080),
    ("BBA", "Bordj Bou Arréridj",     2, 36.0500,  4.7600,  900),
]

stations = []  # (code, nom, wilaya, zone, lat, lon, alt)
for prefix, wilaya, zone, lat, lon, alt in WILAYAS:
    for n in range(1, 4):
        code = f"{prefix}-{n:02d}"
        stations.append((
            code,
            f"Station {wilaya} {n}",
            wilaya,
            zone,
            round(lat + random.uniform(-0.05, 0.05), 6),
            round(lon + random.uniform(-0.05, 0.05), 6),
            round(alt + random.uniform(-80, 80), 2),
        ))

with open(OUT / "stations_A.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["code", "nom", "wilaya", "zone", "latitude", "longitude", "altitude"])
    w.writerows(stations)

# ---------------------------------------------------------------- capteurs
# 3 capteurs par station : -T1 température, -A1 air, -H1 hydrométrie (variante A)
capteurs = []  # (code, station, type, mise_en_service, retrait, etat)
for code, *_ in stations:
    for lettre, typ in (("T1", "temperature"), ("A1", "air"), ("H1", "hydro")):
        mise = date(2025, random.choice([6, 9, 11]), random.randint(1, 28))
        capteur = (f"{code}-{lettre}", code, typ, mise.isoformat(), "", "actif")
        capteurs.append(capteur)

# Quelques capteurs retirés / hors service pendant la période (pas une erreur)
capteurs[4] = (capteurs[4][0], capteurs[4][1], capteurs[4][2], capteurs[4][3],
               "2026-02-20", "retire")
capteurs[10] = (capteurs[10][0], capteurs[10][1], capteurs[10][2], capteurs[10][3],
                "2026-03-15", "hors_service")
capteurs[22] = (capteurs[22][0], capteurs[22][1], capteurs[22][2], capteurs[22][3],
                "", "defaillant")

with open(OUT / "capteurs_A.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["code", "station", "type", "mise_en_service", "retrait", "etat"])
    w.writerows(capteurs)

# ------------------------------------------------------------------ seuils
seuils = [
    ("temperature", "temperature", "min", -10,  "°C"),
    ("temperature", "temperature", "max", 45,   "°C"),
    ("air", "pm25", "max", 100, "µg/m3"),
    ("air", "pm10", "max", 150, "µg/m3"),
    ("air", "no2",  "max", 200, "µg/m3"),
    ("hydro", "humidite", "min", 0,   "%"),
    ("hydro", "humidite", "max", 100, "%"),
    ("hydro", "pluie",    "max", 300, "mm"),
]
with open(OUT / "seuils_A.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["type_capteur", "grandeur", "borne", "valeur", "unite"])
    w.writerows(seuils)

# -------------------------------------------------------------- lots XML
DEBUT = date(2026, 1, 1)
FIN = date(2026, 4, 30)
INSTANTS = [f"{h:02d}:00:00" for h in range(0, 24, 3)]  # 0h, 3h, ..., 21h

# Erreurs injectées à l'intérieur du lot (station, date) concerné :
# (station, date) -> [lignes <mesure> erronées]
ERREURS = {
    ("BJ-01", "2026-01-05"): ['    <mesure capteur="BJ-01-H1" instant="2026-01-05T06:00:00" type="hydro" humidite="130" pluie="0.0"/>',
                              '    <mesure capteur="BJ-01-X9" instant="2026-01-05T12:00:00" type="temperature" valeur="12.5"/>'],
    ("BJ-01", "2026-01-01"): ['    <mesure capteur="BJ-01-T1" instant="2026-01-01T00:00:00" type="temperature" valeur="6.2"/>'],  # doublon
    ("JJ-02", "2026-01-12"): ['    <mesure capteur="JJ-02-A1" instant="2026-01-12T09:00:00" type="air" pm25="-4.5" pm10="30.0" no2="20.0"/>'],
    ("JJ-01", "2026-01-08"): ['    <mesure capteur="JJ-01-A1" instant="2026-01-08T00:00:00" type="air" pm25="18.0" no2="25.0"/>'],  # pm10 manquant
    ("JJ-03", "2026-02-14"): ['    <mesure capteur="JJ-03-H1" instant="14/02/2026 09:00" type="hydro" humidite="55" pluie="1.0"/>'],  # date invalide
    ("ST-03", "2026-02-03"): ['    <mesure capteur="ST-03-T1" instant="2026-02-03T12:00:00" type="temperature" valeur="999"/>'],
    ("ST-02", "2026-01-20"): ['    <mesure capteur="ST-02-H1" instant="2026-01-20T09:00:00" type="hydro" humidite="60"/>'],  # pluie manquante
    ("ST-02", "2026-02-28"): ['    <mesure capteur="ST-02-A1" instant="2026-02-28T25:00:00" type="air" pm25="abc" pm10="40" no2="20"/>'],  # heure invalide + pm25 invalide
    ("ST-01", "2026-03-22"): ['    <mesure capteur="ST-01-T1" instant="2026-03-22T03:00:00" type="temperature" valeur="-75.5"/>'],
    ("ST-01", "2026-02-05"): ['    <mesure capteur="ST-01-H1" instant="2026-02-05T09:00:00" type="hydro" humidite="44" pluie="0.0"/>'],  # doublon
    ("BBA-01", "2026-02-14"): ['    <mesure capteur="BBA-01-H1" instant="2026-02-14T15:00:00" type="hydro" humidite="50" pluie="-2.5"/>'],
    ("BBA-02", "2026-02-10"): ['    <mesure capteur="BBA-02-T1" instant="2026-02-10T21:00:00" type="temperature"/>',  # valeur manquante
                               '    <mesure capteur="ZZ-99-T1" instant="2026-02-10T18:00:00" type="temperature" valeur="9.0"/>'],  # capteur inconnu
    ("BJ-02", "2026-01-15"): ['    <mesure capteur="BJ-02-T1" instant="2026-01-15T06:00:00" type="temperature" valeur="N/A"/>'],
    ("BJ-03", "2026-03-01"): ['    <mesure capteur="BJ-03-A1" instant="2026-03-01T18:00:00" type="air" pm25="12" pm10="-8" no2="33"/>'],
}

n_mesures_total = 0
n_isolees = 0
lignes = ['<?xml version="1.0" encoding="UTF-8"?>', "<lots>"]

jour = DEBUT
while jour <= FIN:
    for code, *_ in stations:
        envoi = datetime.combine(jour, datetime.min.time()) + timedelta(days=1, minutes=5)
        lignes.append(f'  <lot station="{code}" envoi="{envoi.isoformat()}">')
        for instant_h in INSTANTS:
            instant = f"{jour.isoformat()}T{instant_h}"
            for suffixe, typ in (("T1", "temperature"), ("A1", "air"), ("H1", "hydro")):
                capteur = f"{code}-{suffixe}"
                # ---- génération de la mesure normale -------------------
                if typ == "temperature":
                    v = round(random.uniform(-2, 38), 1)
                    m = (f'    <mesure capteur="{capteur}" instant="{instant}" '
                         f'type="temperature" valeur="{v}"/>')
                elif typ == "air":
                    pm25 = round(random.uniform(5, 90), 1)
                    pm10 = round(pm25 * random.uniform(1.3, 2.2), 1)
                    no2 = round(random.uniform(5, 120), 1)
                    m = (f'    <mesure capteur="{capteur}" instant="{instant}" '
                         f'type="air" pm25="{pm25}" pm10="{pm10}" no2="{no2}"/>')
                else:
                    h = round(random.uniform(15, 99), 1)
                    p = round(random.choice([0.0, 0.0, 0.0, random.uniform(0, 25)]), 1)
                    m = (f'    <mesure capteur="{capteur}" instant="{instant}" '
                         f'type="hydro" humidite="{h}" pluie="{p}"/>')
                lignes.append(m)
                n_mesures_total += 1
        # ---- injection des mesures erronées dans ce lot ------------
        for err in ERREURS.get((code, jour.isoformat()), []):
            lignes.append(err)
            n_mesures_total += 1
            n_isolees += 1
        lignes.append("  </lot>")
    jour += timedelta(days=1)

lignes.append("</lots>")
with open(OUT / "lots_A.xml", "w", encoding="utf-8") as f:
    f.write("\n".join(lignes) + "\n")

print(f"stations_A.csv : {len(stations)} stations")
print(f"capteurs_A.csv : {len(capteurs)} capteurs")
print(f"seuils_A.csv   : {len(seuils)} seuils")
print(f"lots_A.xml     : mesures totales={n_mesures_total}, isolees prevues={n_isolees}")
