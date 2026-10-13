@echo off
REM Lance l'interface graphique sans jamais demander de configuration manuelle :
REM -ExecutionPolicy Bypass ignore a la fois la politique du systeme ET le blocage
REM "fichier telecharge depuis Internet", pour cette seule execution (rien n'est modifie
REM de facon permanente sur la machine).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Coloriser-STL-GUI.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Une erreur s'est produite. Appuie sur une touche pour fermer...
    pause >nul
)
