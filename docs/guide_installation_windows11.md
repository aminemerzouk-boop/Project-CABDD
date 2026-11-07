# Guide de Préparation du PC (Windows 11 + VS Code + PostgreSQL) & Bilan de `main`

Ce guide t'accompagne pas à pas pour préparer ton PC sous **Windows 11**, retrouver ta configuration **PostgreSQL**, et savoir exactement comment continuer avec le travail commité par Samou.

---

## Partie 1 — Ce qu'il faut installer sur Windows 11

Bonne nouvelle : comme tu as déjà **Windows 11**, **VS Code** et **PostgreSQL**, **tu n'as besoin d'aucun logiciel lourd** (pas besoin de Docker Desktop qui consomme énormément de RAM sur Windows 11 : PostgreSQL gère très bien les 3 bases `centre`, `zone1` et `zone2` + `postgres_fdw` dans une seule installation locale !).

### Étape 1.1 — Vérifier Git dans le terminal VS Code
Ouvre **VS Code**, puis ouvre un terminal **PowerShell** (`Ctrl + ù` ou menu `Terminal > New Terminal`) et tape :
```powershell
git --version
```
*(Si Git n'est pas installé : `winget install --id Git.Git -e --source winget`, puis redémarre VS Code).*

---

### Étape 1.2 — Retrouver ton installation PostgreSQL et son port
Dans le terminal **PowerShell**, exécute ces 3 commandes pour retrouver ta version, l'état du service et le port :

```powershell
# 1. Voir si le service Windows PostgreSQL tourne
Get-Service *postgres*

# 2. Voir quelle version est installée (ex: 15, 16, 17)
Get-ChildItem "C:\Program Files\PostgreSQL"

# 3. Voir sur quel port PostgreSQL écoute (par défaut : 5432)
Select-String -Path "C:\Program Files\PostgreSQL\*\data\postgresql.conf" -Pattern "^\s*port\s*="
```
- Si le statut du service est `Stopped`, démarre-le (dans un PowerShell lancé en **Administrateur**) :
  ```powershell
  Start-Service postgresql*
  ```

---

### Étape 1.3 — Rendre la commande `psql` accessible partout (PATH Windows)
Teste dans PowerShell :
```powershell
psql --version
```
Si Windows répond *« psql n'est pas reconnu »*, ajoute le dossier `bin` à ton `PATH` utilisateur (remplace `16` par ton numéro de version trouvé à l'étape 1.2) :
```powershell
$pgBin = "C:\Program Files\PostgreSQL\16\bin"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";" + $pgBin, "User")
```
Ferme et rouvre le terminal VS Code, puis revérifie `psql --version`.

---

### Étape 1.4 — Que faire si tu as oublié le mot de passe de `postgres` ? (Astuce en 1 minute)

Teste d'abord la connexion :
```powershell
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```
Si ton mot de passe ne marche plus, réinitialise-le facilement :

1. Lance **Bloc-notes (Notepad)** ou **VS Code** en **Administrateur** (clic droit $\rightarrow$ *Exécuter en tant qu'administrateur*).
2. Ouvre le fichier :
   `C:\Program Files\PostgreSQL\<ta_version>\data\pg_hba.conf`
3. Tout en bas du fichier, repère les lignes `IPv4` et `IPv6` :
   ```text
   host    all             all             127.0.0.1/32            scram-sha-256
   host    all             all             ::1/128                 scram-sha-256
   ```
   Remplace temporairement `scram-sha-256` (ou `md5`) par **`trust`**, puis enregistre (`Ctrl+S`).
4. Dans PowerShell (**Administrateur**), redémarre PostgreSQL :
   ```powershell
   Restart-Service postgresql*
   ```
5. Change le mot de passe en `postgres` (sans qu'aucun mot de passe te soit demandé) :
   ```powershell
   psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "ALTER USER postgres WITH PASSWORD 'postgres';"
   ```
6. Remets **`scram-sha-256`** dans `pg_hba.conf`, enregistre et relance `Restart-Service postgresql*`.

---

### Étape 1.5 — Créer le fichier `pgpass.conf` (indispensable pour enchaîner les scripts sans retaper le mot de passe)
Dans PowerShell (normal), exécute ce bloc pour que `psql` retienne ton mot de passe localement :

```powershell
$pgPassDir = "$env:APPDATA\postgresql"
New-Item -ItemType Directory -Force -Path $pgPassDir | Out-Null
@(
  "127.0.0.1:5432:*:postgres:postgresql"
  "localhost:5432:*:postgres:postgresql"
) | Set-Content -Encoding ASCII "$pgPassDir\pgpass.conf"
```
Maintenant, tape simplement :
```powershell
psql -h 127.0.0.1 -U postgres -d postgres -c "SELECT version();"
```
Si ça affiche la version de PostgreSQL directement sans te demander de mot de passe, **ton PC est 100 % prêt !**

---

### Étape 1.6 — Extensions VS Code conseillées (légères et gratuites)
Dans l'onglet Extensions de VS Code (`Ctrl+Shift+X`), installe uniquement :
1. **`PostgreSQL`** *(de Microsoft : `ms-ossdata.vscode-pgsql`, ou **Database Client / SQLTools**)* — pour explorer visuellement les 3 bases `centre`, `zone1` et `zone2`.
2. **`XML`** *(de Red Hat : `redhat.vscode-xml`)* — pour inspecter `lots_A.xml` et formater le rapport XML généré.

---

## Partie 2 — Faut-il continuer à partir du commit de Samou sur `main` ?

### Réponse courte : **OUI pour garder ses bonnes bases, MAIS en corrigeant ensemble 7 bugs critiques !**

J'ai inspecté ligne par ligne tout ce que Samou a fusionné hier sur `main` (PR #2).  
**Pourquoi il ne faut pas rendre `main` en l'état :** son code a été généré et testé avec de **fausses données Python** (`data/generer_donnees.py` : `34 576` mesures et `16` erreurs) **avant** que tu ajoutes les vrais fichiers du professeur (`33 974` mesures et `694` erreurs).

Voici ce qui marche déjà bien dans son commit **et** les **7 problèmes précis** qu'il faut absolument corriger à deux :

| # | Problème trouvé dans le commit de Samou sur `main` | Qui corrige ? |
| :---: | :--- | :---: |
| **1** | **Deux jeux de scripts mélangés dans `sql/`** (`00..07` + `01..10`) et présence de `data/generer_donnees.py` (Python interdit par l'énoncé) + `donnees_variante_A.zip`. | **Ensemble** (nettoyage Git) |
| **2** | **Bug d'intégrité sur `INHERITS` (`01_schema.sql`)** : les sous-tables `capteur_temperature`, `capteur_air`, `capteur_hydro` n'ont pas de `PRIMARY KEY`, et `REFERENCES capteur(code)` dans PostgreSQL ne regarde que la table mère vide. | **Amine** |
| **3** | **Compatibilité Windows 11 + ordre de tri XML (`03_lots_xml.sql`)** : `pg_read_file()` échoue souvent sous Windows (`Permission denied` sur `C:\Users\...`), et `format_invalide` est testé avant `valeur_manquante`. | **Amine** |
| **4** | **Double bug bloquant sur la propagation FDW (`05_distribution_centre.sql`)** :<br>• En PostgreSQL, un trigger sur la table mère `capteur` **ne se déclenche pas** sur les tables filles `INHERITS` !<br>• Ses triggers font `DELETE` puis `INSERT` lors d'un `UPDATE`, ce qui **plante par violation de FK** dès qu'une zone contient des mesures ! (Il faut `INSERT ... ON CONFLICT DO UPDATE`). | **Amine** |
| **5** | **Bug sur `depasse_seuil` avec le vrai `seuils_A.csv`** : dans le vrai fichier CSV, la grandeur de température s'appelle `'valeur'` (`temperature,valeur,min,0.0,°C`) alors que sa vue utilise `'temperature'` $\rightarrow$ aucun dépassement de température n'est jamais trouvé ! | **Samou** |
| **6** | **Dates de service oubliées & perte des objets dans les zones** : le rapport XML doit tenir compte de `mise_en_service` (`BJ-02-A1` le `02/02/2026`) et `date_retrait` (`JJ-02-T1` le `17/03/2026`), et dans `05b_zone.sql` les objets `type_air` / `type_hydro` ont été aplatis en lignes avec le même `id` répété 3 fois. | **Samou** |
| **7** | **Rapport `rapport/rapport.md` avec de faux chiffres & `EXPLAIN` incomplet** : le rapport affiche `34 576` / `16 isolées` / `8 seuils` au lieu des vrais résultats (**`33 974` = `33 280` valides + `694` isolées**, `6` seuils), et le `EXPLAIN` ne filtre pas sur **1 seule zone + 1 seul mois**. | **Amine & Samou** |

### Plan d'action recommandé dès que ton PostgreSQL répond :
1. Tu fais les étapes **1.1 à 1.5** ci-dessus sur ton Windows 11 (ça prend 5 minutes).
2. Dis-moi dès que `psql -h 127.0.0.1 -U postgres -d postgres -c "SELECT version();"` fonctionne chez toi : on unifiera proprement le dossier `sql/` et on implémentera/testera **ta partie** en premier sur les vraies données !
