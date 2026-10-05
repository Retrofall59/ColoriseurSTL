# ColoriseurSTL

Appli Android pour coloriser automatiquement un ou plusieurs fichiers STL via l'IA de Meshy, et
sortir des `.3mf` prêts à trancher (profil Bambu intégré). Portage direct de la version
PowerShell/Windows du même nom, déjà validée en conditions réelles.

## ⚠️ À savoir avant d'utiliser

- **Un compte Meshy PRO est obligatoire.** Le plan Free n'a pas accès à l'API Meshy.
- **Une clé API Meshy est nécessaire** (gratuite à générer une fois Pro, sur meshy.ai/settings/api),
  à renseigner dans l'écran Paramètres.
- **Chaque figurine consomme des crédits Meshy** (environ 40 crédits pour les deux étapes,
  Retexture puis Multi-Color Print).
- **Cette appli a besoin d'Internet**, contrairement aux quatre lecteurs RFID de la même série qui
  sont volontairement 100% hors ligne — changement de philosophie assumé, pas un oubli.

## ⚠️ Statut

**Compilation complète vérifiée** (stubs des bibliothèques Android reconstruits, même discipline
que les autres projets), mais **jamais testée sur un vrai appareil Android** à ce stade — c'est
un portage de la version Windows (elle-même testée avec succès), pas une appli construite et
validée de zéro comme les quatre lecteurs RFID. Premier vrai test à faire.

## Fonctionnalités

- Choix d'un dossier (recherche récursive dans les sous-dossiers) ou de fichiers individuels
- Choix du dossier de sortie (Storage Access Framework, persiste entre les lancements)
- Galerie de vraies vignettes pour les STL de départ (rendu fait maison, même moteur que la
  version Windows : lecture binaire/ASCII, projection isométrique, ombrage simple) et pour les
  résultats colorisés (image d'aperçu fournie directement par Meshy)
- Menu de styles prédéfinis + prompt personnalisable
- Traitement en arrière-plan (l'appli reste utilisable pendant le traitement)
- Clé API stockée chiffrée (EncryptedSharedPreferences, équivalent Android du chiffrement par
  compte Windows utilisé côté PowerShell)

## Distribution

Comme pour les quatre lecteurs RFID : zip complet du dépôt à uploader sur GitHub, ce qui
déclenche la compilation automatique de l'APK via GitHub Actions.

## Historique des versions

Voir [CHANGELOG.md](CHANGELOG.md).
