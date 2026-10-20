package com.tomyn.coloriseurstl

/**
 * Memes presets que la version PowerShell (Windows) du projet, pour rester coherent entre les
 * deux. Structure a deux niveaux : une categorie de sujet (Personnage, Animal de compagnie,
 * Buste / statuette commemorative, Decor, Terrain / plateau de jeu, Personnage et decor,
 * Vehicule, Piece / Autre, Food / nourriture factice, Bijou / vetement fonctionnel) filtre la
 * liste de prompts proposee. Chaque categorie a sa propre entree "Autre" (texte libre, valeur
 * null dans la LinkedHashMap).
 *
 * 21/10/2026 : completion des 10 categories (6 manquaient encore cote Android - seules
 * Personnage/Decor/Personnage et decor/Piece-Autre avaient ete portees initialement). La
 * categorie dynamique "Mes favoris" de la version Windows (prompts sauvegardes par Tomyn sous un
 * nom, persistes dans prompts-favoris.json) n'est volontairement PAS portee ici - demande a part
 * si besoin, plus gros morceau (UI de sauvegarde/suppression + persistance).
 */
object PromptsPredefinis {

    const val LIBELLE_AUTRE = "Autre (texte libre ci-dessous)"

    /** Ordre des categories et des entrees dans chacune conserve (LinkedHashMap). */
    val categories: LinkedHashMap<String, LinkedHashMap<String, String?>> = linkedMapOf(
        "Personnage" to linkedMapOf(
            "Realiste multicolore" to "couleurs realistes et coherentes, nettement differenciees selon les elements du personnage (peau, cheveux, vetements, accessoires), sans teinte unique sur l'ensemble",
            "Stylise vif / cartoon" to "couleurs vives, saturees et stylisees, inspirees des jeux video ou du dessin anime, contrastes marques entre les elements",
            "Armure fantasy" to "armure et equipement avec metal, cuir et tissu nettement distincts, reflets metalliques sur les parties en metal, legere patine",
            "Figurine peinte a la main" to "rendu type figurine de collection peinte a la main, couleurs mates et nuancees, ombrages doux entre les zones",
            "Super-heros / comics" to "couleurs franches et contrastees type bande dessinee, zones de couleur bien delimitees, pas de degrade",
            "Costume d'epoque" to "tissus et matieres d'epoque realistes, couleurs sobres et historiquement coherentes, broderies et details distincts si presents",
            "Science-fiction" to "combinaison technique avec des zones distinctes pour le tissu, les plaques rigides, le plastron et la visiere, finition high-tech",
            "Creature / monstre" to "ecailles, fourrure ou peau avec des variations de teinte naturelles, cornes, griffes ou dents dans une couleur distincte du corps",
            "Style jouet / chibi" to "couleurs pastel et douces, rendu mignon type jouet pour enfant, zones de couleur simples et bien separees",
            "Buste / portrait realiste" to "couleurs de peau realistes et nuancees, details du visage et des cheveux soignes, rendu photorealiste",
            LIBELLE_AUTRE to null
        ),
        "Animal de compagnie" to linkedMapOf(
            "Realiste pelage/poil" to "pelage ou poil avec des couleurs realistes et naturelles, variations de teinte fideles a la robe de l'animal, truffe et coussinets dans une couleur distincte",
            "Portrait souvenir fidele" to "couleurs aussi fideles que possible a la photo d'origine de l'animal, robe, yeux et marques particulieres bien reconnaissables",
            "Stylise mignon / chibi" to "couleurs douces et pastel, rendu mignon et simplifie, zones de couleur bien separees sans trop de nuances",
            "Figurine peinte a la main" to "rendu type figurine de collection peinte a la main, couleurs mates et nuancees, ombrages doux entre les zones du pelage",
            "Chat" to "pelage avec des couleurs et motifs realistes (uni, tigre, ecaille ou tachete selon le cas), yeux et truffe bien distincts du pelage",
            "Chien" to "pelage avec des couleurs et motifs realistes selon la race, truffe, yeux, coussinets et collier eventuel bien distincts",
            "Oiseau" to "plumage avec des couleurs vives et nettement differenciees entre les zones (tete, ailes, poitrine, queue), bec et pattes dans une teinte distincte",
            "Animal de ferme / exotique" to "pelage, plumage ou peau avec des couleurs realistes et naturelles propres a l'espece, details (cornes, bec, ecailles) bien distincts",
            "Race a poil long" to "pelage long et fourni avec des variations de teinte naturelles, meches et degrades doux, sans aplat uniforme",
            "Memorial / hommage" to "couleurs fideles et apaisees a la robe reelle de l'animal, rendu doux et soigne, adapte a une piece souvenir",
            LIBELLE_AUTRE to null
        ),
        "Buste / statuette commemorative" to linkedMapOf(
            "Portrait fidele et sobre" to "couleurs de peau et de cheveux realistes et fideles a la photo d'origine, rendu digne et sobre, sans effet stylise",
            "Noir et blanc / sepia" to "rendu en camaieu de gris ou de sepia, sans couleur vive, effet photo ancienne ou buste classique",
            "Bronze / statue classique" to "finition type bronze patine ou pierre claire, teinte uniforme et sobre avec de legeres variations de patine",
            "Uniforme / tenue specifique" to "peau et cheveux realistes, uniforme ou tenue avec des couleurs fideles et nettement distinctes de la peau",
            "Portrait de couple / famille" to "couleurs realistes et coherentes pour chaque personne representee, bien differenciees entre les sujets",
            "Marbre clair" to "teinte uniforme type marbre ou platre clair, tres peu de variation de couleur, rendu epure et intemporel",
            "Medaille / bas-relief" to "couleur unique ou presque, type metal patine (bronze, laiton ou argent selon le cas), reliefs mis en valeur par l'ombrage naturel",
            "Trophee / recompense" to "finition metallique noble (or, argent ou bronze selon le cas), rendu brillant et soigne",
            "Souvenir de ceremonie" to "couleurs sobres et elegantes, tenue de ceremonie bien distincte de la peau et des cheveux, rendu soigne et discret",
            "Realiste multicolore detaille" to "couleurs realistes et nettement differenciees pour chaque element (peau, cheveux, vetements, accessoires), rendu detaille et vivant malgre le format buste",
            LIBELLE_AUTRE to null
        ),
        "Decor" to linkedMapOf(
            "Materiaux naturels" to "pierre, bois, vegetation et eau avec des couleurs naturelles et bien differenciees selon le materiau",
            "Architecture / batiment" to "pierre, toiture, bois et metal avec des couleurs distinctes et realistes selon chaque materiau de construction",
            "Decor stylise jeu video" to "couleurs vives et stylisees type jeu video, ambiance coloree et lisible, contrastes marques entre les elements du decor",
            "Paysage miniature" to "terrain, vegetation et eau avec des couleurs naturelles variees, rendu type diorama ou maquette",
            "Ruines / antique" to "pierre usee et patinee, mousse et vegetation envahissante, couleurs sobres et vieillies",
            "Interieur meuble" to "bois, tissu et metal des meubles avec des couleurs distinctes et realistes, ambiance chaleureuse",
            "Diorama fantastique" to "couleurs riches et legerement surnaturelles, elements magiques mis en valeur par des teintes distinctes",
            "Urbain / moderne" to "beton, metal et verre avec des couleurs sobres et realistes, contrastes nets entre les materiaux",
            "Vegetation dense / foret" to "multiples nuances de vert et de brun, feuillage, troncs et sol bien differencies",
            "Socle de jeu / wargaming" to "terrain et relief avec des couleurs naturelles variees, textures du sol bien marquees (herbe, roche, sable selon le cas)",
            LIBELLE_AUTRE to null
        ),
        "Terrain / plateau de jeu" to linkedMapOf(
            "Hexagones / cases lisibles" to "cases ou hexagones avec des couleurs nettement differenciees selon le type de terrain (herbe, eau, roche, sable, foret), contrastes marques pour rester lisible a distance",
            "Relief naturel varie" to "terrain avec des couleurs naturelles variees selon l'altitude et le type de sol, degrades doux entre les zones",
            "Plateau stylise jeu de societe" to "couleurs vives et franches type jeu de societe moderne, zones bien delimitees et faciles a distinguer d'un coup d'oeil",
            "Carte fantasy" to "couleurs riches et legerement stylisees pour les terrains fantastiques (lave, cristal, marais magique selon le cas), contrastes nets entre les zones",
            "Terrain militaire / wargame" to "couleurs sobres et realistes type terrain militaire (boue, beton, vegetation), marquages de zone bien visibles si presents",
            "Desert / aride" to "camaieu de sable, roche et terre avec des variations de teinte naturelles, peu de vegetation",
            "Hivernal / enneige" to "camaieu de blanc, gris et bleu clair pour la neige et la glace, elements rocheux ou vegetaux bien distincts en dessous",
            "Urbain / plateau de rue" to "beton, bitume et batiments avec des couleurs sobres et realistes, marquages au sol bien visibles",
            "Grille / damier technique" to "couleurs contrastees et constantes entre les cases pour un reperage facile, rendu simple et fonctionnel",
            "Ile / archipel" to "camaieu de bleu pour l'eau, vert pour la vegetation et sable clair pour les plages, transitions nettes entre les zones",
            LIBELLE_AUTRE to null
        ),
        "Personnage et decor" to linkedMapOf(
            "Scene complete equilibree" to "personnage et decor avec des couleurs realistes et bien differenciees, equilibre entre le sujet principal et son environnement",
            "Scene d'action" to "personnage mis en valeur par des couleurs plus vives que le decor, qui reste dans des teintes plus sobres en arriere-plan",
            "Diorama narratif" to "couleurs realistes et variees racontant une scene, chaque element (personnages, decor, accessoires) nettement differencie",
            "Scene historique" to "couleurs sobres et historiquement coherentes pour le personnage et le decor, materiaux d'epoque bien distincts",
            "Scene fantastique" to "couleurs riches et legerement surnaturelles pour le personnage et son environnement magique",
            "Scene sci-fi" to "couleurs technologiques et froides, materiaux metalliques et synthetiques bien differencies entre personnage et decor",
            "Scene quotidienne / realiste" to "couleurs naturelles et realistes pour l'ensemble de la scene, sans effet stylise",
            "Figurine et socle decore" to "personnage avec des couleurs bien differenciees, socle avec un decor distinct en couleurs plus sobres",
            "Scene nature" to "personnage et environnement naturel avec des couleurs variees et realistes, vegetation et terrain bien distincts",
            "Scene urbaine" to "personnage et decor urbain avec des couleurs realistes, materiaux de la ville (beton, metal, verre) bien differencies du personnage",
            LIBELLE_AUTRE to null
        ),
        "Vehicule" to linkedMapOf(
            "Carrosserie realiste" to "carrosserie, vitres, pneus et chrome avec des couleurs realistes et nettement distinctes selon le materiau, reflets metalliques sur la carrosserie",
            "Voiture de course / livree" to "couleurs vives et contrastees type livree de course, zones de sponsoring ou de numerotation bien delimitees",
            "Vehicule militaire" to "camouflage ou teinte unie type vehicule militaire, couleurs mates et sobres, usure legere",
            "Avion / aeronautique" to "fuselage, ailes, cockpit et reacteurs avec des couleurs realistes et bien differenciees, marquages distincts si presents",
            "Vaisseau spatial / sci-fi" to "coque technique avec des couleurs froides et metalliques, panneaux et hublots nettement distincts, legers reflets high-tech",
            "Vehicule d'epoque / vintage" to "carrosserie et interieur avec des couleurs d'epoque realistes, chrome et cuir bien distincts, patine legere",
            "Moto" to "carenage, selle, chrome et pneus avec des couleurs realistes et contrastees, finitions nettes entre les parties",
            "Vehicule utilitaire / chantier" to "carrosserie et elements fonctionnels avec des couleurs sobres et realistes type engin de chantier, marquages de securite distincts si presents",
            "Train / ferroviaire" to "wagons et locomotive avec des couleurs realistes et coherentes, marquages et numeros bien distincts de la carrosserie",
            "Bateau" to "coque, pont et superstructure avec des couleurs realistes et nettement differenciees, ligne de flottaison distincte si presente",
            LIBELLE_AUTRE to null
        ),
        "Piece / Autre" to linkedMapOf(
            "Piece mecanique realiste" to "couleurs realistes de metal, plastique et caoutchouc, usure et reflets metalliques bien rendus",
            "Objet du quotidien" to "couleurs realistes et naturelles correspondant au materiau reel de l'objet",
            "Neutre fonctionnel / prototype" to "couleurs sobres et distinctes entre les differentes parties, rendu simple adapte a un prototype fonctionnel",
            "Piece auto / moteur" to "metal, caoutchouc et plastique technique avec des couleurs realistes et des finitions distinctes selon le materiau",
            "Electronique / boitier" to "plastique, metal et elements techniques avec des couleurs nettes et bien separees entre les parties",
            "Outil / quincaillerie" to "metal et poignee avec des couleurs realistes et contrastees, finition fonctionnelle",
            "Piece industrielle usee" to "rouille, peinture ecaillee et metal use, couleurs vieillies et contrastees",
            "Objet design / deco" to "materiaux nobles (bois, metal, pierre ou verre selon le cas) avec des couleurs raffinees et bien differenciees",
            "Jouet / accessoire" to "couleurs vives et franches type plastique de jouet, zones de couleur bien separees",
            "Bijou / objet precieux" to "finitions metalliques nobles (or, argent ou bronze selon le cas) et pierres ou details avec des couleurs distinctes et un rendu brillant",
            LIBELLE_AUTRE to null
        ),
        "Food / nourriture factice" to linkedMapOf(
            "Gateau / patisserie" to "glacage, creme, fruits et decorations avec des couleurs appetissantes et nettement differenciees, rendu gourmand et realiste",
            "Plat realiste" to "aliments avec des couleurs naturelles et realistes propres a chaque ingredient, nettement differencies les uns des autres",
            "Fruits et legumes" to "couleurs vives et naturelles propres a chaque fruit ou legume, peau, chair et feuilles bien distinctes",
            "Glace / dessert froid" to "couleurs pastel et appetissantes, nappage, toppings et cornet ou pot bien distincts",
            "Boisson / cocktail" to "liquide, glacons et garniture avec des couleurs distinctes et un rendu translucide si pertinent",
            "Fast-food / street food" to "couleurs vives et franches type restauration rapide, emballage et aliment bien differencies",
            "Boulangerie / pain" to "croute doree et mie claire bien distinctes, variations de cuisson naturelles",
            "Confiserie / bonbons" to "couleurs vives et saturees type confiserie, zones de couleur bien separees et nettes",
            "Plateau de fromages / charcuterie" to "couleurs naturelles et realistes propres a chaque aliment, nettement differenciees entre les pieces du plateau",
            "Maquette miniature gourmande" to "couleurs appetissantes et realistes adaptees a une miniature decorative, finitions soignees malgre la petite echelle",
            LIBELLE_AUTRE to null
        ),
        "Bijou / vetement fonctionnel" to linkedMapOf(
            "Bijou porte au quotidien" to "finitions metalliques nobles (or, argent ou bronze selon le cas) adaptees a un usage reel, couleurs resistantes et uniformes, sans effet fragile",
            "Accessoire textile souple" to "couleurs uniformes et resistantes adaptees a une matiere flexible qui va plier et bouger, sans degrade fragile",
            "Pendentif / collier" to "chaine et pendentif avec des couleurs nettement distinctes, finition brillante ou mate selon le style voulu",
            "Bague / anneau" to "finition metallique uniforme et reguliere sur toute la surface, sans variation parasite due a la petite taille de la piece",
            "Bracelet articule" to "couleurs coherentes et uniformes sur l'ensemble des maillons ou segments, adaptees a une piece qui bouge",
            "Broche / epingle" to "couleurs nettes et bien delimitees, finition soignee adaptee a un petit accessoire visible de pres",
            "Accessoire de mode colore" to "couleurs vives et franches type accessoire de mode, zones de couleur bien separees",
            "Style minimaliste / epure" to "une ou deux couleurs sobres et uniformes, sans degrade ni detail superflu, rendu epure",
            "Boucle d'oreille" to "couleurs nettes et symetriques, finition soignee adaptee a une petite piece portee de pres",
            "Accessoire enfant" to "couleurs vives, douces et ludiques, zones de couleur simples et bien separees, sans detail fragile",
            LIBELLE_AUTRE to null
        )
    )

    val nomsCategories: List<String> get() = categories.keys.toList()

    /** Libelles de la categorie donnee, dans l'ordre. */
    fun libellesPour(categorie: String): List<String> = categories[categorie]?.keys?.toList() ?: emptyList()

    /** Texte du prompt pour un libelle donne dans une categorie donnee ; null si "Autre". */
    fun textePour(categorie: String, libelle: String): String? = categories[categorie]?.get(libelle)
}
