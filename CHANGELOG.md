# Changelog

## v0.4 (build 4)

**Changement d'architecture important** : le traitement tourne maintenant dans un vrai service
Android en premier plan (`ColorisationService`), plus dans un simple thread attaché à l'écran.
Concrètement : le traitement continue même si tu quittes complètement l'application (retirée de
la liste des tâches récentes) - ce que même le correctif de la v0.3 ne couvrait pas (il protégeait
contre un écran recréé, pas contre une appli totalement fermée). Une vraie notification Android
accompagne le traitement (obligatoire pour ce type de service) avec la progression en direct.

Portage des fonctions de la version Windows :
- Case à cocher par fichier pour exclure un fichier avant de lancer, "Tout cocher/décocher"
- Estimation du coût affichée (20 crédits/figurine, confirmé à l'usage)
- Vérification de la clé API et du solde avant de lancer (distingue clé invalide de panne réseau)
- Annulation en cours de traitement
- Relancer uniquement les fichiers en échec
- Historique des lots consultable (date, réussites, échecs, crédits réels consommés)
- Barre de progression visuelle

**⚠️ Changement le plus risqué de tout ce projet** : l'architecture par service en premier plan
n'a jamais pu être testée ici (nécessite un vrai appareil - permissions runtime, comportement du
gestionnaire de notifications, cycle de vie du service selon la version d'Android). Compilation
complète vérifiée (zéro avertissement dans le code du projet), mais c'est la pièce la plus
complexe tentée sur ce projet et la confiance réelle viendra du premier test terrain. Point
particulier à surveiller : l'icône de la notification utilise le logo de l'appli en couleur plutôt
qu'une silhouette blanche simple (convention Android pour la barre de statut) - pourrait
s'afficher bizarrement selon la version d'Android, purement cosmétique si c'est le cas.

## v0.3 (build 3)

- Corrige : la galerie de résultats (et celle des fichiers de départ) disparaissait entièrement
  après avoir ouvert un fichier dans un visualiseur 3D externe puis être revenu dans l'appli —
  signalé en conditions réelles, reproductible à chaque fois. Cause différente du bug de rotation
  (déjà corrigé en v0.2) : un visualiseur externe gourmand en mémoire peut faire tuer notre
  activité en arrière-plan par Android pour libérer de la RAM, ce que `configChanges` ne couvre
  pas (il ne gère que les changements de configuration, pas les arrêts pour cause de mémoire).
  Les deux galeries sont maintenant reconstruites automatiquement au retour, à partir de données
  conservées indépendamment de l'instance d'écran détruite.
- Un vrai bug de compilation trouvé et corrigé pendant l'écriture de ce correctif (visibilité
  Kotlin : une propriété publique ne peut pas exposer un type privé) - détecté par la compilation
  réelle avant livraison, pas par relecture seule.

## v0.2 (build 2)

**Confirmé fonctionnel sur un vrai appareil** (premier retour terrain positif).

- Corrige : une rotation d'écran pendant le traitement coupait la progression et perdait tout
  l'état (galerie, journal) — Android détruisait et recréait l'activité par défaut, alors que le
  thread de traitement continuait en fond à mettre à jour une interface qui n'existait plus.
  `android:configChanges` empêche maintenant la recréation de l'activité à la rotation.

## v0.1 (build 1)

Portage Android de la version PowerShell/Windows "Coloriser-STL", déjà validée en conditions
réelles. Première version, **jamais testée sur un vrai appareil Android**.

- Lecture de dossier (récursive) ou de fichiers individuels via Storage Access Framework.
- Rendu STL fait maison (même moteur que la version Windows), galerie de vignettes pour les
  fichiers de départ et pour les résultats colorisés (aperçu fourni par Meshy).
- Appels à l'API Meshy (Retexture puis Multi-Color Print), mêmes paramètres que la version
  Windows (4 couleurs par défaut, style "cartoon", profil Bambu).
- Menu de styles prédéfinis + prompt personnalisable (mêmes presets que la version Windows).
- Clé API stockée chiffrée (EncryptedSharedPreferences).
- **Corrigé avant la première livraison** (trouvé par vérification mathématique indépendante, pas
  par test réel — voir `tests/`) : l'échelle du rendu se basait sur la boîte englobante *avant*
  rotation plutôt qu'après, ce qui coupait les coins du rendu sur des formes anguleuses (jusqu'à
  19% hors cadre mesuré sur un cube de test). Ce même bug existe dans la version Windows (masqué
  jusqu'ici par des modèles aux formes plutôt organiques) - à corriger là-bas aussi.
