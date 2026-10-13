' Lance l'interface graphique sans aucune fenetre de console visible.
' -WindowStyle Hidden + le "0" dans Run masquent completement la fenetre PowerShell
' sous-jacente ; -ExecutionPolicy Bypass evite toute configuration manuelle, pour
' cette seule execution (rien n'est modifie de facon permanente sur la machine).

Dim objFSO, objShell, strDossier, strCheminScript, strCommande

Set objFSO = CreateObject("Scripting.FileSystemObject")
strDossier = objFSO.GetParentFolderName(WScript.ScriptFullName)
strCheminScript = strDossier & "\Coloriser-STL-GUI.ps1"

Set objShell = CreateObject("WScript.Shell")
strCommande = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strCheminScript & """"
objShell.Run strCommande, 0, False
