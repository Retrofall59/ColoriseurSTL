package com.tomyn.coloriseurstl

/** Memes presets que la version PowerShell (Windows) du projet, pour rester coherent entre les deux. */
object PromptsPredefinis {

    const val LIBELLE_AUTRE = "Autre (texte libre ci-dessous)"

    /** Ordre de la liste conserve (LinkedHashMap), "Autre" en dernier avec une valeur null. */
    val liste: LinkedHashMap<String, String?> = linkedMapOf(
        "Couleurs naturelles et coherentes" to "couleurs naturelles et coherentes",
        "Couleurs realistes, fideles au sujet represente" to "couleurs naturelles et realistes, fideles au sujet represente",
        "Couleurs vives et dynamiques, style jouet" to "couleurs vives et dynamiques, style jouet",
        "Teintes douces, peu saturees, style figurine peinte main" to "teintes douces et peu saturees, style figurine peinte a la main",
        "Camaieu d'une seule teinte, degrade coherent" to "camaieu d'une seule teinte avec un degrade coherent, pas de couleurs qui jurent entre elles",
        "Pastel doux et clair" to "palette de couleurs pastel, douces et claires",
        "Metallique, style bronze/laiton antique" to "finition metallique, style bronze ou laiton antique vieilli",
        "Patine ancienne, aspect vieilli/use" to "aspect vieilli et patine, comme un objet ancien use par le temps",
        "Noir et blanc contrastes, style gravure" to "noir et blanc fortement contrastes, style gravure ou lithographie",
        "Fantastique, couleurs surnaturelles" to "couleurs fantastiques et surnaturelles, adaptees a une creature magique",
        LIBELLE_AUTRE to null
    )

    val libelles: List<String> get() = liste.keys.toList()
}
