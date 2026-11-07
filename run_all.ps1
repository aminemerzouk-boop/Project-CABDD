<#
.SYNOPSIS
    Exécute dans l'ordre les scripts SQL numérotés du Mini-Projet CABDD (Variante A)
    sous Windows 11 + PostgreSQL 18.

.EXAMPLE
    .\run_all.ps1 -StopAt 4                 # Teste uniquement l'Étape 1 (01 -> 04)
    .\run_all.ps1 -StopAt 6                 # Teste les Étapes 1 et 2 (01 -> 06)
    .\run_all.ps1                           # Exécute tout le projet (01 -> 10)
#>
param(
    [string]$HostName = "127.0.0.1",
    [int]$Port        = 5432,
    [string]$User     = "postgres",
    [string]$Password = "postgresql",
    [int]$StopAt      = 10
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$env:PGPASSWORD = $Password
$env:PGCLIENTENCODING = "UTF8"

$scripts = @(
    @{ Num = 1;  File = "sql/01_init_bases.sql" },
    @{ Num = 2;  File = "sql/02_schema_ro.sql" },
    @{ Num = 3;  File = "sql/03_operations_ro.sql" },
    @{ Num = 4;  File = "sql/04_referentiel_csv.sql" },
    @{ Num = 5;  File = "sql/05_chargement_xml.sql" },
    @{ Num = 6;  File = "sql/06_rapport_xml.sql" },
    @{ Num = 7;  File = "sql/07_zones_partitions.sql" },
    @{ Num = 8;  File = "sql/08_propagation_referentiel.sql" },
    @{ Num = 9;  File = "sql/09_centre_transparent.sql" },
    @{ Num = 10; File = "sql/10_tests_et_plans.sql" }
)

foreach ($s in $scripts) {
    if ($s.Num -gt $StopAt) { break }
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host ("[{0:D2}/10] Exécution de {1}" -f $s.Num, $s.File) -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    psql -h $HostName -p $Port -U $User -d postgres `
         -v ON_ERROR_STOP=1 `
         -v pg_host=$HostName `
         -v pg_port=$Port `
         -v pg_user=$User `
         -v pg_pass=$Password `
         -f $s.File

    if ($LASTEXITCODE -ne 0) {
        throw "Échec lors de l'exécution de $($s.File) (code $LASTEXITCODE)."
    }
}

Write-Host "`nExécution terminée avec succès jusqu'au script $StopAt !" -ForegroundColor Green
