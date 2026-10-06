package com.tomyn.coloriseurstl

/**
 * Memes presets que la version PowerShell (Windows) du projet, pour rester coherent entre les
 * deux. Structure a deux niveaux : une categorie de sujet (Personnage, Decor, Personnage et
 * decor, Piece / Autre) filtre la liste de prompts proposee. Chaque categorie a sa propre
 * entree "Autre" (texte libre, valeur null dans la LinkedHashMap).
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
        )
    )

    val nomsCategories: List<String> get() = categories.keys.toList()

    /** Libelles de la categorie donnee, dans l'ordre. */
    fun libellesPour(categorie: String): List<String> = categories[categorie]?.keys?.toList() ?: emptyList()

    /** Texte du prompt pour un libelle donne dans une categorie donnee ; null si "Autre". */
    fun textePour(categorie: String, libelle: String): String? = categories[categorie]?.get(libelle)
}
