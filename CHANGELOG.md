# Changelog

## Windows (22/10/2026, correctif) : .3mf peint Tripo coupe en deux par le plateau Bambu Studio

Apres le correctif d'echelle (ci-dessous), Tomyn a teste avec un nouveau modele (voiture) :
screenshot Bambu Studio montrant l'objet coupe en deux par le plateau (la moitie basse invisible,
sous le niveau du plateau) avec l'avertissement "Les objets suivants sont places au-dessus...".

- Cause : l'export Tripo CENTRE le maillage sur l'origine (verifie sur le vrai fichier du chien :
  Z de -63,2 a +63,2mm apres mise a l'echelle) au lieu de le poser avec son point le plus bas a
  Z=0, comme un objet pret a imprimer. La moitie du modele se retrouvait donc sous le plateau.
- Corrige : recentrage de X et Y sur l'origine (deja a peu pres le cas, desormais garanti) et
  translation de Z pour que le point le plus bas du maillage touche exactement 0.
- Teste : nouveau test dedie (`test_pose_plateau.ps1`, bac a sable puis rejoue contre le code reel
  extrait) sur un petit objet synthetique deliberement decentre en X/Y/Z - verifie Z minimum = 0 et
  centrage X/Y symetrique. Suite complete existante rejouee sans regression. Bout en bout sur le
  vrai fichier du chien : Z va desormais de 0 a 126,4mm (au lieu de -63,2 a +63,2), X/Y toujours
  centres, 16 couleurs toujours presentes - reverifie independamment en Python.
- **Pas encore confirme dans Bambu Studio lui-meme** (pas d'acces direct au logiciel) - a verifier
  par Tomyn sur son prochain test.

## Windows (22/10/2026, correctif) : .3mf peint Tripo minuscule (puis demesure) sur le plateau Bambu Studio

En testant le .3mf avec le correctif des metadonnees BambuStudio (16 couleurs bien affichees,
confirme par Tomyn screenshot a l'appui), le modele apparaissait MINUSCULE sur le plateau.

- Cause : l'export .obj de Tripo (via Blender) sort des coordonnees SANS unite physique reelle -
  verifie sur deux vrais fichiers de Tomyn : le plus grand cote du maillage brut vaut quasiment
  exactement 1.0, quel que soit le modele. Tripo normalise sa geometrie dans une boite ~1x1x1,
  copiees telles quelles dans un .3mf qui declare "unit=millimeter" -> Bambu Studio interpretait
  un objet de longueur "1.0" comme 1 MILLIMETRE.
- Premiere tentative (facteur fixe x1000, en supposant des coordonnees en metres) : fausse piste -
  verifie que ca donnait au contraire un objet de PRES D'1 METRE (toujours faux, juste dans l'autre
  sens). Pas de "bonne" taille deductible du fichier source lui-meme, il n'y a aucune reference
  d'echelle dans une generation IA depuis une seule image.
- Corrige : reutilisation du champ UI existant "Taille d'impression prevue (plus grand cote, mm)"
  ($numTailleImpression, deja cable pour l'analyse d'imprimabilite Meshy) - le maillage Tripo est
  maintenant mis a l'echelle pour que son plus grand cote corresponde a cette valeur, avec le meme
  defaut de repli que cote Meshy (150mm) si le champ est laisse a 0. Parametre ajoute de bout en
  bout : `Convertir-ObjColoreVers3mfPeint` -> `Coloriser-UnFichierTripo` -> les deux sites d'appel
  (lot normal et lot Meshy+Tripo compare cote a cote).
- Teste : nouveau test dedie (`test_echelle.ps1`, bac a sable puis rejoue contre le code reel
  extrait) verifiant le defaut 150mm et deux tailles demandees explicitement (80mm, 300mm) sur un
  petit objet synthetique normalise comme Tripo. Suite complete existante rejouee sans regression.
  Bout en bout sur le vrai fichier de Tomyn (706567 sommets / 1413194 triangles) : sortie
  reverifiee independamment en Python - plus grand cote exactement 150,0mm (defaut), structure
  BambuStudio toujours valide (16 couleurs, model_settings.config coherent).
- **Pas encore confirme dans Bambu Studio lui-meme** (pas d'acces direct au logiciel depuis cet
  environnement) - a verifier par Tomyn, en particulier que 150mm est une taille de depart
  raisonnable pour ses propres modeles (ajustable via le champ existant si besoin).

## Windows (22/10/2026, hypothese non confirmee) : .obj Tripo genere par l'appli moins bien regroupe par Bambu que celui du site web Tripo

Apres le correctif des metadonnees BambuStudio (voir entree suivante), Tomyn a teste le .3mf
genere par une version pas encore mise a jour (mon erreur : j'avais pousse sur GitHub mais pas
renvoye le fichier .ps1 lui-meme dans cette conversation - verifie directement dans le .3mf
qu'il a teste : pas de metadonnee `Application`, `project_settings.config` encore a l'ancien
format 181 octets). Une fois le bon fichier envoye, reste un probleme distinct remonte sur le
`.obj` brut (pas le `.3mf`) : la boite "Modele d'importation" de Bambu Studio (regroupement
auto des couleurs par sommet en N filaments, 4/8/16 + bouton Appliquer) reste quasi plate sur le
.obj genere par l'appli, meme a 16 couleurs + Appliquer, alors que le MEME .obj genere directement
via le site web Tripo (meme image source confirmee par Tomyn : "l'image est la meme") s'y
regroupe correctement.

- Comparaison octet pour octet des deux fichiers reels (statistiques RGB/teinte/saturation,
  nombre de sommets orphelins, presence de materiaux/coordonnees UV, nettete des transitions de
  couleur entre sommets voisins adjacents) : aucune difference franche trouvee qui expliquerait a
  coup sur le comportement different de l'algo de regroupement de Bambu Studio - cet algo est
  proprietaire/ferme, pas de moyen de le debugger directement depuis cet environnement.
- Hypothese testee (PAS CONFIRMEE par une vraie generation - pas d'acces a la cle API Tripo de
  Tomyn pour tester sans consommer ses credits) : `pbr` vaut `true` par defaut chez Tripo pour
  `/generation/image-to-model` (confirme dans leur documentation officielle), et mon code le
  forcait explicitement a `true` sur le chemin "image sans prompt" (`pbr = $AvecTexture`). Un
  materiau PBR (cartes couleur/rugosite/normale projetees en UV, pense pour un rendu realiste
  shade) pourrait exporter moins bien en simple couleur-par-sommet qu'une texture "standard"
  classique - le site web Tripo ne force peut-etre pas ce mode par defaut pour une generation
  simple image -> modele.
- Change : `pbr` force explicitement a `$false` sur les deux chemins de texturation Tripo
  (`Lancer-ImageModelTripo` ET l'appel `/models/texture` separe pour le cas "avec prompt", qui
  n'envoyait meme pas ce champ avant et dependait donc du defaut serveur - potentiellement `true`
  aussi).
- **A confirmer par Tomyn avec une vraie generation** : ni la cause (hypothese PBR) ni l'effet du
  changement n'ont pu etre verifies ici. Si le probleme persiste malgre ce changement, la vraie
  cause est ailleurs et il faudra regarder autre chose (peut-etre directement cote Tripo, hors de
  mon controle).
- Rappel important independant de ce bug : la boite "Modele d'importation" ne concerne QUE
  l'ouverture d'un `.obj` brut dans Bambu Studio - elle ne s'applique jamais au `.3mf` genere
  automatiquement par l'appli a cote (qui ecrit les couleurs directement, sans recourir a cet
  algo). Le `.3mf` reste le livrable recommande, independamment de ce que fait ou ne fait pas
  cette boite de dialogue sur le `.obj`.

## Windows (21/10/2026, correctif) : Bambu Studio n'affichait que 4 couleurs - usurpation de metadonnees BambuStudio

Suite au correctif precedent (seeding k-means), Tomyn a remonte que meme avec un fichier aux
couleurs correctement variees, Bambu Studio continuait a n'afficher que 4 couleurs dans le
viewport (4 ou 16 couleurs demandees, meme resultat), alors que le Melangeur en detectait bien 16
dans le fichier. Il avait raison de corriger ma premiere explication (hypothese `<m:colorgroup>`/
`pid`/`p1`) : "OUI MAIS AVEC MESHY PAS LE PROBLEME PK AVEC TRIPO IL YA LE PROBLEME DONC CE QUE TU
DIS NA RIEN A VOIR" - si Meshy n'a jamais ce probleme via l'appli, l'explication "Bambu Studio
ignore TOUJOURS les reglages d'un fichier tiers, point final" ne pouvait pas etre la bonne.

- Cause reelle, trouvee en comparant octet pour octet un vrai .3mf Meshy fonctionnel (fourni par
  Tomyn) a ma propre sortie : Bambu Studio applique `Metadata/project_settings.config` (la
  palette de filaments) UNIQUEMENT si `3D/3dmodel.model` declare
  `<metadata name="Application">BambuStudio-X.X.X.X</metadata>`. Sans cette declaration, Bambu
  Studio charge "geometrie et couleurs uniquement" et retombe sur les 4 filaments par defaut du
  projet en cours - c'est exactement le dialogue "configuration invalide, chargement des donnees
  geometriques uniquement", documente et volontaire cote Bambu (trackers #7775, #2491), jamais un
  bug chez moi. Le fichier Meshy fonctionne parce que Meshy, lui, se declare bien comme
  BambuStudio - mon fichier Tripo ne le faisait pas.
  - Piege en se declarant "BambuStudio-..." : `Metadata/model_settings.config` devient alors
    OBLIGATOIRE - son absence ou une erreur dedans fait echouer le chargement ENTIER du fichier
    ("Archive does not contain a valid model config"), pas juste la palette. D'ou la prudence du
    correctif precedent qui n'avait pas ose toucher a ca sans connaitre le schema exact.
  - Confirme aussi, en comparant au fichier Meshy : le mecanisme de peinture par triangle reste le
    meme que deja implemente (`paint_color` en hexa, pas de `<m:colorgroup>`/`pid`/`p1` - zero
    occurrence de `pid=` dans le vrai fichier Meshy, mon hypothese precedente etait fausse) ; les
    couleurs de `project_settings.config` doivent etre en hexa RGBA 8 chiffres
    (`#672A17FF`), pas RGB 6 chiffres comme avant.
- Corrige : deux nouvelles fonctions, `Construire-ProjectSettingsBambu` (JSON complet a 36 cles,
  calque sur le vrai fichier Meshy - couleurs RGBA, `filament_settings_id`, matrice/vecteur de
  purge dimensionnes sur N couleurs, `printer_model`, etc.) et `Construire-ModelSettingsBambu`
  (XML minimal mais valide : objet id=1, nombre de faces reel, plateau). `3D/3dmodel.model`
  declare desormais `Application: BambuStudio-02.03.01.00` plus les metadonnees
  `BambuStudio:3mfVersion`/`BambuStudio:MmPaintingVersion`.
- Teste : nouveau test dedie (`test_schema_bambu.ps1`, bac a sable puis rejoue contre le code reel
  extrait de `Coloriser-STL-GUI.ps1`) verifiant la presence et la coherence des deux fichiers de
  metadonnees. Suite complete existante rejouee sans regression (cube, index negatifs, pas de BOM,
  slashs du zip - ces deux derniers etendus pour couvrir le nouveau `model_settings.config`,
  format RGBA). Bout en bout sur le vrai fichier de Tomyn (706567 sommets / 1413194 triangles,
  k=16) : 89,3s, puis le .3mf resultant reverifie independamment avec Python (zipfile +
  ElementTree + json) - 5 fichiers du paquet presents, aucun BOM, XML/JSON bien formes, 16
  couleurs RGBA presentes, `model_settings.config` reference bien l'objet id=1 avec le bon nombre
  de faces.
- **Pas encore confirme dans Bambu Studio lui-meme** : comme tout ce qui touche a ce logiciel, je
  n'ai pas d'acces direct a Bambu Studio depuis cet environnement - cette correction a ete validee
  par analyse de fichier (structure, contenu, comparaison au fichier Meshy de reference) mais pas
  par un chargement reel. A confirmer par Tomyn.

## Windows (21/10/2026, correctif) : palette k-means "trop approchante" - mauvaise initialisation des clusters

Suite au lissage, Tomyn a teste avec 16 couleurs demandees sur un vrai modele Tripo (chien) :
l'outil Melangeur de couleurs detectait bien 16 valeurs distinctes dans le fichier, mais "tres
approchantes" les unes des autres - aucune ne representait vraiment le noir de la tete ou le
marron-rouge du collier, qui dominent visuellement mais sont minoritaires en nombre de triangles.

- Cause : l'initialisation des centres de depart du k-means parcourait l'echantillon dans son
  ORDRE DE FICHIER (indices equirepartis), pas selon la diversite des couleurs. Sur un maillage ou
  une seule couleur domine en nombre de triangles (le pelage beige), la plupart des germes
  atterrissaient dans cette zone et le k-means convergeait vers plusieurs centres quasi identiques
  au lieu de capturer les couleurs minoritaires mais visuellement importantes.
- Corrige : remplace par un "farthest-point seeding" deterministe (variante sans alea de
  k-means++) - le premier germe est le premier point de l'echantillon, puis chaque germe suivant
  est le point le plus eloigne en couleur de tous les germes deja choisis. Garantit des centres de
  depart bien repartis sur toute la diversite de couleurs, quel que soit k.
- Nouveau test dedie (`test_seeding_kmeans.ps1`, bac a sable) : distribution tres desequilibree
  (95% d'une couleur dominante, deux couleurs minoritaires tres differentes) - verifie que les 2
  couleurs minoritaires sont bien retrouvees par un centre proche, pas absorbees par la dominante.
- Verifie sur le vrai fichier de Tomyn avec k=16 : palette resultante nettement plus variee
  (gris fonces, beige, rouge-brun pour le collier...) au lieu de nuances quasi identiques de beige.
  93,8s de conversion, toujours dans un budget raisonnable.
- **Important, pas encore resolu** : Tomyn a aussi remonte que Bambu Studio n'affiche que 4
  couleurs dans le viewport quel que soit le nombre demande (4 ou 16), alors que le Melangeur en
  detecte bien 16 dans le fichier. C'est un probleme SEPARE de celui-ci : le fichier n'a pas de
  balise `<metadata name="Application">BambuStudio-...</metadata>` dans `3D/3dmodel.model`, donc
  Bambu Studio desactive le chargement de la configuration projet (mon `project_settings.config`
  avec la palette) et affiche uniquement les 4 filaments deja configures par defaut dans le projet
  ("configuration invalide, chargement des donnees geometriques uniquement"). Corriger ca
  proprement demande d'ajouter cette metadonnee ET un `Metadata/model_settings.config` valide
  (sinon, une fois la metadonnee "BambuStudio-" ajoutee, l'absence de ce fichier devient une
  erreur FATALE qui bloquerait le chargement entier). Pas encore tente - risque de regression trop
  eleve pour l'improviser sans mieux connaitre le schema exact attendu par Bambu Studio.

## Windows (21/10/2026, amélioration) : couleurs "à l'arrache" - lissage par vote majoritaire + nombre de couleurs configurable

Retour de Tomyn apres avoir enfin pu ouvrir un .3mf peint : "les couleurs sont pas tres bien
definies, on dirait qu'il a fait ca a l'arrache". Deux changements :

- Le nombre de couleurs pour la colorisation Tripo utilise desormais le reglage "Nombre de
  couleurs" de l'interface (`$numCouleurs`, deja utilise pour Meshy) au lieu d'un `8` fixe code
  en dur.
- Les couleurs de sommet exportees par Tripo integrent l'ombrage du rendu (pas des couleurs
  "materiau" plates), donc la simple moyenne par triangle + k-means produisait des affectations
  bruitees : des triangles isoles mal classes au milieu d'une zone par ailleurs uniforme. Ajout
  d'un lissage par vote majoritaire entre triangles adjacents (partageant une arete) : un
  triangle isole adopte la couleur de ses voisins si au moins 2 de ses (jusqu'a 3) voisins la
  partagent - les vraies frontieres de couleur, qui ont toujours une majorite de voisins du meme
  cote, ne sont pas effacees.
- Adjacence calculee en O(n) via un hachage d'aretes (pas de liste d'aretes materialisee), et
  lissage par comparaisons manuelles (pas de pipeline `Group-Object`/`Where-Object` par triangle,
  bien trop lent a l'echelle du million de triangles).
- Teste : 3 fixtures dediees (triangle isole corrige vers la couleur majoritaire des voisins ;
  triangles deja corrects inchanges ; vraie frontiere de couleur preservee), plus la suite
  complete existante (cube, index negatifs, pas de BOM, slashs du zip) rejouee contre le code tel
  qu'il est livre dans `Coloriser-STL-GUI.ps1`.
- Performance : +14s sur le vrai fichier de Tomyn (706567 sommets / 1413194 triangles) par
  rapport a la version sans lissage - 74s a 87,7s au total, toujours tres en dessous du seuil qui
  bloquait l'UI avant la reecriture complete du moteur.
- Honnetete : le lissage reduit mathematiquement le bruit visible (triangles isoles corriges),
  mais je n'ai pas de moyen de verifier le rendu visuel final dans Bambu Studio depuis ici - reste
  a confirmer chez Tomyn si le resultat parait moins "a l'arrache".

## Windows (21/10/2026, correctif) : antislashs dans le zip .3mf (CreateFromDirectory sous Windows) + .rels manquant

Après le correctif du BOM, Tomyn a généré un **nouveau** `.3mf` (nouvelle colorisation Tripo,
pas l'ancien fichier) avec la version corrigée de l'appli, et Bambu Studio a renvoyé
**exactement les mêmes erreurs** ("le chargement du fichier modèle a échoué" / "le fichier ne
contient pas de données géométriques"). Il m'a renvoyé l'`.obj` et le `.3mf` de cette nouvelle
tentative :

- En inspectant les noms d'entrée bruts du zip (`python3 -c "import zipfile; ..."`), les 3
  fichiers du dossier `3D/`, `Metadata/` et `_rels/` étaient nommés avec des **antislashs** :
  `3D\3dmodel.model`, `Metadata\project_settings.config`, `_rels\.rels`. Le format OPC/.3mf exige
  des slashs `/` dans les chemins internes du paquet — avec des antislashs, Bambu Studio ne
  retrouve jamais `3D/3dmodel.model` et traite l'archive comme vide de géométrie.
- Cause : `[System.IO.Compression.ZipFile]::CreateFromDirectory()` nomme chaque entrée avec le
  séparateur de chemin de l'OS qui l'exécute. Sous Linux (mon environnement de test), ça produit
  des slashs par défaut — le bug était donc invisible dans tous mes tests précédents. Sous
  Windows (la machine de Tomyn), ça produit des antislashs.
- Corrigé : le zip est maintenant construit à la main avec `System.IO.Compression.ZipArchive`,
  en forçant explicitement des slashs `/` dans chaque nom d'entrée, quel que soit l'OS.
- Second bug trouvé en écrivant le test pour celui-ci : `Get-ChildItem -Recurse -File` (sans
  `-Force`) ignore silencieusement `_rels/.rels`, car un fichier commençant par un point est
  marqué "caché" par .NET — le `.3mf` se retrouvait donc sans ses relations internes, un autre
  motif de rejet à lui seul. Corrigé avec `-Force`.
- Nouveau test (`test_slashs_zip.ps1`, pas encore dans ce dépôt — vit dans mon bac à sable de
  session) qui vérifie explicitement les noms d'entrée bruts du zip (pas seulement que le contenu
  se relit correctement, ce qui masquait le bug).
- **Vérifié directement sur le `.obj` réel envoyé par Tomyn pour cette nouvelle tentative**
  (706 567 sommets / 1 413 194 triangles), avec le code extrait tel quel de
  `Coloriser-STL-GUI.ps1` : conversion en ~74s, `.3mf` résultant avec les 4 entrées nommées avec
  des slashs, sans BOM, XML intégralement reparsable, 1 seul `<object>` référencé correctement
  par `<build><item>`. C'est la vérification la plus poussée possible sans Bambu Studio
  lui-même — reste à confirmer l'ouverture chez Tomyn.

## Windows (21/10/2026, correctif confirmé) : BOM UTF-8 en tête de fichier, cause réelle du rejet

Suite du correctif précédent (index OBJ négatifs) : Tomyn a régénéré un `.3mf` avec ce correctif,
et Bambu Studio a renvoyé **exactement les mêmes erreurs**. Il m'a envoyé directement le `.obj`
source et le `.3mf` cassé — analyse en conditions réelles plutôt qu'en devinant :

- Le vrai `.obj` de Tomyn (730 372 sommets, 1 460 768 triangles) ne contient **aucun** index
  négatif ni hors bornes : le correctif précédent était un vrai bug (toujours utile), mais pas la
  cause de CE rejet précis.
- Inspection **octet par octet** du `.3mf` cassé envoyé par Tomyn : le fichier `3D/3dmodel.model`
  commençait par `EF BB BF` (un BOM UTF-8) avant `<?xml version="1.0"...`. Le XML lui-même était
  par ailleurs complet et bien formé (aucune troncature, `</model>` final présent).
- Cause : `[System.Text.Encoding]::UTF8` de .NET ajoute automatiquement ce BOM avec
  `WriteAllText` — un piège classique, et un `.3mf` ne doit jamais en contenir un.
- Corrigé : écriture de tous les fichiers du paquet (`3dmodel.model`, `[Content_Types].xml`,
  `_rels/.rels`, `project_settings.config`) avec un encodage UTF-8 explicitement sans BOM.
- **Vérifié directement sur le fichier réel de Tomyn**, avec le code tel qu'il est livré dans
  `Coloriser-STL-GUI.ps1` (extrait et exécuté tel quel, pas une reconstruction) : conversion
  complète du vrai `.obj` (730 372 sommets / 1 460 768 triangles) en ~75 secondes, `.3mf` résultant
  sans BOM confirmé au niveau octet, XML intégralement reparsable (tous les sommets et triangles
  présents). C'est la vérification la plus poussée possible sans Bambu Studio lui-même — reste à
  confirmer que le fichier s'ouvre bien chez Tomyn.

## Windows (21/10/2026, correctif) : le .3mf généré ne s'ouvrait pas dans Bambu Studio

Bug remonté par Tomyn sur son premier vrai test : le `.3mf` généré automatiquement se créait bien
sur le disque mais Bambu Studio refusait de l'ouvrir ("Le chargement du fichier modèle a échoué."
puis "Le fichier ne contient pas de données géométriques." sur deux tentatives).

Recherche effectuée dans le vrai parseur C++ de Bambu Studio (`bbs_3mf.cpp`, dépôt
`bambulab/BambuStudio`) pour comprendre pourquoi, plutôt que de retenter à l'aveugle :
`[Content_Types].xml` et les espaces de noms XML ne sont jamais lus à l'import (écartés comme
cause) ; en revanche, **un seul triangle référençant un index de sommet hors bornes fait rejeter
tout le fichier**, sans indication claire côté utilisateur.

Cause racine trouvée en relisant mon propre code : le format OBJ autorise des index de face
**relatifs négatifs** (`f -1 -2 -3` = les 3 derniers sommets définis jusque-là dans le fichier) —
un cas déjà géré correctement par le rendu de vignette existant de l'appli (`RenduSTL.ChargerObj`,
en C#), mais oublié dans le nouveau convertisseur OBJ→3MF : un index négatif y était traité comme
positif, produisant un index de sommet complètement faux, **sans aucune erreur** (pas d'exception,
juste une géométrie corrompue qui passait inaperçue jusqu'à l'ouverture dans Bambu Studio).

- Corrigé : résolution des index négatifs identique à celle déjà utilisée ailleurs dans l'appli.
- Ajout d'un filet de sécurité indépendant : tout triangle qui référencerait malgré tout un index
  hors bornes (pour une autre raison imprévue) est désormais écarté et journalisé, au lieu de
  produire un `.3mf` que Bambu Studio rejetterait en bloc sans explication.
- **Vérifié par exécution réelle** : nouveaux tests reproduisant exactement ce cas (face exprimée
  avec des index négatifs vs. positifs équivalents → même géométrie ; triangle avec un index très
  hors bornes mélangé à un triangle valide → seul le triangle valide survit, fichier quand même
  généré). Les 19 assertions de correction + le test de charge à 300 000 triangles restent tous
  verts.
- **Ce qui reste incertain** : cette correction explique un bug réel et probable, mais je n'ai pas
  pu confirmer qu'elle était bien LA cause exacte du rejet observé chez Tomyn, faute d'accès à son
  fichier `.obj` original ou au message d'erreur détaillé de Bambu Studio (qui, d'après le code
  source, donne normalement le numéro de ligne XML fautif). À confirmer par un nouvel essai réel.

## Windows (21/10/2026, correctif) : le .3mf généré automatiquement était invisible dans l'appli

Bug remonté par Tomyn : après le correctif de performance ci-dessous, le `.3mf` peint se générait
bien et était bien présent sur le disque (confirmé par Tomyn dans l'Explorateur Windows, 67,2 Mo,
reconnu comme fichier BambuStudio) — mais rien ne le signalait dans l'onglet "Résultats colorisés"
de l'appli, qui n'affichait toujours que la vignette de l'`.obj`.

Correctif : une seconde vignette est maintenant ajoutée automatiquement, juste à côté de celle de
l'OBJ, dès que la conversion en `.3mf` réussit. Cette vignette .3mf récupère au passage les boutons
"Analyser les couleurs..." (vers le Mélangeur) et "Copier desc." déjà prévus pour tout résultat
`.3mf` dans la galerie — pas disponibles sur la vignette OBJ, puisque ces outils ne lisent que des
`.3mf`.

Note technique : le rendu maison des vignettes (`RenduSTL`) ne sait lire que `.obj`/`.stl`, pas
`.3mf` — la nouvelle vignette affiche donc l'image de remplacement générique plutôt qu'un rendu 3D,
sans risque de lenteur sur un maillage énorme (celui testé par Tomyn faisait 1 464 680 triangles).

## Windows (21/10/2026, correctif) : blocage de l'appli sur un gros maillage ("Ne répond pas")

Bug remonté par Tomyn en conditions réelles, sur un lot visant 300 000 triangles : juste après
"Conversion terminée" / "Enregistré : ..." dans le journal, l'appli s'est figée (barre de titre
"Ne répond pas") — exactement au moment où le nouveau convertisseur OBJ→3MF (ci-dessous)
démarrait.

Cause racine : le moteur de conversion (v1) utilisait un objet PowerShell par sommet/triangle et
des pipelines `ForEach-Object`, avec un k-means recalculé sur **tous** les triangles à chaque
itération — jamais testé au-delà de petits fixtures de quelques triangles. À l'échelle réelle
(150 000+ sommets, 300 000 triangles), ce code est des ordres de grandeur trop lent, et comme il
tournait sur le thread principal sans jamais rendre la main à Windows, la fenêtre se figeait.

**Correctif : réécriture complète du moteur pour la performance**, sans changer le comportement
observable :
- tableaux primitifs (`double[]`/`int[]`) au lieu d'un objet par sommet/triangle ;
- le k-means ajuste ses centres sur un **échantillon borné** (20 000 points par défaut,
  déterministe), puis fait une **seule passe linéaire** sur tous les triangles pour l'affectation
  finale — coût indépendant du nombre d'itérations, toujours rapide quelle que soit la taille du
  maillage ;
- pompage périodique des messages Windows (`Application::DoEvents`) dans les boucles longues
  (parsing, clustering, écriture XML), pour que l'appli ne soit plus jamais signalée "Ne répond
  pas" même sur un gros fichier.
- **Vérifié par exécution réelle sur un maillage de 299 538 triangles / 150 544 sommets** (grille
  régulière générée spécifiquement pour reproduire l'échelle du cas de Tomyn) : conversion
  complète (parsing + clustering + écriture + relecture réelle du zip/XML produit) en ~16
  secondes, contre un blocage indéfini avant. Les 19 assertions de correction déjà écrites restent
  toutes vertes sur le nouveau moteur.

## Windows (21/10/2026) : conversion automatique de l'OBJ Tripo en .3mf peint

Bug remonté par Tomyn : utiliser "Suggérer un trio pour ce fichier..." (Mélangeur) sur un `.obj`
généré par Tripo plantait silencieusement (exception `ExtractToDirectory` non rattrapée — voir le
correctif côté melangecouleurs3mf). Cause racine : Tripo livre désormais un OBJ coloré par sommet
(pas un vrai `.3mf`), donc aucun outil de la chaîne ne pouvait en tirer une palette/un dosage.

Demande explicite de Tomyn : convertir lui-même cet OBJ en un vrai `.3mf` peint pour Bambu Studio,
**automatiquement**, immédiatement après chaque colorisation Tripo, déposé à côté du `.obj`.

- Nouveau moteur de conversion (dans `Coloriser-STL-GUI.ps1`, pas dans le Mélangeur — l'automatisme
  doit vivre là où l'OBJ est produit) :
  - lecture de l'OBJ coloré par sommet (lignes `v x y z r g b`, couleur en 0-1 ou 0-255 détectée
    automatiquement ; lignes `f` standard, avec ou sans index texture/normale, triangulation en
    éventail si plus de 3 sommets par face) ;
  - regroupement des couleurs par triangle en au plus 8 teintes (k-means en espace RGB, graine
    déterministe) ;
  - écriture d'un `.3mf` valide : `3D/3dmodel.model` avec l'attribut `paint_color` par triangle
    (encodage confirmé en lisant le vrai code source BambuStudio/OrcaSlicer — `bbs_3mf.cpp` /
    `Model.cpp` — pas une doc tierce) et `Metadata/project_settings.config` avec `filament_colour`
    (même schéma que les `.3mf` réels, lu sans rien changer par le Mélangeur existant).
- Câblé automatiquement dans `Coloriser-UnFichierTripo`, juste après l'extraction de l'OBJ : le
  `.3mf` apparaît dans le même dossier, nommé comme l'OBJ. Un échec de conversion est journalisé
  sans faire perdre le résultat Tripo (l'OBJ reste utilisable tel quel).
- **Vérification effectuée** : analyse syntaxique réelle du fichier complet (aucune erreur), 20
  assertions d'exécution réelle sur le moteur extrait du fichier livré (parsing OBJ avec/sans
  index texture, triangulation de quads, échelles 0-1 et 0-255, clustering, écriture PUIS
  **relecture réelle** du zip/XML produit, encodage `paint_color` vérifié contre les exemples
  documentés du code source Bambu, palette `filament_colour` au format attendu).
- **Ce qui n'a PAS pu être vérifié** : je n'ai pas Bambu Studio sous la main pour ouvrir le `.3mf`
  produit et confirmer à l'oeil que la peinture s'applique correctement à l'AMS. Le format écrit
  correspond exactement à ce que lit le code source réel de Bambu Studio/OrcaSlicer, mais seul un
  premier essai réel de Tomyn validera le résultat.

## v0.29 (build 29) + Windows

**Réactivation de la vérification du solde Tripo** (avant lancement ET en cours de lot), trouvée
en continuant la comparaison systématique Windows/Android après la session précédente : la
fonction existait déjà des deux côtés (`Verifier-CleEtSoldeTripo` / `TripoApiClient.verifierCleEtSolde`),
pointait depuis le 20/10/2026 vers le bon endpoint documenté (`/account/balance`), mais n'était
appelée nulle part — désactivée depuis l'origine à cause d'un blocage de l'UI provoqué par le tout
premier endpoint deviné (jamais confirmé), jamais revérifiée depuis.

- Avant lancement : si Meshy ET Tripo sont utilisés (mode comparaison), les deux soldes sont
  vérifiés et regroupés dans une seule boîte d'avertissement plutôt que deux popups successives.
  Clé invalide : bloquant, message précisant quel fournisseur (Meshy vérifié en premier).
- En cours de lot (tous les 20 fichiers, voir la revérif ajoutée en v0.28/v8.28) : étendue à Tripo
  en plus de Meshy, même principe — avertissement non-bloquant côté Android (journal), boîte
  Oui/Non côté Windows.
- **Pas de test réseau réel effectué** : aucune clé Tripo utilisable n'était disponible pour cette
  session (la capture partagée ne montrait que le Client ID, pas la clé secrète — jamais réaffichée
  par Tripo après sa création). Le raisonnement pour réactiver quand même : le squelette de
  `Verifier-CleEtSoldeTripo`/`TripoApiClient.verifierCleEtSolde` (try/catch, retry réseau, timeout)
  est identique à celui de Meshy, déjà en production sans souci de ce type — le blocage original
  était très probablement dû au endpoint deviné lui-même (jamais confirmé), pas à un défaut
  structurel. **À surveiller au premier vrai lot Tripo lancé après cette mise à jour** — en cas de
  souci, redésactiver est aussi simple qu'avant.
- Vérifié par analyse syntaxique PowerShell réelle du script entier (0 erreur), exécution
  PowerShell réelle de la logique de décision combinée Meshy+Tripo (14 assertions, dont les cas
  cle invalide/solde insuffisant/mode comparaison/intervalle mid-batch), et recompilation Kotlin
  complète contre les stubs (0 erreur sur le nouveau code).

## v0.28 (build 28) + Windows

**Revérification du solde Meshy en cours de lot**, idée proposée en passant et validée par Tomyn
("2-4") pendant une session de recherche d'améliorations : jusqu'ici le solde n'était vérifié
qu'UNE fois avant de lancer tout le lot. Sur un dossier de 250 fichiers payé par le collègue
dessinateur de Tomyn, un dérapage du coût réel (prompts plus gourmands que prévu, options
activées en cours de route) ne se voyait qu'en échouant fichier par fichier une fois le solde
épuisé - trop tard pour agir à temps.

- Tous les 20 fichiers traités (`INTERVALLE_VERIF_SOLDE_LOT`), le solde Meshy RÉEL est revérifié
  et comparé au coût estimé des fichiers RESTANTS (`CREDITS_ESTIMES_PAR_FICHIER` par fichier,
  comme à l'estimation de départ).
- **Windows** : si le solde restant est insuffisant pour couvrir l'estimation, une boîte de
  dialogue Oui/Non interrompt le lot ("Continuer quand même ?") - même pattern que les dialogues
  existants (overlay de progression masqué avant la boîte, ré-affiché seulement si l'utilisateur
  choisit de continuer). Vérifié par analyse syntaxique réelle du script entier (0 erreur) et par
  une exécution PowerShell réelle du calcul de déclenchement (9 assertions, dont les cas limites
  exacts sur un lot de 250 fichiers et la non-déclenchement sur un lot de 15 fichiers).
- **Android** : différence délibérée - `ColorisationService` tourne dans un Service, pas une
  fenêtre WinForms, donc pas de boîte de dialogue bloquante Oui/Non sans complexité
  supplémentaire. À la place, un AVERTISSEMENT non-bloquant est écrit dans le journal (visible
  immédiatement dans l'onglet Avancement) ; Tomyn garde la main via le bouton Annuler déjà
  existant s'il juge que ça vaut le coup d'arrêter. App entière recompilée avec les stubs (0
  erreur sur le nouveau code).

## v0.27 (build 27)

**Temps restant estimé pendant un lot**, porté depuis la version Windows (`Obtenir-TexteEtaLot` /
`Afficher-ProgressionEnCours`) - demandé par Tomyn : son collègue dessinateur lui envoie souvent
des dossiers de 200+ fichiers, où la seule barre de progression ne dit pas combien de temps il
reste à attendre.

- Nouvelle ligne de statut au-dessus de la barre de progression pendant un lot : "Fichier X/Y -
  écoulé : MM:SS - reste ~N min - N credit(s) dépensés" - même recette que côté Windows (moyenne
  glissante : temps écoulé / fichiers déjà faits × fichiers restants). Vide tant qu'aucun fichier
  n'est encore terminé (pas d'estimation fiable sur un seul point de mesure), comme côté Windows.
- Nouveau module `EstimateurEtaLot.kt` (pur Kotlin, sans dépendance Android). Vérifié par
  exécution JVM réelle : 18 assertions, y compris les cas limites exacts (60s, 3600s - bascule
  entre "min" et "h" au bon seuil) - toutes passent. App entière recompilée avec les stubs
  (0 erreur).

## v0.26 (build 26)

**"Sauvegarder ma config..." / "Restaurer ma config..."** portés depuis la version Windows
(`Obtenir-FichiersConfigConnus`) - trouvés en continuant la comparaison systématique
Windows/Android, pas un bug mais une vraie fonctionnalité manquante (Tomyn a dit "go").

- Nouveau bouton "Sauvegarder ma config..." (écran Paramètres) : exporte en ZIP les favoris de
  prompts et l'historique des lots - pour ne pas tout reperdre en changeant de téléphone ou en
  réinstallant l'appli. Les clés API ne sont JAMAIS incluses dans l'export.
- Nouveau bouton "Restaurer ma config..." : réimporte un ZIP de sauvegarde (écrase les fichiers
  existants) ; ignore sans planter tout ZIP qui n'est pas une sauvegarde de cette appli.
- Périmètre volontairement plus restreint que côté Windows : seuls les fichiers du stockage
  PRIVÉ de l'appli sont inclus (ceux réellement perdus à la désinstallation) -
  `historique_fichiers.csv` vit déjà dans le dossier de sortie choisi par l'utilisateur, donc
  hors d'atteinte d'une désinstallation, contrairement à Windows où tout vit au même endroit.
- Nouveau module `SauvegardeConfig.kt` (pur Kotlin, sans dépendance Android). Vérifié par
  exécution JVM réelle avec de vrais fichiers temporaires : 11 assertions (export/import,
  fichier non-connu jamais exporté/importé, écrasement, ZIP étranger sans effet) - toutes
  passent. App entière recompilée avec les stubs (0 erreur).

## v0.25 (build 25)

**Complète le réessai réseau de la 0.24** (même chantier, deux manques trouvés en relisant
`Invoquer-AvecReessaiReseau` côté Windows de plus près) :

- Chaque tentative manquée est maintenant écrite dans le journal visible de l'appli ("... : erreur
  réseau transitoire, tentative 2/3 - '...' - nouvel essai dans 4s"), comme côté Windows
  (`Ecrire-Journal`) - avant, le réessai était silencieux : aucune trace dans l'appli qu'un
  accroc réseau avait eu lieu.
- L'annulation demandée par l'utilisateur est maintenant revérifiée pendant l'attente entre deux
  tentatives (toutes les ~200ms, comme la boucle `DoEvents` côté Windows) : annuler un lot
  n'attend plus bêtement les 4s d'un réessai en cours avant de s'arrêter.
- Vérifié par exécution JVM réelle : 9 nouvelles assertions (annulation avant/pendant l'attente,
  callback de log appelé avec les bons paramètres) - 22 assertions au total, toutes passent. App
  entière recompilée avec les stubs (0 erreur).

## v0.24 (build 24)

**Écart de fiabilité trouvé en comparant avec la version Windows** (pas demandé par Tomyn, trouvé
en continuant la comparaison systématique Windows/Android) : la version Windows protège quasiment
CHAQUE appel réseau (polling, envois, téléchargements - 20 points d'appel au total) avec un
mécanisme de réessai (`Invoquer-AvecReessaiReseau`, 3 tentatives, 4s d'intervalle) qui ne retente
QUE sur une vraie coupure réseau (timeout, connexion refusée/réinitialisée, DNS, erreur serveur
5xx) et jamais sur une vraie erreur API (mauvaise clé, requête invalide, etc.). La version Android
n'avait AUCUN réessai nulle part : le moindre accroc réseau (fréquent en mobile, contrairement à
un PC filaire) faisait échouer tout le traitement direct, sans seconde chance.

- Nouveau module `ReessaiReseau.kt` (pur Kotlin, sans dépendance Android) portant la même logique
  que côté Windows : 3 tentatives, 4s entre chaque, uniquement sur erreur transitoire (timeout,
  connexion coupée/refusée/réinitialisée, DNS, HTTP 5xx) - jamais sur du 4xx.
- Branché sur les 5 points d'appel réseau centraux d'Android (Meshy `requete()` + `telecharger()`,
  Tripo `requeteJson()` + `uploaderVersUrlPresignee()` + `telecharger()`) : couvre de fait TOUS les
  appels Meshy/Tripo (polling de tâche compris, qui repasse par ces mêmes fonctions), comme les 20
  points d'appel côté Windows.
- Vérifié par exécution JVM réelle (pas juste compilation) : 13 assertions sur la classification
  transitoire/réelle et le comportement de `executer()` (réussite directe, réessai puis succès,
  pas de réessai sur 4xx, épuisement des tentatives) - toutes passent. App entière recompilée avec
  les stubs (0 erreur).

## v0.23 (build 23)

**Encore un écart trouvé en comparant avec la version Windows** : l'historique PAR FICHIER
(`historique_fichiers.csv`, écrit depuis plusieurs versions déjà) était écrit mais jamais
consultable depuis l'appli - fallait aller l'ouvrir à la main avec un gestionnaire de fichiers.

- Nouveau bouton "Historique par fichier" dans la boîte "Historique des lots" (icône horloge en
  haut de l'écran) : liste cherchable par nom de fichier, plus récent en premier - même principe
  que la fenêtre dédiée côté Windows, en plus simple (pas de vrai ListView triable par colonne).

## v0.22 (build 22)

**4 fonctionnalités manquantes portées depuis la version Windows** (choisies par Tomyn parmi les
écarts restants identifiés par comparaison systématique) :

- **Vérification de mise à jour** (Paramètres) : compare la version installée à la dernière
  Release publiée sur GitHub, propose d'ouvrir la page si une plus récente existe. Adapté au
  modèle Android (compare aux Releases taguées, pas au dernier commit comme côté Windows - c'est
  le build.gradle d'une release qui compte, pas un commit jamais compilé en APK).
- **Prompts favoris** : nouvelle catégorie dynamique "Mes favoris" en tête du menu Catégorie,
  boutons "Sauver en favori" / "Supprimer ce favori" sous le champ de prompt. Persisté dans
  l'espace privé de l'app (prompts_favoris.json), même format que côté Windows.
- **Description MakerWorld** : chaque résultat colorisé génère maintenant un titre + texte prêts
  à coller dans le formulaire de dépôt MakerWorld, écrit en fichier texte à côté du résultat et
  copiable en un clic ("Copier description" sur la vignette).
- **Graphique des crédits consommés** (icône "Crédits" en haut de l'écran) : barres horizontales
  proportionnelles aux crédits de chaque lot, 40 derniers lots. Version simplifiée par rapport au
  vrai graphique vectoriel de Windows (Views standard plutôt qu'un dessin Canvas personnalisé,
  invérifiable visuellement sans appareil réel dans cet environnement).

Vérifié par compilation réelle (kotlinc + stubs, plusieurs trous de stub comblés au passage :
JSONObject.keys(), Intent(action, Uri), LinearLayout.LayoutParams à 3 arguments, ScrollView,
ClipData/ClipboardManager) : zéro erreur.

## v0.21 (build 21)

**Demande de Tomyn : les catégories/styles de prompt de la version Windows manquaient côté
Android, et impossible de lancer sans prompt.** Deux correctifs :

- **Catégories de prompt complétées** : 6 catégories manquaient (Animal de compagnie,
  Buste/statuette commémorative, Terrain/plateau de jeu, Véhicule, Food/nourriture factice,
  Bijou/vêtement fonctionnel) - seules Personnage/Décor/Personnage et décor/Pièce-Autre
  existaient. Les 10 catégories de la version Windows sont maintenant toutes présentes, avec
  leurs styles. (La catégorie dynamique "Mes favoris" de Windows, elle, n'est pas portée - plus
  gros morceau, à demander séparément si besoin.)
- **Lancement sans prompt** : possible maintenant, mais seulement si TOUS les fichiers du lot
  sont des images (un .stl/.obj n'a aucun style de "source" vers lequel se replier). Sans
  prompt, Meshy repart du style de la photo elle-même (`image_style_url` à la place de
  `text_style_prompt`) et Tripo texture directement pendant l'Image to 3D (pas d'étape Texture
  séparée). Même comportement et mêmes limites que la version Windows.

## v0.20 (build 20)

**Vrai bug trouvé en test sur téléphone (0.19)** : "Smart Topology" et la résolution 2k/4k
cochées en même temps donnaient encore HTTP 400, même après le correctif `ai_model` de la 0.19.
Cause confirmée sur la doc officielle Meshy : les deux réglages exigent chacun un `ai_model`
différent et incompatible (`meshy-t2.5` vs `meshy-7.1`) - ce n'est pas un oubli, c'est une
combinaison invalide côté API. Corrigé des deux côtés (Windows et Android) :
- L'interface empêche maintenant de cocher Smart Topology et une résolution 2k/4k en même temps
  (cocher Smart Topology repasse la résolution sur "Standard" et grise le menu).
- Par sécurité réseau, si jamais les deux arrivent quand même actives (anciens réglages
  enregistrés, par exemple), Smart Topology est prioritaire et la résolution est ignorée plutôt
  que d'envoyer une requête vouée à l'échec - avec un mot dans le journal pour que ce ne soit pas
  silencieux.

## v0.19 (build 19)

**Correctif réel trouvé en testant sur téléphone** : Meshy refusait `geometry_resolution`
("2k"/"4k") avec l'erreur HTTP 400 `geometry_resolution '4k' requires ai_model 'meshy-7.1'`.
L'hypothèse de départ (l'API mettrait `meshy-7.1` par défaut toute seule) était fausse - corrigé
en envoyant explicitement `ai_model` dans ce cas (sauf si Smart Topology est actif, qui fixe le
sien). Même correctif appliqué côté Windows.

**Portage complet des fonctions Meshy/Tripo avancées de la version Windows vers Android**
(vagues 1 à 6, précédemment étiquetées par erreur sous la version 0.17 sans changelog à jour) :

- Plafonds de taille réels (100 Mo Meshy, 150 Mo Tripo), balance détaillée des deux fournisseurs
- Smart Topology, `geometry_resolution`/`texture_resolution`, support des images côté Tripo
- Analyze/Repair Printability (Meshy) avec taille d'impression prévue
- Conversion locale `.3mf` → `.stl` (gère la Production Extension de Bambu Studio)
- Réglages avancés Meshy exposés dans l'interface (Smart Topology, résolutions, Printability)
- Remesh automatique (Meshy) et Retopology/decimate automatique (Tripo) pour les gros maillages
- Champ "Triangles visés" réglable (était fixé à 30000 partout)
- Corrige deux bugs trouvés en comparant les listes d'extensions avec la version Windows
  (`.webp` manquant, `.3mf` invisible dans le sélecteur de fichiers)

**À partir de cette version : chaque modification livrée fait monter le numéro de version et
déclenche la création d'une Release**, pour éviter qu'un fichier APK ancien et un fichier APK à
jour portent le même nom (c'est ce qui vient de se produire entre les releases 0.17 et 0.18 :
même nom de fichier `ColoriseurSTL-v0.17.apk` dans les deux, car le numéro de version n'avait pas
été remonté - piège corrigé ici).

## v0.17 (build 17)

**Portage de deux fonctions de la version Windows (ajoutées le 08/10/2026 côté bureau) :**

- **Historique par fichier** : à chaque colorisation réussie (Tripo, Meshy standard ou Meshy .obj),
  une ligne est ajoutée dans `historique_fichiers.csv` à la racine du dossier de sortie choisi
  (date, nom du fichier, fournisseur, crédits, chemin de sortie). Contrairement à la version
  Windows (où ce fichier est juste à côté du script et donc trivial à retrouver), sur Android le
  CSV est écrit via le dossier de sortie SAF choisi par Tomyn, pour qu'il reste accessible.
- **Assombrissement de la texture .obj** : nouveau champ (0 à 100 %), actif uniquement quand
  l'option "Meshy .obj expérimental" est cochée, pour compenser l'éclaircissement/assombrissement
  que Bambu Studio peut appliquer automatiquement selon le filament choisi (même logique que côté
  Windows : multiplication des canaux R/G/B par un facteur, alpha inchangé).
- Vérifié par compilation réelle (kotlinc + stubs Android, avec plusieurs trous de stub corrigés :
  `Intent.getDoubleExtra`/`putExtra(Double)`, `ContentResolver.openOutputStream(uri, mode)`,
  `Canvas.drawBitmap`, `Paint.colorFilter`, `ColorMatrix`/`ColorMatrixColorFilter`) : zéro erreur.
  **Pas encore testé sur le terrain** - à vérifier à l'installation, notamment que le CSV s'écrit
  bien dans le bon dossier et que le curseur d'assombrissement donne un résultat visuel cohérent.

## v0.16 (build 16)

**Corrige : les résultats colorisés disparaissaient en revenant dans l'appli après avoir ouvert un
visualiseur STL externe depuis la galerie** (remonté par Tomyn en testant la v0.15 en conditions
réelles). Cause : `EtatTraitement` (résultats, échecs, journal) ne vivait qu'en mémoire RAM dans un
objet singleton - suffisant pour survivre à une rotation d'écran, mais pas à un vrai kill de
processus par Android, qui peut arriver en mettant l'appli en arrière-plan pour ouvrir une appli
tierce (surtout avec plusieurs aperçus en mémoire). Au retour dans l'appli, le processus repart de
zéro et la galerie se retrouve vide - obligeant à relancer toute la colorisation (et donc à
reconsommer des crédits) juste pour revoir un résultat déjà obtenu.

- Chaque résultat et chaque échec est maintenant aussi écrit sur le disque (dans l'espace privé de
  l'appli, pas dans le cache qu'Android peut vider à tout moment) au fur et à mesure du lot, pas
  seulement une fois le lot terminé - un kill en plein milieu ne perd que ce qui n'était pas encore
  traité, jamais ce qui l'était déjà.
- Au lancement de l'appli, si l'état en mémoire est vide (signe d'un redémarrage de processus) et
  qu'un lot précédent a laissé une trace sur le disque, la galerie de résultats est reconstruite
  automatiquement à partir de cette trace - y compris les aperçus (réenregistrés en PNG).
- Un nouveau lot efface la trace du précédent, comme avant côté mémoire.
- Vérifié par compilation réelle (kotlinc + stubs Android, avec deux vrais trous de stub corrigés
  au passage : `Bitmap.compress`/`CompressFormat` et `BitmapFactory.decodeFile` manquaient) : zéro
  erreur. **Pas encore réinstallé/retesté sur le terrain** - priorité donnée à corriger vite ce bug
  précis plutôt qu'à attendre un nouveau cycle de test complet.

## v0.15 (build 15)

**Image -> STL -> colorisation (idée de Damdam2959, portée depuis la version Windows déjà confirmée
fonctionnelle en conditions réelles)** : le dossier source peut maintenant contenir des images
(`.jpg`, `.jpeg`, `.png`) mélangées avec des fichiers 3D, détectées automatiquement par leur
extension - rien d'obligatoire, aucune nouvelle case ni onglet.

- Pour un fichier 3D : rien ne change.
- Pour une image : l'appli lance d'abord "Image to 3D" chez Meshy (maillage seul, sans texture -
  la texture est refaite juste après par la colorisation habituelle avec le prompt choisi, pas
  celle générique que ferait Image to 3D elle-même), puis enchaîne directement sur le même
  pipeline de colorisation qu'un fichier 3D (même case ".obj expérimentale", même palette).
- **Coût** : +20 crédits environ par image (confirmé sur la doc tarifaire Meshy), en plus du coût
  de colorisation habituel - affiché séparément dans l'estimation.
- **Meshy uniquement pour le moment** - une image donnée à Tripo échoue avec un message clair.
- La vignette de la galerie de départ affiche directement l'image plutôt que de tenter (et
  échouer silencieusement) le rendu STL maison dessus.
- Vérifié par compilation réelle (kotlinc + stubs Android) : zéro erreur. Pas encore testé sur le
  terrain côté Android (déjà confirmé fonctionnel sur la version Windows le 08/10/2026).

## v0.14 (build 14)

**Portage des correctifs Windows du 07/10/2026** (export OBJ Tripo, option OBJ expérimentale pour
Meshy, vrais chiffres de crédits) :

- **Tripo sort désormais un `.obj` colorié par sommet (ZIP extrait) au lieu d'un `.3mf`.**
  `export_vertex_colors` n'est documenté par Tripo comme valide que pour les formats OBJ et
  GLTF - demandé avec 3MF comme avant, le paramètre était silencieusement ignoré, d'où des
  `.3mf` reçus avec une palette ajoutée mais jamais appliquée à la géométrie (aucune texture
  visible). Le résultat Tripo est maintenant un **sous-dossier** `<nom>_colorise/` (ou
  `<nom>_tripo_colorise/` en mode comparaison), extrait du ZIP renvoyé par l'API (maillage + `.mtl`
  + textures) via `ZipInputStream` et le `ContentResolver` (pas d'équivalent direct de
  `ZipFile.ExtractToDirectory` avec le Storage Access Framework).
- **Nouvelle case à cocher "Pour Meshy : exporter en .obj texturé plutôt qu'en .3mf"** : saute
  l'étape Multi-Color Print (facturée en plus) et récupère directement le `.obj` + `.mtl` + image
  de texture de l'étape Retexture, dans un sous-dossier dédié - même principe que Tripo. Disponible
  aussi bien en solo qu'en mode comparaison (seul Meshy est concerné ; Tripo n'a pas d'équivalent
  "avec/sans" à choisir). Reste décochée par défaut.
- **Estimation de coût revue avec les vrais chiffres observés par Damdam2959 le 07/10/2026** : Meshy
  ~20 crédits/figurine (Retexture 10 + Multi-Color Print 10, confirmés dans le tableau de bord -
  une première lecture avait suggéré 56, corrigée depuis), ~10 crédits avec l'option `.obj`
  (Multi-Color Print économisé), Tripo ~20 crédits/figurine (import 5 confirmé NON gratuit comme
  on le pensait + texturation 10 + conversion variable ~5). Le crédit d'import Tripo, auparavant
  ignoré dans le total réel du bilan, est maintenant bien compté.
- Vérifié par compilation réelle (kotlinc + stubs des API Android/AndroidX utilisées, extension du
  stub `DocumentFile` avec `createDirectory`/`findFile`) : zéro erreur. Pas encore testé en
  conditions réelles sur un appareil - priorité donnée à Windows pour la validation terrain avant
  ce portage, comme d'habitude.

## v0.13 (build 13)

**Mode comparaison Meshy + Tripo**, porté depuis la version Windows (même fonctionnalité,
adaptée à l'écran mobile) :

- Nouvelle case à cocher "Comparer Meshy et Tripo" (désactive le menu de choix du fournisseur
  quand elle est cochée) : lance les deux fournisseurs sur chaque fichier, l'un après l'autre,
  chacun avec son propre `try`/`catch` indépendant - l'échec de l'un n'empêche jamais de
  récupérer le résultat de l'autre.
- Fichiers de sortie suffixés `_meshy`/`_tripo` pour ne jamais s'écraser l'un l'autre, exactement
  comme sur Windows.
- Un fichier compte comme "réussi" dès qu'AU MOINS UN des deux fournisseurs aboutit ; seul un
  échec sur les deux fournisseurs compte comme un vrai échec.
- Contrairement à Windows (deux colonnes côte à côte), l'écran mobile est trop étroit pour une
  vraie mise en page à deux colonnes : chaque vignette de résultat porte à la place un petit
  badge coloré ("Meshy" en bleu, "Tripo" en orange) pour distinguer les deux à l'œil dans la même
  galerie.
- Bilan final (journal + notification) au format "Meshy X/N réussite(s), Tripo Y/N réussite(s)"
  en mode comparaison, au lieu du bilan simple habituel.
- Double le coût en crédits à chaque génération (les deux fournisseurs sont facturés) - reste
  décochée par défaut.
- Vérifié par compilation réelle (kotlinc + stubs des API Android/AndroidX utilisées) : zéro
  erreur. Pas encore testé en conditions réelles sur un appareil.

## v0.12 (build 12)

**Menu de prompts a deux niveaux**, pour remplacer la liste plate de 10 styles predefinis qui
melangeait des presets pensees pour un personnage avec d'autres pensees pour un decor :

- Nouveau menu "Categorie" (Personnage / Decor / Personnage et decor / Piece / Autre) qui filtre
  la liste proposee par le menu "Style voulu" en dessous - meme principe que la version Windows
  mise a jour en parallele.
- 10 prompts detailles par categorie (40 au total) + une entree "Autre" par categorie pour la
  saisie libre, chacune avec sa propre memoire du dernier texte tape (pour ne pas melanger le
  texte libre d'un personnage avec celui d'une piece mecanique d'une fois sur l'autre).
- L'appli se rouvre sur la derniere categorie utilisee.
- `PromptsPredefinis` restructure en catalogue par categorie (`categories`, `libellesPour`,
  `textePour`) au lieu d'une simple liste a plat - meme nom de fichier, structure interne
  changee.

## v0.11 (build 11)

**Tripo confirmé fonctionnel de bout en bout pour la première fois**, côté Windows, après une
longue série de corrections - tous les correctifs portés ici à l'identique :

- Ajout de l'étape d'import manquante (`import_model`), obligatoire avant la texturation pour
  un fichier uploadé - confirmée par la doc officielle et par l'historique du tableau de bord
  Tripo (chaque texturation en échec était précédée d'un import en succès jamais réutilisé).
- Corrigé le nom du champ pour la texturation : `original_model_task_id`, pas `input` comme
  envoyé jusqu'ici - `input` était silencieusement ignoré par l'API, qui tournait alors sans
  jamais avoir de vraie référence de modèle. C'était la vraie cause des échecs systématiques
  ("Internal processing error") observés sur tous les tests précédents, même sur un simple cube.
- Corrigé l'extraction de l'URL du résultat final : `output.model_url`, pas `output.model`.
- Les crédits réellement consommés sont maintenant extraits et comptabilisés (au lieu de
  toujours afficher 0 pour les fichiers traités via Tripo).

## v0.10 (build 10)

- Corrigé un manque réel dans le manifest : la permission `ACCESS_NETWORK_STATE` n'était pas
  déclarée alors que la fonction "Wi-Fi uniquement" (v0.6) en a besoin - pouvait provoquer un
  plantage immédiat au clic sur "Lancer" si ce réglage était actif, sans message d'erreur.
  Fonction rendue défensive en plus (ne peut plus planter l'appli pour ce simple contrôle de
  confort, quoi qu'il arrive).
- Signalé en conditions réelles : l'appli plantait dès le clic sur "Lancer", avec Meshy comme
  avec Tripo - cause probable identifiée et corrigée, mais pas encore reconfirmée en conditions
  réelles après ce correctif précis.

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
