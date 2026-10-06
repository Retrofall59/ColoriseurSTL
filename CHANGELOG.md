# Changelog

## v0.9 (build 9)

**Intégration Tripo portée depuis la version Windows**, où le pipeline a été confirmé
fonctionnel jusqu'à l'étape de texturation (réservation d'upload, envoi du fichier, création de
tâche, suivi de progression - tous confirmés avec de vraies clés/crédits sur de vrais fichiers).
La toute dernière étape (conversion en 3MF) n'a pas encore été vue aboutir : les échecs
rencontrés venaient d'erreurs internes au serveur Tripo lui-même, pas d'un problème dans nos
appels.

- Deux clés API possibles dans Paramètres (Meshy, Tripo), chacune optionnelle individuellement -
  au moins une des deux est obligatoire, peu importe laquelle.
- Menu "Fournisseur à utiliser" sur l'écran principal, ne propose que ceux dont une clé est
  renseignée.
- Nouveau client `TripoApiClient.kt` : réservation d'upload, envoi du fichier (upload avec
  longueur fixe explicite plutôt qu'un envoi fragmenté - évite le problème rencontré côté
  Windows avec Invoke-WebRequest, corrigé là-bas avec WebClient), texturation, conversion en 3MF
  coloré (couleur par sommet, pas de palette fixe comme Meshy).
- Vérification de clé/solde désactivée côté Tripo (même choix que Windows : l'endpoint deviné
  posait problème, pas essentiel au fonctionnement réel).

## v0.8 (build 8)

- **Corrigé : aperçu en "nuage de points" sur les maillages très denses.** Bug réel trouvé et
  corrigé côté Windows sur un vrai fichier (~2 millions de faces), même correctif porté ici à
  l'identique : l'ancien allègement ("un triangle sur N dans l'ordre du fichier") laissait des
  trous partout sur un maillage dense, car des triangles voisins sur la surface ne sont pas
  forcément voisins dans le fichier. Remplacé par une répartition en grille spatiale 3D, et le
  seuil de déclenchement est monté à 5 millions de triangles (un maillage de ~2M s'est rendu en
  entier en 14,6 secondes sur Windows, sans besoin de réduction).
- Pas de changement lié à Tripo dans cette version : son intégration n'a pas encore eu de test
  réussi de bout en bout côté Windows (tâches qui échouent côté serveur Tripo pour une raison
  encore inconnue), donc volontairement pas encore portée ici, comme convenu.
- Le correctif ci-dessus n'a pu être compilé et vérifié que par recoupement avec la version
  Windows (où il a été testé en vrai sur de vrais fichiers) - comme toujours, le rendu graphique
  Android lui-même reste impossible à exécuter en dehors d'un appareil réel depuis cet
  environnement.

## v0.7 (build 7)

- **Nouveaux formats acceptés** : en plus du `.stl`, l'appli accepte maintenant `.obj`, `.fbx`,
  `.glb` et `.gltf` (formats confirmés dans la doc officielle de l'API Meshy). Le `.3mf` n'est
  **pas** supporté en entrée - Meshy ne l'accepte qu'en sortie, jamais comme source.
- **Vrai rendu ajouté pour l'OBJ** (vignettes de départ), même logique que le STL. Pour
  `.fbx`/`.glb`/`.gltf` : pas de tentative de rendu local (formats trop complexes pour un
  parseur maison fiable), le placeholder "pas d'aperçu" s'affiche à la place - le fichier se
  colorise quand même normalement par ailleurs.
- Côté Windows (même projet), le même ajout a pu être **réellement exécuté et vérifié
  visuellement** grâce à un compilateur C# installé en cours de route - première vraie
  vérification visuelle de ce moteur de rendu sur tout ce projet. La version Android utilise la
  même logique (portée en Kotlin), mais reste, comme toujours, seulement compilée ici, jamais
  exécutée sur un appareil réel par mes soins.

## v0.6 (build 6)

- Nouveau réglage **"Wi-Fi uniquement"** (Paramètres) : bloque le lancement d'un lot si la
  connexion active est facturée au volume (vérifie techniquement l'absence de la capacité
  NOT_METERED, pas littéralement le Wi-Fi - couvre aussi un partage de connexion illimité ou une
  connexion filaire, et exclut un Wi-Fi facturé au volume si l'appareil le signale comme tel).
- **Appui long sur une vignette de résultat** : ouvre le vrai menu de partage Android (Bluetooth,
  cloud, messagerie...) plutôt que seulement l'ouverture dans un visualiseur.
- Corrigé : le texte "À propos" affichait encore l'ancien chiffre de 40 crédits/figurine au lieu
  de 20 (confirmé depuis).

## v0.5 (build 5)

**v0.4 confirmée fonctionnelle sur un vrai appareil** (service en premier plan, premier retour
positif).

- Bouton "Annuler" directement sur la notification de progression, pas besoin de rouvrir l'appli.
- Vérification de l'espace disque avant de lancer un lot (estimation approximative sur le
  stockage principal de l'appareil - Storage Access Framework ne permet pas de connaître
  précisément l'espace libre d'un dossier choisi via SAF, limite honnête à connaître).
- Message ponctuel (une seule fois) invitant à exempter l'appli de l'optimisation de batterie sur
  les téléphones à la gestion énergétique agressive (Xiaomi, Huawei...), qui peuvent arrêter un
  service en premier plan malgré les garanties normales d'Android.

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
