# ColoriseurSTL — version Windows (PowerShell)

Interface graphique PowerShell/WinForms qui colorise automatiquement un dossier entier de
fichiers 3D non colorisés (`.stl`, `.obj`, `.fbx`, `.glb`, `.gltf`) via l'API Meshy ou Tripo, et
sort des fichiers prêts à trancher. Version d'origine du projet — le [portage Android](../app)
reprend les mêmes idées en appli mobile.

**Deux fournisseurs possibles, au choix** : Meshy (palette fixe à N couleurs, sort un `.3mf` prêt
à trancher dans Bambu Studio) ou Tripo (couleur par sommet, dégradé continu, sort un `.obj`
coloré) — utile pour basculer sur l'un si l'autre est à court de crédits.

## Utilisation (recommandée) — double-clic, aucune configuration

1. Garde ces fichiers **dans le même dossier** :
   - `Lancer-Coloriser-STL.vbs` ← celui sur lequel tu double-cliques
   - `Coloriser-STL-GUI.ps1`
   - `Lancer-Coloriser-STL.bat` (dépannage uniquement, si rien ne s'ouvre)
2. Double-clique sur `Lancer-Coloriser-STL.vbs`. Une vraie fenêtre s'ouvre, sans console visible,
   sans configuration à faire.
3. Dans la fenêtre : colle ta clé API, choisis le dossier de fichiers 3D, décris le style voulu,
   choisis le nombre de couleurs, lance.

Les fichiers colorisés arrivent dans un sous-dossier `colorise` à côté des fichiers d'origine.

## La clé API

Demandée une seule fois : au premier lancement, elle est enregistrée dans `cle_api.enc` (et
`cle_api_tripo.enc` pour Tripo), **chiffrée avec ton compte Windows** — illisible sur une autre
machine ou par quelqu'un d'autre. Ces fichiers apparaissent uniquement en local après usage, ne
sont **jamais** à partager, et ne sont pas versionnés ici (voir `.gitignore`).

## Coût

Environ 20 crédits Meshy par figurine (Retexture + Multi-Color Print), ~10 avec l'option `.obj`
(pas de Multi-Color Print). Côté Tripo, environ 20 crédits par figurine au total (import +
texturation + conversion), sur une échelle de crédits séparée de celle de Meshy. Une estimation
s'affiche avant de lancer, et le solde réel est vérifié juste avant le traitement.

## Fonctionnalités

- Choix d'un dossier (recherche récursive) ou de fichiers individuels, avec case "Inclure" par
  fichier pour en exclure certains avant de lancer
- Glisser-déposer un dossier ou des fichiers 3D directement sur la fenêtre
- **Comparer Meshy et Tripo** sur chaque fichier (case à cocher, nécessite les deux clés) :
  résultats côte à côte, suffixés `_meshy`/`_tripo` pour ne jamais s'écraser
- Annuler en cours de traitement, relancer uniquement les fichiers en échec
- Avertissement avant d'écraser un résultat déjà présent, ou historique horodaté (rien n'est
  jamais écrasé) avec la case correspondante
- Historique des lots consultable (date, réussites, échecs, crédits consommés)
- Fichier de plus de 50 Mo (limite Meshy) refusé avant l'envoi
- Barre de progression + temps écoulé + notification Windows à la fin
- Bouton "Enreg. journal" pour sauvegarder le détail complet d'un lot
- Dernier prompt personnalisé mémorisé d'un lancement à l'autre

## Si un fichier échoue

Le traitement continue avec les fichiers suivants plutôt que de tout arrêter ; le bilan final
indique combien ont réussi et combien ont échoué, avec le détail de chaque échec dans le journal.

## Alternative : ligne de commande

Pour qui préfère la ligne de commande, `coloriser_stl.py` (Python, variable d'environnement
`MESHY_API_KEY`) et `Coloriser-STL.ps1` (PowerShell, console) font la même chose sans interface
graphique.

## Historique

Voir [CHANGELOG.md](CHANGELOG.md) pour le détail du développement, session par session.
