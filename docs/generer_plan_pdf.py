#!/usr/bin/env python3
"""
Génère le PLAN PDF de Samou (docs/plan_samou.pdf).
Règle : à chaque tâche TERMINÉE, la retirer de la liste TACHES ci-dessous
(ou passer son statut à 'fait'), puis relancer :
    python3 docs/generer_plan_pdf.py
Le PDF ne liste que les tâches restantes + un récapitulatif.
"""
from datetime import date
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer

# ---------------------------------------------------------------- tâches
# statut: 'a_faire' | 'fait'  — une tâche 'fait' est retirée du plan affiché
TACHES = [
    ("01", "sql/01_init_bases.sql", "Création des 3 bases + extensions",
     "Bases centre/zone1/zone2 en UTF8 + postgres_fdw. Testé : OK.", "fait"),
    ("03", "sql/03_operations_ro.sql", "Opérations en base sur les objets",
     "distance_km (Haversine), distance_stations_km, depasse_seuil_*, seuils_franchis, "
     "celsius_vers_fahrenheit, pluie_mm_vers_pouces, point_de_rosee. Testé : OK.", "fait"),
    ("04", "sql/04_referentiel_csv.sql", "Chargement du référentiel CSV -> modèle RO",
     "Staging \\copy des 3 CSV officiels (en-têtes altitude_m, date_retrait, type), "
     "insertion station/capteur*/seuil_alerte, tests de rejet (humidité>100, PM<0, capteur inconnu). "
     "Critère : SELECT * FROM capteur = 36 lignes. Testé : OK (36 capteurs, rejets FK/CHECK OK).", "fait"),
    ("06", "sql/06_rapport_xml.sql", "Rapport XML Bilan journalier (variante A)",
     "generer_bilan_journalier_xml(debut, fin) : <bilanJournalier><jour><station><grandeur> "
     "avec min/max/moyenne/nbMesures, en tenant compte des dates de mise en service/retrait. "
     "Test : extrait sur février 2026.", "a_faire"),
    ("07", "sql/07_zones_partitions.sql", "Schémas zone1/zone2 + partitionnement mensuel",
     "Copie locale du référentiel, PARTITION BY RANGE (instant_mesure) 2026_01..2026_04 + DEFAULT, "
     "contrainte 'stations de la zone uniquement'. Critère : EXPLAIN 1 mois = 1 seule partition lue.", "a_faire"),
    ("09", "sql/09_centre_transparent.sql", "Transparence centre : vues + routage + rapport réparti",
     "Foreign tables mesures zone1/zone2, migration des mesures, centre vidé, vues UNION ALL, "
     "INSTEAD OF INSERT, bilan XML depuis centre.", "a_faire"),
    ("10", "sql/10_tests_et_plans.sql", "Validation complète + plans (avec Amine)",
     "Batterie de tests, EXPLAIN (ANALYZE, VERBOSE) centre -> 1 zone / 1 mois, panne simulée d'une zone, "
     "extraits pour le rapport 10 pages.", "a_faire"),
]

AUJOURDHUI = date(2026, 11, 6)

# ---------------------------------------------------------------- rendu PDF
styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="Titre", parent=styles["Title"], fontSize=20, spaceAfter=6,
                          textColor=colors.HexColor("#1a3a5c")))
styles.add(ParagraphStyle(name="Sous", parent=styles["Normal"], fontSize=11, textColor=colors.grey, spaceAfter=14))
styles.add(ParagraphStyle(name="Tache", parent=styles["Heading2"], fontSize=13, spaceBefore=12,
                          textColor=colors.HexColor("#1a3a5c")))
styles.add(ParagraphStyle(name="Corps", parent=styles["Normal"], fontSize=10, leading=14))
styles.add(ParagraphStyle(name="Petit", parent=styles["Normal"], fontSize=9, textColor=colors.grey))

doc = SimpleDocTemplate("docs/plan_samou.pdf", pagesize=A4,
                        leftMargin=2*cm, rightMargin=2*cm, topMargin=2*cm, bottomMargin=2*cm,
                        title="Plan de travail - Samou - Mini-projet CABDD Variante A",
                        author="Megharba Samou")
story = []

restantes = [t for t in TACHES if t[4] == "a_faire"]
faites = [t for t in TACHES if t[4] == "fait"]

story.append(Paragraph("Plan de travail — Megharba Samou", styles["Titre"]))
story.append(Paragraph(f"Mini-projet CABDD · Variante A (hydrométrie, partitions mensuelles, bilan journalier) · "
                       f"Mis à jour le {AUJOURDHUI.isoformat()}", styles["Sous"]))
story.append(Paragraph(f"<b>{len(restantes)} tâche(s) restante(s)</b> sur {len(TACHES)} — "
                       f"{len(faites)} terminée(s) : {', '.join(t[0] for t in faites)}.", styles["Corps"]))
story.append(Spacer(1, 0.4*cm))

for num, script, titre, detail, statut in restantes:
    story.append(Paragraph(f"☐ Tâche {num} — {titre}", styles["Tache"]))
    story.append(Paragraph(f"<b>Fichier :</b> <font face='Courier'>{script}</font>", styles["Corps"]))
    story.append(Paragraph(detail, styles["Corps"]))

story.append(Spacer(1, 0.6*cm))
story.append(Paragraph("Ordre d'exécution global (avec Amine)", styles["Tache"]))
ordre = ["01 ✅", "02 (Amine)", "03 ✅", "04", "05 (Amine)", "06", "07", "08 (Amine)", "09", "10 (ensemble)"]
story.append(Paragraph(" → ".join(ordre), styles["Corps"]))
story.append(Spacer(1, 0.4*cm))
story.append(Paragraph("Règle : quand une tâche est terminée et testée, la retirer de docs/generer_plan_pdf.py "
                       "puis relancer <font face='Courier'>python3 docs/generer_plan_pdf.py</font> — "
                       "ce PDF est régénéré sans les tâches faites.", styles["Petit"]))

doc.build(story)
print(f"PDF généré : docs/plan_samou.pdf ({len(restantes)} tâches restantes)")
