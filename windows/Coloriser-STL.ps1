<#
.SYNOPSIS
    Colorise un dossier entier de fichiers STL non colorises, automatiquement, via l'API Meshy
    (Retexture puis Multi-Color Print), et sort un .3mf pret a trancher pour chaque fichier.

.DESCRIPTION
    PAS TESTE PAR CLAUDE : ce script appelle une vraie API payante (credits Meshy), impossible
    a tester sans une vraie cle API et de vrais credits a depenser. Teste-le d'abord sur UN SEUL
    fichier avant de lancer un gros dossier.

    Documentation officielle utilisee pour ecrire ce script :
      https://docs.meshy.ai/en/api/retexture
      https://docs.meshy.ai/en/api/multi-color-print

.NOTES
    Pour l'executer par double-clic, il faut d'abord autoriser les scripts PowerShell une fois
    (voir le README). Sinon : clic droit sur ce fichier > "Executer avec PowerShell".
#>

$ErrorActionPreference = "Stop"
$BaseUrl = "https://api.meshy.ai/openapi/v1"
$IntervallePollSecondes = 5
$TimeoutTacheSecondes = 1200  # 20 minutes max par etape

function Attendre-Tache {
    param([string]$UrlTache, [hashtable]$Entetes, [string]$Libelle)
    $debut = Get-Date
    while ($true) {
        if (((Get-Date) - $debut).TotalSeconds -gt $TimeoutTacheSecondes) {
            throw "$Libelle : pas de reponse apres $($TimeoutTacheSecondes / 60) min"
        }
        $tache = Invoke-RestMethod -Uri $UrlTache -Headers $Entetes -Method Get
        switch ($tache.status) {
            "SUCCEEDED" { return $tache }
            "FAILED"    { throw "$Libelle a echoue : $($tache.task_error.message)" }
            "CANCELED"  { throw "$Libelle a ete annulee" }
            default     { Write-Host "    $Libelle : $($tache.status) ($($tache.progress)%)..." }
        }
        Start-Sleep -Seconds $IntervallePollSecondes
    }
}

function Coloriser-UnFichier {
    param(
        [System.IO.FileInfo]$FichierStl,
        [string]$Prompt,
        [hashtable]$Entetes,
        [string]$DossierSortie,
        [int]$MaxCouleurs,
        [string]$Style,
        [string]$MarqueImprimante
    )

    Write-Host "`n=== $($FichierStl.Name) ===" -ForegroundColor Cyan

    $tailleMo = $FichierStl.Length / 1MB
    if ($tailleMo -gt 50) {
        Write-Host "  ATTENTION : fichier de $([math]::Round($tailleMo,1)) Mo, limite Meshy = 50 Mo." -ForegroundColor Yellow
    }

    # --- Etape 1 : Retexture ---
    $octets = [System.IO.File]::ReadAllBytes($FichierStl.FullName)
    $base64 = [Convert]::ToBase64String($octets)
    $dataUri = "data:application/octet-stream;base64,$base64"

    Write-Host "  Envoi a l'API Retexture..."
    $corpsRetexture = @{
        model_url          = $dataUri
        text_style_prompt  = $Prompt
        enable_original_uv = $false
    } | ConvertTo-Json

    $reponse = Invoke-RestMethod -Uri "$BaseUrl/retexture" -Headers $Entetes -Method Post `
        -ContentType "application/json" -Body $corpsRetexture
    $idRetexture = $reponse.result

    $tacheRetexture = Attendre-Tache -UrlTache "$BaseUrl/retexture/$idRetexture" -Entetes $Entetes -Libelle "Retexture"
    Write-Host "  Retexture terminee ($($tacheRetexture.consumed_credits) credits)." -ForegroundColor Green

    # --- Etape 2 : Multi-Color Print (enchaine directement sur le resultat de l'etape 1) ---
    Write-Host "  Envoi a l'API Multi-Color Print..."
    $corpsImpression = @{
        input_task_id  = $idRetexture
        max_colors     = $MaxCouleurs
        style          = $Style
        printer_brand  = $MarqueImprimante
    } | ConvertTo-Json

    $reponse = Invoke-RestMethod -Uri "$BaseUrl/print/multi-color" -Headers $Entetes -Method Post `
        -ContentType "application/json" -Body $corpsImpression
    $idImpression = $reponse.result

    $tacheImpression = Attendre-Tache -UrlTache "$BaseUrl/print/multi-color/$idImpression" -Entetes $Entetes -Libelle "Multi-Color Print"
    Write-Host "  Multi-Color Print terminee ($($tacheImpression.consumed_credits) credits)." -ForegroundColor Green

    # --- Telechargement ---
    $cheminSortie = Join-Path $DossierSortie ($FichierStl.BaseName + "_colorise.3mf")
    Invoke-WebRequest -Uri $tacheImpression.model_urls.'3mf' -OutFile $cheminSortie
    Write-Host "  -> Enregistre : $cheminSortie" -ForegroundColor Green
}

# ============================== PROGRAMME PRINCIPAL ==============================

Write-Host "=== Colorisation de STL en lot (Meshy) ===" -ForegroundColor Cyan
Write-Host ""

# Cle API : enregistree localement (chiffree avec ton compte Windows - illisible sur une autre
# machine ou par un autre utilisateur) pour ne plus la redemander a chaque lancement.
# IMPORTANT si tu partages ce script sur le forum : ne partage JAMAIS le fichier cle_api.enc,
# seulement le .ps1 - chaque personne doit enregistrer SA PROPRE cle en le lancant une 1ere fois.
$cheminCleChiffree = Join-Path $PSScriptRoot "cle_api.enc"

if (Test-Path $cheminCleChiffree) {
    $cleApiSecurisee = Get-Content $cheminCleChiffree | ConvertTo-SecureString
    $cleApi = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cleApiSecurisee))
    Write-Host "Cle API deja enregistree, reutilisation." -ForegroundColor DarkGray
} else {
    Write-Host "Aucune cle API enregistree pour l'instant."
    Write-Host "Colle ta cle (Ctrl+V ou clic droit > Coller) puis Entree :"
    $cleApiSecurisee = Read-Host "Cle API Meshy (meshy.ai/settings/api)" -AsSecureString
    $cleApi = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cleApiSecurisee))

    if ($cleApi) {
        $cleApiSecurisee | ConvertFrom-SecureString | Set-Content $cheminCleChiffree
        Write-Host "Cle enregistree pour les prochains lancements (chiffree, propre a ce compte Windows)." -ForegroundColor Green
    }
}
if (-not $cleApi) { Write-Host "Cle API vide, arret." -ForegroundColor Red; exit 1 }

# Dossier : demande a chaque lancement (plus simple pour un double-clic que des arguments)
$dossier = Read-Host "Chemin du dossier contenant tes fichiers .stl"
if (-not (Test-Path $dossier -PathType Container)) {
    Write-Host "Dossier introuvable : $dossier" -ForegroundColor Red; exit 1
}

$prompt = Read-Host "Decris le style/les couleurs voulues (ex: couleurs naturelles et coherentes)"
if (-not $prompt) { Write-Host "Prompt vide, arret." -ForegroundColor Red; exit 1 }

$saisieCouleurs = Read-Host "Nombre de couleurs (1-16, Entree pour 4)"
$maxCouleurs = if ($saisieCouleurs) { [int]$saisieCouleurs } else { 4 }
if ($maxCouleurs -gt 16) {
    Write-Host "Nombre de couleurs plafonne a 16 (limite de l'API Meshy Multi-Color Print)." -ForegroundColor Yellow
    $maxCouleurs = 16
}
if ($maxCouleurs -lt 1) { $maxCouleurs = 1 }

$entetes = @{ Authorization = "Bearer $cleApi" }

$fichiersStl = Get-ChildItem -Path $dossier -Filter "*.stl"
if ($fichiersStl.Count -eq 0) {
    Write-Host "Aucun fichier .stl trouve dans $dossier" -ForegroundColor Red; exit 1
}

$dossierSortie = Join-Path $dossier "colorise"
New-Item -ItemType Directory -Force -Path $dossierSortie | Out-Null

Write-Host "`n$($fichiersStl.Count) fichier(s) a traiter, sortie dans $dossierSortie"

$reussites = @()
$echecs = @()
foreach ($fichier in $fichiersStl) {
    try {
        Coloriser-UnFichier -FichierStl $fichier -Prompt $prompt -Entetes $entetes `
            -DossierSortie $dossierSortie -MaxCouleurs $maxCouleurs -Style "cartoon" -MarqueImprimante "bambu"
        $reussites += $fichier.Name
    } catch {
        Write-Host "  ECHEC sur $($fichier.Name) : $_" -ForegroundColor Red
        $echecs += "$($fichier.Name) : $_"
    }
}

Write-Host "`n=== Bilan : $($reussites.Count) reussite(s), $($echecs.Count) echec(s) ===" -ForegroundColor Cyan
foreach ($e in $echecs) { Write-Host "  ECHEC $e" -ForegroundColor Red }

Write-Host "`nAppuie sur Entree pour fermer..."
Read-Host | Out-Null
