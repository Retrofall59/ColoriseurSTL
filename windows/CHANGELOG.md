# Changelog (version Windows PowerShell)

Historique de développement au fil des sessions (notes datées, dans l'ordre chronologique).
Voir [README.md](README.md) pour l'état actuel de cette version.

---

**Fix : la galerie de fichiers se retrouvait coupée en bas de fenêtre (14/10/2026, signalé par
Tomyn, capture à l'appui).** Les 4 en-têtes de section ajoutés dans la passe précédente ont fait
grossir la zone de configuration du haut d'environ 150-190px, sans plus de place en dessous pour
la galerie - toujours accessible en défilant (la galerie était déjà prévue pour ça), mais moins
visible d'un coup d'œil qu'avant. Espacement sous chaque bandeau réduit (34 → 28px) et police/
décalage du titre légèrement resserrés : quelques dizaines de pixels récupérés, correctif modeste
mais sûr plutôt qu'une refonte plus large de la mise en page (option évoquée mais pas retenue pour
l'instant).

**Refonte visuelle, 1re passe : hiérarchie en sections (13/10/2026, Tomyn).** L'écran de
configuration était un long mur de champs à plat, sans aucune hiérarchie visuelle. Quatre
en-têtes de section ajoutés (bande accent violette + titre en majuscules) : **Connexion aux
fournisseurs**, **Source**, **Style et couleurs**, **Lancement**. Volontairement limité à ça pour
cette passe : aucun contrôle existant n'a été déplacé ni retouché dans sa logique, seuls les
en-têtes sont insérés entre eux - choix fait pour ne pas risquer de casser un alignement ou un
évènement sur une appli dont dépend le collègue dessinateur de Tomyn, sans pouvoir
visuellement vérifier le rendu avant livraison (pas de Windows sous la main ici). Une refonte
plus poussée (vrais panneaux groupés, réorganisation de la mise en page) reste possible dans une
passe ultérieure si celle-ci convient.

**Titre + description prêts à coller pour un dépôt MakerWorld (13/10/2026, Tomyn).** Demande
initiale : import/export automatisé avec MakerWorld (Bambu Lab). Vérifié avant de coder :
MakerWorld n'a **pas d'API publique** (confirmé sur leur propre forum - accès réservé aux
entreprises sur demande, de plus en plus fermé avec le temps), et Tomyn avait déjà tenté un
contournement par scraping, bloqué par Cloudflare. Ni l'import ni le dépôt ne sont donc
automatisables proprement (pas d'API) ou de façon fiable (scraping bloqué). Seule la partie
rédaction l'est : à chaque fichier colorisé avec succès, un titre (dérivé du nom de fichier) et
une description (basée sur le style/prompt choisi) sont désormais générés automatiquement -
déposés dans un fichier `..._description_makerworld.txt` à côté du résultat, ET accessibles
d'un clic via un nouveau bouton "Copier description" sur la vignette correspondante (presse-
papier), à coller à la main dans le formulaire de dépôt MakerWorld (nom, catégorie, licence,
visibilité, description - champs confirmés dans leur doc officielle).

**Reprise automatique d'un lot interrompu (13/10/2026, Tomyn).** Sur un gros dossier (~250
fichiers d'images du collègue dessinateur), si l'appli plante ou est fermée à mi-lot, relancer
sur le même dossier de sortie repartait de zéro et redépensait des crédits sur des fichiers déjà
colorisés avec succès. Quand des fichiers de sortie existent déjà dans le dossier choisi (et que
"Garder un historique des essais" n'est pas coché), une nouvelle boîte à 3 choix s'affiche :
**Reprendre le lot** (ignore les fichiers déjà traités, ne retraite que les nouveaux/manquants,
0 crédit dépensé dessus), **Tout refaire** (comportement d'avant : écrase tout) ou **Annuler**.
Un fichier n'est considéré "déjà traité" que si TOUTES ses sorties attendues existent déjà (les
deux, en mode comparaison Meshy+Tripo) - sinon il repasse normalement, pour ne jamais sauter un
fichier resté à moitié fait. Le bilan final précise combien de fichiers ont été repris sans
redépense.

**5 nouvelles catégories de prompts (13/10/2026, Tomyn : "ça peut toujours servir à un moment").**
En plus d'"Animal de compagnie" ajoutée juste avant, 5 autres catégories pas encore couvertes par
les menus existants, toutes avec 10 styles + "Autre" comme les autres :
- **Buste / statuette commémorative** (portrait humain) — rendu sobre et fidèle, bronze/marbre,
  médaille, trophée, souvenir de cérémonie.
- **Terrain / plateau de jeu** — hexagones/cases lisibles, carte fantasy, wargame, désert,
  hivernal, île, etc. (différent du "Socle de jeu" déjà présent dans Décor, pensé pour un plateau
  entier plutôt qu'un socle de figurine).
- **Véhicule** — voiture, livrée de course, militaire, avion, vaisseau sci-fi, moto, train,
  bateau.
- **Food / nourriture factice** — gâteau, plat, fruits/légumes, glace, fast-food, confiserie,
  plateau de fromages.
- **Bijou / vêtement fonctionnel** — différent du "Bijou / objet précieux" de Pièce/Autre (pensé
  pour une pièce décorative statique) : ici visé pour un objet réellement porté, couleurs
  pensées pour tenir sur une surface qui plie ou bouge.

**Nouvelle catégorie de prompts : "Animal de compagnie" (13/10/2026, demande de Tomyn).** Entre
"Personnage" et "Décor" dans le menu déroulant, 10 styles dédiés aux figurines d'animaux (pelage
réaliste, portrait souvenir fidèle, stylisé mignon/chibi, figurine peinte à la main, chat, chien,
oiseau, animal de ferme/exotique, race à poil long, mémorial/hommage), plus "Autre" comme les
autres catégories.

**Fix : le champ "Triangles visés" chevauchait le bouton "Lancer la colorisation" (13/10/2026,
signalé par Tomyn).** Le nouveau champ ajouté juste en dessous avait bien sa propre ligne, mais
le bouton "Lancer" calculait encore sa position par rapport à la même variable de ligne,
decalée entre-temps - il retombait exactement sur la ligne des triangles au lieu de rester sur
celle de "Nombre de couleurs". Le bouton garde maintenant sa position d'origine (même ligne que
le nombre de couleurs), mémorisée avant que la ligne des triangles ne la fasse avancer. Correctif
purement visuel, sans impact sur le comportement.

**Maillage "Image to 3D" trop peu dense (13/10/2026, Tomyn : "je lui donne une photo et il me
sort un truc très low poly, sur le site Meshy tu peux lui dire combien de triangles tu veux à
l'arrivée")** : confirmé en relisant la doc de l'API Meshy — le paramètre `target_polycount`
(100 à 300 000 triangles) existe bien, mais il est ignoré tant que `should_remesh` n'est pas mis
explicitement à `true` (`false` par défaut pour Meshy 6/7 — donc aucun remaillage ne se
produisait jusqu'ici, et le maillage généré restait tel quel, parfois clairsemé). Un nouveau
champ **"Triangles visés (image uniquement, 100-300000)"** apparaît dans l'appli à côté du
nombre de couleurs, envoyé avec `should_remesh: true` à chaque appel "Image to 3D" — valeur par
défaut 30 000, identique à celle documentée par Meshy pour un remaillage activé. Sans effet sur
un fichier 3D (STL/OBJ/etc.) déjà fourni en entrée, seulement sur une image. **Non testé en
conditions réelles.**

Colorise automatiquement un dossier entier de fichiers 3D non colorisés (`.stl`, `.obj`, `.fbx`,
`.glb`, `.gltf`). **Deux fournisseurs possibles, au choix** : Meshy (palette fixe à N couleurs,
sort un `.3mf` prêt à trancher) ou Tripo (couleur par sommet, dégradé continu, sort un `.obj`
coloré) — utile pour basculer sur l'un si l'autre est à court de crédits. Renseigne la clé d'au
moins l'un des deux dans l'appli ; un menu déroulant permet de choisir lequel utiliser pour
chaque lot.

**Compteurs numériques : saisie directe au clavier (10/10/2026, signalé par Tomyn : devoir cliquer
sur les petites flèches pour atteindre un grand nombre, c'est pénible)** : le compteur maison
(nombre de couleurs, % d'assombrissement — voir "Relookage niveau 1" plus bas) ne permettait que de
cliquer sur + ou -, champ en lecture seule. Il est maintenant modifiable directement au clavier :
clic dedans (le contenu se sélectionne tout seul, prêt à être retapé), saisie filtrée au fur et à
mesure (chiffres, un seul séparateur décimal si le compteur en accepte, signe moins seulement si le
compteur accepte les négatifs), validée en appuyant sur Entrée ou en cliquant ailleurs — avec retour
automatique à la dernière valeur valide si jamais un texte invalide est collé dedans plutôt que
tapé. Les boutons +/- restent là pour les petits ajustements. **Non testé.**

**Deuxième bug trouvé sur le même sujet : le journal se coupait pour de vrai, pas juste à l'écran
(10/10/2026, Tomyn a confirmé/insisté après mon explication "c'est juste qu'il faut scroller" —
il avait raison, c'était un vrai bug)** : le `TextBox` Windows a, par défaut, une limite cachée de
32 767 caractères (`MaxLength`), même en mode multiligne. Une fois cette limite atteinte,
`AppendText()` n'ajoute plus rien du tout, silencieusement, sans la moindre erreur — donc rien à
voir avec le défilement (qui marchait bien), le texte au-delà n'était juste jamais écrit dans le
journal. Avec une ligne ajoutée à chaque poll de progression ("Retexture : IN_PROGRESS (..)...") et
deux fois plus de lignes en mode "Comparer Meshy et Tripo", cette limite est facile à atteindre sur
un lot qui tourne un moment. Corrigé en levant cette limite (`MaxLength = 0`, illimité en
pratique pour un TextBox multiligne). **Non testé**, comme le reste : impossible de vérifier ici le
nombre de caractères exact qui faisait planter l'ajout chez Tomyn.

**Bug important corrigé : la boîte de dialogue de fin plantait à chaque fois (10/10/2026, trouvé
en creusant le "texte coupé en bas" signalé par Tomyn, capture à l'appui)** : ce que Tomyn prenait
pour un souci d'affichage du journal cachait en fait une vraie erreur PowerShell. Depuis le
remplacement des `MessageBox` Windows par la boîte maison `Afficher-Boite` (passe de polissage
graphique précédente), **chaque appel** à cette fonction plantait silencieusement avec l'erreur `Le
terme 'if' n'est pas reconnu comme nom d'applet de commande...`, visible dans le journal juste
après le bilan d'un lot au lieu du petit message "Colorisation terminée" attendu. Cause : le code
calculait la couleur du bouton avec `Rendre-BoutonPlat $bouton (if ($icone -eq "Error") {...} else
{...})` — un `if/else` glissé directement entre parenthèses simples comme argument de fonction.
Ça ressemble à du PowerShell valide (et ça se lit bien), mais PowerShell n'accepte un `if/else`
comme valeur que via `$(...)` (sous-expression), pas via `(...)` simple en position d'argument ;
utilisé ainsi, il essaie d'exécuter "if" comme une commande externe, qui n'existe pas. Ni moi ni
Tomyn n'avions de Windows sous la main pour le repérer avant qu'il ne tombe dessus en conditions
réelles. Corrigé en calculant la couleur du bouton dans une variable à part avant d'appeler
`Rendre-BoutonPlat`, comme c'était déjà fait correctement partout ailleurs dans le script (toutes
les autres utilisations d'un `if` en valeur passent déjà par `$(...)`, seule `Afficher-Boite` avait
ce bug). Concrètement, ça veut dire que **toutes** les boîtes de dialogue de l'appli (confirmations,
avertissements, erreurs, pas seulement le message de fin) plantaient de la même façon depuis cette
passe — ce correctif les répare toutes d'un coup. Pour le texte du journal en lui-même : rien
d'anormal à ce qu'il ne montre que les dernières lignes à l'écran (il défile tout seul vers le bas
au fur et à mesure, comme prévu) — c'est juste qu'avec deux fournisseurs comparés en parallèle, il
y a deux fois plus de lignes à produire, donc deux fois plus à faire défiler. **Non testé** comme
toujours : à confirmer que la boîte "Colorisation terminée" s'affiche bien maintenant au lieu de
l'erreur, sur un vrai lot.

**Correctif : fenêtre trop haute pour l'écran (10/10/2026, signalé par Tomyn — captures d'écran à
l'appui, "on voit pas tout" et pendant la colorisation "on voit les premières lignes d'avancement
mais pas la suite")** : la fenêtre s'ouvrait toujours à ~1136 px de haut, quel que soit l'écran —
plus que la zone utile de pas mal d'écrans une fois la barre des tâches déduite (ex : ~1040 px
utiles sur un écran 1920×1080). Résultat : le bas de la fenêtre, dont une bonne partie de l'onglet
"Avancement", sortait de l'écran, sans bordure de fenêtre visible en bas pour pouvoir la déplacer
ou la redimensionner proprement à la souris.
- *Premier essai (raté, signalé "toujours pareil" par Tomyn avec une nouvelle capture)* : réduire
  la taille de la fenêtre tout en haut du script, avant la création des onglets. Ça ne marchait pas
  : l'ancrage de l'onglet (`$onglets.Anchor`, qui le fait suivre le redimensionnement de la
  fenêtre) calcule sa marge par rapport au bord bas de la fenêtre au moment où on le lui donne — si
  la fenêtre est déjà rétrécie à ce moment-là, cette marge part en négatif et l'onglet (640 px de
  haut, fixe) déborde quand même hors écran au lieu de rétrécir avec elle.
- *Deuxième essai (raté aussi, "toujours pareil" d'après Tomyn avec une nouvelle capture)* :
  construire la fenêtre à sa taille complète (pour que l'ancrage se calcule sur la bonne base),
  puis la rétrécir tout à la fin pour tenir dans la zone utile de l'écran détecté
  (`Screen.WorkingArea`). Logiquement ça aurait dû marcher (l'ancrage était bien en place avant le
  rétrécissement) — mais le résultat sur l'écran de Tomyn était identique. Cause la plus probable,
  non confirmable sans Windows sous la main : la mise à l'échelle DPI de Windows (un écran réglé à
  125 %/150 %, très courant), qui peut réagrandir une taille fixée à la main après coup, ou fausser
  le calcul de la zone utile réelle pour une appli qui ne déclare pas son support DPI — terrain
  casse-tête classique en WinForms.
- *Troisième essai, approche différente* : plutôt que de continuer à deviner une taille "à la
  main", la fenêtre démarre maintenant carrément **maximisée**. C'est Windows lui-même qui calcule
  alors la bonne taille/position (barre des tâches, mise à l'échelle DPI, tout est déjà géré
  nativement par l'OS pour une maximisation, contrairement à un calcul fait depuis le script) — la
  même mécanique fiable que n'importe quelle appli qui s'ouvre en plein écran. Beaucoup plus
  simple, et ça contourne le problème au lieu d'essayer de le calculer. La fenêtre reste
  redimensionnable ensuite (bouton "Restaurer" dans la barre de titre, ou double-clic dessus) si
  une fenêtre plus petite est préférée.
**Non testé** : pas de Windows ici pour vérifier sur un vrai écran. Si le souci persiste encore
après cette version, c'est que la fenêtre a un autre problème que sa seule hauteur de départ (peut-
être carrément lié au DPI/à l'échelle d'affichage) — dans ce cas, le plus utile serait de savoir :
l'échelle d'affichage utilisée (Paramètres Windows > Affichage > "Mise à l'échelle", souvent 100,
125 ou 150 %) et si "Restaurer" (double-clic sur la barre de titre) après l'ouverture en plein
écran redonne une fenêtre de taille raisonnable ou pas.

**Import direct depuis Thingiverse : tenté puis abandonné (10/10/2026)** : idée de Tomyn — coller
le lien d'un "thing" Thingiverse, récupérer la liste de ses fichiers via l'API officielle, en
choisir, les télécharger et rejoindre le pipeline normal. Codé, puis testé en réel par Tomyn : l'API
Thingiverse est derrière un vrai défi JavaScript Cloudflare ("Just a moment..."), qu'aucune requête
HTTP simple (PowerShell ou autre) ne peut passer — ni un User-Agent de navigateur, ni rien côté
script. La seule vraie solution serait d'embarquer un moteur de navigateur complet (WebView2) dans
l'appli, jugé trop lourd/fragile pour ce que ça apporte. Tomyn a préféré qu'on retire complètement
cette fonctionnalité plutôt que de s'engager dans ce chantier — retour au dépôt manuel de fichiers,
qui marche très bien. Gardé en note ici au cas où Cloudflare changerait un jour sa politique sur cet
endpoint, ou si l'idée revient avec une approche différente.

Autre point non vérifié : le nom exact des champs dans la réponse JSON de l'API (notamment celui
qui donne le lien de téléchargement direct d'un fichier) n'a pas pu être confirmé contre une vraie
réponse tant que le blocage Cloudflare n'est pas passé. Autre limite connue : certains fichiers
rendus "réservés" par leur auteur sur Thingiverse nécessitent d'être connecté pour être
téléchargés — ceux-là ne passeront pas avec un simple jeton d'app.

**Boîtes de dialogue maison, dernière trace Windows native éliminée (10/10/2026, suite — Tomyn :
"je suis sûr que tu peux encore faire mieux au niveau graphique")** : toutes les fenêtres d'alerte
(erreurs, confirmations, avertissements — une vingtaine dans l'appli) utilisaient encore la boîte
de dialogue système `MessageBox` (fond gris, icône Windows, bouton bleu natif) — c'était la
dernière brique 100% Windows qui restait. Remplacées par une boîte maison (`Afficher-Boite`) dans
le même style que le reste de l'appli : bandeau de couleur selon le type (violet = info, orange =
avertissement, rouge = erreur), boutons plats du thème. Pour les boîtes Oui/Non à risque
(confirmer malgré un solde potentiellement insuffisant, écraser des résultats existants, etc.),
la touche Entrée valide par défaut le bouton "Annuler" plutôt que "Continuer quand même", pour
éviter une validation accidentelle sur une action qui coûte des crédits ou écrase des fichiers.
**Non testé** : l'affichage (bandeau, texte qui s'ajuste à la longueur du message, alignement des
boutons) n'a pas pu être vérifié visuellement, ni le comportement des touches Entrée/Échap — à
surveiller en particulier sur les messages les plus longs (vérification de solde, erreurs d'API).

**Relookage niveau 2 (10/10/2026, suite) : ComboBox, onglets et compteurs ne faisaient plus
Windows** : les listes déroulantes (fournisseur, catégorie, style) et les onglets (Fichiers 3D /
Résultats / Avancement) étaient les derniers widgets 100% natifs — liste grise, surbrillance bleu
système, onglets à relief Windows. Ils sont maintenant repeints dans la palette violette (onglet
actif en plein violet, liste déroulante avec surbrillance violette au lieu du bleu système). Les
compteurs numériques (nombre de couleurs, % d'assombrissement) sont recolorés aussi, mais les
petites flèches haut/bas restent grises — .NET ne permet pas de les repeindre sans remplacer tout
le contrôle, jugé hors scope pour cette passe.
**Glisser-déposer la clé API directement dans son champ, maintenant possible** : auparavant,
déposer un texte sélectionné (la clé copiée depuis le site de Meshy/Tripo) sur le champ de clé ne
faisait rien — Windows désactive le glisser-déposer natif sur un champ en mode mot de passe, par
sécurité, même si on force l'option correspondante. Contourné en récupérant le dépôt au niveau de
la fenêtre entière plutôt que du champ lui-même. Le copier-coller clavier/clic droit (Ctrl+V)
fonctionnait déjà normalement, y compris sur un champ masqué — seule la **copie depuis le champ**
reste bloquée par Windows tant qu'il est masqué (sécurité du mode mot de passe) : clique sur
"Afficher" d'abord si tu veux recopier une clé déjà saisie.
**Relookage niveau 1, poussé à fond (10/10/2026, Tomyn a demandé d'aller encore plus loin)** :
- Les compteurs numériques (nombre de couleurs, % d'assombrissement) n'utilisent plus le
  `NumericUpDown` natif de Windows (ses flèches grises étaient la dernière vraie limite du niveau
  1) : remplacé par un petit composant maison (zone de texte + deux boutons +/- plats), dans les
  couleurs du thème, sans aucune trace de widget système.
- Les vignettes de la galerie (fichiers 3D et résultats colorisés) ont maintenant des coins
  arrondis au lieu du rectangle net d'origine.

**Écran de lancement (10/10/2026, demande de Tomyn)** : au démarrage, une fenêtre sans bordure
violette (même couleur que la bannière) s'affiche brièvement avec le logo "bobine", le nom de
l'appli et une fine barre orange qui se remplit, avant de laisser place au formulaire principal —
une vraie entrée dans l'appli plutôt qu'une ouverture directe sur le formulaire.

**Non testé, comme le reste de cette page** : aucun Windows/PowerShell disponible ici pour
vérifier le rendu réel. À surveiller en particulier : le composant +/- maison (clic sur les
boutons, affichage de la valeur, activation/désactivation avec la case "Meshy .obj expérimental"),
et l'écran de lancement (positionnement centré, transition propre vers le formulaire principal,
sans fenêtre fantôme qui resterait affichée).

**Nouvelle interface graphique (10/10/2026, demande de Tomyn : l'appli faisait "trop fenêtre
Windows")** : bannière violette avec logo, boutons plats colorés par rôle (violet pour l'action
principale, orange pour relancer les échecs, rouge discret pour annuler), cartes blanches à bande
colorée pour les vignettes au lieu du cadre gris, en-têtes de colonnes Meshy/Tripo en violet,
barre de progression recolorée. Même palette violette que l'appli Android ColoriserSTL, pour une
identité visuelle commune aux deux versions. **Non testé** : aucun Windows/PowerShell disponible
pour vérifier le rendu réel (voir l'avertissement en tête du script) — les deux points les plus à
risque sont le petit logo "bobine" généré à la volée et la recoloration de la barre de progression
(passe par un appel Windows bas niveau, SendMessage, plus fragile que le reste).

**Partir d'une image plutôt que d'un modèle 3D (ajouté le 2026-10-08, idée de Tomyn)** : le dossier
ou la sélection de fichiers peut aussi contenir des images (`.jpg`, `.jpeg`, `.png`), mélangées
avec des fichiers 3D — détectées automatiquement par leur extension, sans case ni onglet séparé.
Pour un fichier 3D, rien ne change. Pour une image, l'appli lance d'abord "Image to 3D" chez Meshy
(maillage seul, sans texture — la texture est refaite juste après par l'étape de colorisation
habituelle avec ton prompt, pas celle générique que ferait Image to 3D toute seule), puis enchaîne
directement sur la colorisation choisie (3MF ou .obj, selon les mêmes réglages qu'un fichier 3D).
**Coût** : +20 crédits environ par image, en plus du coût de colorisation habituel (donc ~40
crédits au total pour une image, contre ~20 pour un modèle 3D déjà prêt). **Meshy uniquement pour
le moment** — une image donnée à Tripo (en mode comparaison ou directement) échoue avec un message
clair plutôt que d'être envoyée telle quelle.

**Historique par fichier (ajouté le 2026-10-08)** : en plus de l'historique par lot existant
(`historique_lots.csv`, un total par lancement), un nouveau `historique_fichiers.csv` garde une
ligne par fichier réussi — nom, fournisseur, crédits consommés, chemin de sortie. Les résultats
Meshy/Tripo ne sont récupérables depuis leur API que 3 jours après génération (politique officielle
confirmée), donc ceci ne remplace pas une sauvegarde du dossier de sortie lui-même, mais garde une
trace locale permanente de ce qui a été généré et ce que ça a coûté, même si un fichier précis
disparaît un jour.

**Constaté par Tomyn (2026-10-08) : partir d'une image donne un résultat nettement plus fidèle**
qu'un STL fourni directement. Deux raisons probables, qui se recoupent :
- Le maillage généré par Image to 3D a un UV/dépliage pensé dès le départ pour recevoir une
  texture automatique, donc la Retexture qui suit projette plus proprement (moins de distorsion,
  moins de coutures visibles).
- Un STL fourni directement n'a souvent jamais été conçu pour ça — pensé pour une impression
  mono-couleur ou pour être repeint à la main, pas pour une texture automatique multi-couleur.

**⚠️ Tripo sort un `.obj`, pas un `.3mf`.** Confirmé le 2026-10-07 : le paramètre
`export_vertex_colors` de l'API Tripo n'est documenté comme valide que pour les formats `OBJ` et
`GLTF` — demandé avec `3MF` comme avant, il était silencieusement ignoré, et le `.3mf` obtenu
avait bien 4 couleurs ajoutées à sa palette mais jamais appliquées à la géométrie (aucune texture
visible, même dans un lecteur `.3mf`). Bambu Studio sachant lire un `.obj` coloré par sommet et
proposer ses couleurs dans l'AMS, le script demande maintenant ce format-là pour Tripo. Comme
l'export OBJ de Tripo est livré en ZIP (maillage + `.mtl` + textures, pas un fichier unique),
chaque résultat Tripo est un **sous-dossier** `<nom>_colorise/` (ou `<nom>_tripo_colorise/` en
mode comparaison) contenant ces fichiers — ouvre le `.obj` à l'intérieur dans Bambu Studio.

**Option .obj pour Meshy aussi, confirmée fonctionnelle le 2026-10-07** : une case à cocher
("Pour Meshy : exporter en .obj texturé plutôt qu'en .3mf") permet de sauter l'étape "Multi-Color
Print" (celle qui crée la palette à N couleurs, facturée en plus) et de récupérer directement le
`.obj` + `.mtl` + image de texture de l'étape Retexture — même sous-dossier dédié que pour Tripo.
Avantages confirmés à l'usage par Tomyn : une seule étape facturée (moins cher), Bambu Studio
propose bien sa boîte de dialogue de correspondance automatique des couleurs avec ce `.obj`-là
aussi (pratique quand les filaments exacts choisis par Meshy ne sont pas disponibles), et les
couleurs rendues sont même plus fidèles au modèle que l'équivalent Tripo (moins délavées/pastel).
Bambu Studio peut proposer de "réparer" le maillage à l'ouverture : normal pour un import OBJ,
pas un signe de problème. Reste décochée par défaut, et ignorée en mode comparaison (Meshy y
reste sur son Multi-Color Print habituel, pour ne pas ajouter une troisième variante au bilan).

**Ni le `.obj` ni le `.3mf` ne sont "zéro manip" dans Bambu Studio — précisé par Tomyn le
2026-10-08, pour choisir en connaissance de cause :**
- `.obj` (Meshy ou Tripo) : Bambu Studio propose un bouton qui fait la correspondance de couleurs
  tout seul à partir de la texture — pratique, mais le résultat n'est pas toujours fidèle.
- `.3mf` (Meshy, Multi-Color Print) : le multi-couleur est déjà garanti par Meshy (pas de souci de
  nombre de couleurs ni de fidélité), mais Bambu Studio ne fait rien d'automatique à l'ouverture —
  c'est à toi d'assigner les couleurs/slots AMS pour chaque partie.

Bref, c'est le même travail de toute façon (choisir quels filaments correspondent à quelles
couleurs), juste fait à des moments différents : par Meshy à l'avance (`.3mf`, fidèle mais manuel
ensuite dans l'AMS) ou par Bambu Studio après coup (`.obj`, automatique mais parfois approximatif).

**Astuce découverte par Tomyn (2026-10-08)** pour améliorer la fidélité du bouton auto de Bambu
Studio sur un `.obj` : dans sa boîte de dialogue de correspondance des couleurs, mets le nombre de
teintes nettement plus haut que ton nombre réel de filaments (ex. 18-19) avant de lancer le mélange
automatique avec tes filaments choisis (RYBW ou CMYW, par exemple). **Ce nombre ne correspond pas
à des filaments en plus** — tu gardes bien les mêmes 4 filaments physiques dans ton AMS. Il indique
à Bambu Studio sur combien de paliers de transition répartir le dégradé entre ces 4 filaments :
plus il y en a, plus fin est le mélange calculé, d'où un rendu nettement plus fidèle au modèle
qu'un simple plaquage de 4 couleurs plates.

**Revers de la médaille** (noté par Tomyn le 2026-10-08) : le filament inclus dans le mélange tire
le rendu dans un sens ou dans l'autre, logique comme en peinture — avoir du **blanc** dans la liste
pastellise (éclaircit toutes les teintes), avoir du **bleu** assombrit (fonce le mélange). À garder
en tête en choisissant les filaments pour le dégradé, pas juste le nombre de teintes demandé.

**Ne pas dépasser 18-19 teintes** (constaté par Tomyn le 2026-10-08) : au-delà, certains filaments
ne sont plus mélangés du tout par Bambu Studio, ce qui annule le bénéfice de l'astuce plutôt que
l'améliorer. 18-19 semble être le maximum utile constaté dans la pratique, pas juste un exemple.

**Nouveau réglage "Assombrir la texture .obj" (ajouté le 2026-10-08)** : un curseur réglable au
dixième de % près (0,0 à 100,0) apparaît sous la case ".obj Meshy", actif uniquement quand cette
case est cochée. Il assombrit l'image de texture reçue de Meshy *avant* qu'elle parte dans le
sous-dossier `.obj` — pour précompenser l'éclaircissement du mélange automatique Bambu Studio
quand le jeu de filaments choisi comprend du blanc (voir plus haut). 0% = texture inchangée. Pas de
valeur universelle : dépend des filaments utilisés ensuite dans Bambu, à régler une fois pour son
jeu de filaments habituel. Ne concerne que l'option `.obj` de Meshy (pas Tripo, pas le `.3mf`).

**⚠️ L'intégration Tripo est nettement moins certaine que Meshy.** Les endpoints et
l'authentification viennent du SDK officiel Tripo (bon niveau de confiance), mais les noms exacts
de certains champs de requête sont des déductions par recoupement de sources tierces, pas une
doc officielle citée mot pour mot comme pour Meshy. Attends-toi à devoir corriger des détails au
premier vrai test avec une clé Tripo - plus proche de nos débuts sur les lecteurs RFID que du
niveau de certitude habituel sur Meshy.

Galerie de vraies vignettes intégrée à la fenêtre, pour les fichiers de départ comme
pour les résultats colorisés.

**Statut** — confirmé fonctionnel en conditions réelles (interface graphique, appels API,
rendu des vignettes) sur plusieurs sessions de test. Le moteur de rendu lui-même (projection,
ombrage, et maintenant le lecteur OBJ) a pu être compilé et **réellement exécuté** (pas juste
relu) grâce à un compilateur C# installé en cours de route - vérifié visuellement sur un cube de
test, STL et OBJ, résultat identique comme attendu. Reste un vrai test avant de lancer un gros
lot si tu changes quelque chose de significatif.

**Un point à connaître sur les nouveaux formats** : Meshy accepte `.stl`, `.obj`, `.fbx`, `.glb`,
`.gltf` en entrée (confirmé dans leur doc officielle) — **mais pas le `.3mf`**, qui n'existe que
comme format de *sortie* chez eux. Impossible donc de repartir d'un `.3mf` pour le coloriser.
Côté vignettes d'aperçu local : seuls `.stl` et `.obj` ont un vrai rendu ; `.fbx`/`.glb`/`.gltf`
affichent le placeholder "pas d'aperçu" (formats trop complexes pour un parseur maison fiable),
mais se colorisent normalement par ailleurs.

**Note technique** : les vignettes des STL de départ sont rendues directement par le script
(lecture du fichier, projection isométrique, ombrage simple) — ça ne dépend d'aucune
application externe. Une première version s'appuyait sur la Visionneuse 3D de Windows, mais
Microsoft a retiré cette appli du Store en 2026 et elle n'était de toute façon pas préinstallée
sur Windows 11. Les vignettes des résultats, elles, viennent directement de l'image d'aperçu
que Meshy fournit avec son résultat.

## Utilisation (recommandée) — double-clic, aucune configuration

1. Garde ces fichiers **dans le même dossier** :
   - `Lancer-Coloriser-STL.vbs` ← celui sur lequel tu double-cliques
   - `Coloriser-STL-GUI.ps1`
   - `Lancer-Coloriser-STL.bat` (dépannage uniquement, voir plus bas)
   - (et `cle_api.enc` apparaîtra ici après le premier lancement — voir plus bas)

2. **Double-clique sur `Lancer-Coloriser-STL.vbs`**. Une vraie fenêtre s'ouvre, sans aucune
   console derrière, pas de politique d'exécution à configurer, pas de fichier à débloquer — le
   lanceur gère tout ça tout seul à chaque fois, sans rien modifier de permanent sur ta machine.

   **Si jamais rien ne s'ouvre et que tu ne sais pas pourquoi** : lance plutôt
   `Lancer-Coloriser-STL.bat` à la place une fois, pour voir le message d'erreur dans la
   console (le `.vbs` étant invisible, il ne montre aucune erreur si quelque chose empêche
   même l'interface de démarrer).

3. Dans la fenêtre :
   - Colle ta clé API (meshy.ai/settings/api) — bouton "Afficher" pour vérifier ce que t'as collé
   - "Parcourir..." pour choisir le dossier contenant tes fichiers 3D
   - Décris le style voulu (ex. *"couleurs naturelles et cohérentes"*)
   - Choisis le nombre de couleurs (4 par défaut)
   - **Lancer la colorisation**

L'avancement s'affiche en direct dans la fenêtre. Les fichiers `.3mf` arrivent dans un
sous-dossier `colorise` à côté de tes fichiers.

## La clé API

**Demandée une seule fois** : au premier lancement, colle-la, elle est enregistrée dans
`cle_api.enc`, **chiffrée avec ton compte Windows** (illisible sur une autre machine ou par
quelqu'un d'autre). Les lancements suivants la pré-remplissent automatiquement.

**⚠️ Si tu partages ces fichiers sur le forum** : partage uniquement `Lancer-Coloriser-STL.bat`
et `Coloriser-STL-GUI.ps1`, **jamais** `cle_api.enc` qui apparaît après le premier lancement —
c'est ta clé. Chaque personne doit coller la sienne au premier lancement, sinon ce sont tes
propres crédits Meshy qui seraient utilisés par les autres.

## Coût

Chaque figurine consomme environ **20 crédits Meshy** (détail confirmé par Tomyn le 2026-10-07
dans son tableau de bord : étape Retexture à 10 crédits, plus Multi-Color Print à 10 crédits —
une première lecture avait suggéré 56 crédits, corrigée depuis). Une estimation s'affiche
automatiquement dès qu'un dossier ou des fichiers sont chargés, et l'appli vérifie ton solde réel
(API Meshy) juste avant de lancer un lot, avec un avertissement si ça risque de dépasser ce qu'il
te reste. Avec l'option ".obj" (voir plus bas), tu économises les 10 crédits du Multi-Color
Print : ~10 crédits au lieu de 20.

Côté Tripo, confirmé par Tomyn le 2026-10-07 : **5 crédits pour l'import + 10 crédits pour la
texturation**, plus l'étape de conversion (variable, ~5 crédits observés) — soit environ **20
crédits par figurine** au total, sur une échelle de crédits séparée de celle de Meshy (pas
garanti que ce soit la même "unité"). L'import n'est donc **pas gratuit**, contrairement à ce
qu'on pensait au départ (il n'apparaissait simplement jamais dans le total affiché avant cette
date — corrigé).

## Autres fonctions

- **Comparer Meshy et Tripo** (case à cocher, nécessite les deux clés API) : lance les deux
  fournisseurs sur chaque fichier et affiche les deux résultats côte à côte (deux colonnes dans
  l'onglet "Résultats colorisés", une par fournisseur), pour choisir celui qui convient le mieux
  en double-cliquant dessus. Double le coût en crédits à chaque génération (les deux sont
  facturés) — reste décoché par défaut. Les résultats sont suffixés `_meshy`/`_tripo` pour ne
  jamais s'écraser l'un l'autre : un fichier `<nom>_meshy_colorise.3mf` pour Meshy, un dossier
  `<nom>_tripo_colorise/` (contenant le `.obj` et ses fichiers associés) pour Tripo.
- **Case "Inclure"** sur chaque vignette de départ : décoche un fichier pour l'exclure du
  traitement sans changer de dossier.
- **Glisser-déposer** un dossier ou des fichiers 3D directement sur la fenêtre.
- **Annuler** en cours de traitement (réagit vite, même en pleine attente de Meshy).
- **Relancer les échecs** : si certains fichiers échouent sur un gros lot, un bouton permet de ne
  retraiter que ceux-là plutôt que de tout refaire (et repayer) depuis zéro.
- **Avertissement avant d'écraser** un résultat déjà présent dans le dossier de sortie — ou,
  avec la case "Garder un historique des essais", chaque résultat est horodaté et rien n'est
  jamais écrasé.
- **Historique des lots** consultable (date, réussites, échecs, crédits consommés par lot).
- **Tout cocher / Tout décocher** d'un coup sur la galerie de départ.
- **Temps écoulé** affiché pendant le traitement (fichier en cours, durée).
- **Notification Windows** à la fin du traitement, pas besoin de garder l'œil sur la fenêtre.
- Un fichier de plus de 50 Mo (limite Meshy) est maintenant **refusé avant l'envoi**, pas
  seulement signalé après coup — évite un appel API voué à l'échec.
- **La clé API est vérifiée explicitement** avant de lancer (pas seulement le solde) : une clé
  invalide ou expirée est détectée tout de suite, plutôt qu'au premier fichier qui échoue après
  plusieurs minutes d'attente.
- **Barre de progression visuelle** pendant le traitement, en plus du texte détaillé.
- **Bouton "Enreg. journal"** pour sauvegarder le détail complet d'un lot dans un fichier texte à
  part (utile pour comparer deux essais avec des prompts différents, par exemple).
- Le dernier prompt personnalisé ("Autre") est mémorisé d'un lancement à l'autre.

## Si un fichier échoue

Le traitement continue avec les fichiers suivants plutôt que de tout arrêter ; le bilan final
indique combien ont réussi et combien ont échoué, avec le détail de chaque échec dans le
journal.

## Alternative : ligne de commande

Pour qui préfère la ligne de commande, `coloriser_stl.py` (Python) et `Coloriser-STL.ps1`
(PowerShell, console) font exactement la même chose sans interface graphique.
