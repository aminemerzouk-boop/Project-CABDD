<#
# config.example.ps1 — MODÈLE de configuration des identifiants PostgreSQL.
#
# Chaque membre du binôme copie ce fichier en "config.local.ps1" et y met
# SES propres identifiants (le fichier config.local.ps1 est ignoré par Git :
# aucun mot de passe n'est jamais commité).
#
#   Samou  : son user/mot de passe PostgreSQL sur SA machine
#   Amine  : les siens sur SA machine
# run_all.ps1 lit automatiquement config.local.ps1 s'il existe.
#>

$PGConfig = @{
    HostName = "127.0.0.1"
    Port     = 5432
    User     = "postgres"        # ← ton user PostgreSQL (souvent "postgres")
    Password = "ton_mot_de_passe" # ← TON mot de passe PostgreSQL
}
