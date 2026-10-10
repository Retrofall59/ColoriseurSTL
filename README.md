# ColoriseurSTL

Appli Android pour coloriser automatiquement un ou plusieurs fichiers 3D (`.stl`, `.obj`, `.fbx`,
`.glb`, `.gltf` — pas le `.3mf`, qu'aucun des deux fournisseurs n'accepte en entrée) via Meshy ou
Tripo au choix, et sortir des `.3mf` prêts à trancher. Portage direct de la version
PowerShell/Windows du même nom, déjà validée en conditions réelles pour les deux fournisseurs.

Renseigne la clé d'au moins l'un des deux dans Paramètres ; un menu sur l'écran principal permet
de choisir lequel utiliser pour chaque lot. Différence de fond à connaître : Meshy utilise une
palette fixe à N couleurs, Tripo encode la couleur par sommet du maillage (dégradé continu) —
résultats visuellement différents selon le fournisseur choisi. Le solde de crédits API Tripo est
séparé des crédits Tripo Studio (le site web) : vérifie sur platform.tripo3d.ai/billing.

**Partir d'une image plutôt que d'un modèle 3D (v0.15)** : le dossier source peut aussi contenir
des images (`.jpg`, `.jpeg`, `.png`) mélangées avec des fichiers 3D, détectées automatiquement par
leur extension. Pour une image, l'appli lance d'abord "Image to 3D" chez Meshy (maillage seul),
puis enchaîne sur la colorisation habituelle - +20 crédits environ par image, en plus du coût de
colorisation. Meshy uniquement pour le moment (pas encore pris en charge côté Tripo).

**Constaté par Tomyn (2026-10-08) : partir d'une image donne un résultat nettement plus fidèle**
qu'un STL fourni directement - probablement parce que le maillage généré par Image to 3D a un UV
pensé dès le départ pour recevoir une texture automatique, alors qu'un STL fourni directement n'a
souvent jamais été conçu pour ça (pensé pour une impression mono-couleur ou pour être repeint à
la main).

## ⚠️ À savoir avant d'utiliser

- **Un compte Meshy PRO est obligatoire.** Le plan Free n'a pas accès à l'API Meshy.
- **Une clé API Meshy est nécessaire** (gratuite à générer une fois Pro, sur meshy.ai/settings/api),
  à renseigner dans l'écran Paramètres.
- **Chaque figurine consomme environ 20 crédits Meshy** (confirmé à l'usage, pour les deux étapes
  Retexture et Multi-Color Print).
- **Cette appli a besoin d'Internet**, contrairement aux quatre lecteurs RFID de la même série qui
  sont volontairement 100% hors ligne — changement de philosophie assumé, pas un oubli.

## ⚠️ Statut

**v0.1 à v0.3 confirmées fonctionnelles sur un vrai appareil**, deux bugs réels trouvés et
corrigés en conditions réelles (rotation d'écran, galerie qui disparaissait après un visualiseur
externe). **La v0.4 change d'architecture** (service en premier plan plutôt qu'un simple thread) —
compilation complète vérifiée (zéro avertissement dans le code du projet), mais cette
architecture précise n'a pas encore été testée sur un appareil. Voir le CHANGELOG pour le détail.

## Fonctionnalités

- Choix d'un dossier (recherche récursive dans les sous-dossiers) ou de fichiers individuels,
  avec case à cocher par fichier pour en exclure certains avant de lancer
- Choix du dossier de sortie (Storage Access Framework, persiste entre les lancements)
- Galerie de vraies vignettes pour les STL de départ (rendu fait maison, même moteur que la
  version Windows : lecture binaire/ASCII, projection isométrique, ombrage simple) et pour les
  résultats colorisés (image d'aperçu fournie directement par Meshy)
- Menu de styles prédéfinis + prompt personnalisable (le dernier prompt libre est mémorisé)
- **Le traitement tourne dans un vrai service Android en premier plan** : continue même si
  l'appli est complètement fermée, avec une notification système affichant la progression
- Vérification de la clé API et du solde Meshy avant de lancer
- Estimation du coût affichée avant de lancer
- Annulation en cours de traitement
- Relance uniquement des fichiers en échec, sans retraiter tout le lot
- Historique des lots consultable (date, réussites, échecs, crédits réels consommés)
- Réglage "Wi-Fi uniquement" pour éviter de consommer du forfait data sans y penser
- Appui long sur un résultat pour le partager directement (Bluetooth, cloud, messagerie...)
- Bouton "Annuler" directement sur la notification de progression
- Vérification d'espace disque avant de lancer (estimation approximative)
- Clé API stockée chiffrée (EncryptedSharedPreferences, équivalent Android du chiffrement par
  compte Windows utilisé côté PowerShell)

## Distribution

Comme pour les quatre lecteurs RFID : zip complet du dépôt à uploader sur GitHub, ce qui
déclenche la compilation automatique de l'APK via GitHub Actions.

## Historique des versions

Voir [CHANGELOG.md](CHANGELOG.md).
