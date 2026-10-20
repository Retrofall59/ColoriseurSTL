package com.tomyn.coloriseurstl

/**
 * Porte depuis la version Windows (Generer-DescriptionMakerWorld, 13/10/2026) : pas de depot
 * automatise possible vers MakerWorld (pas d'API publique) - genere juste un titre et un texte
 * prets a coller a la main dans leur formulaire de depot (champs confirmes dans leur doc
 * officielle : nom, description). Fonction pure, sans dependance Android, testable directement en
 * JVM comme Convertisseur3MF/CompteurTriangles.
 */
object GenerateurDescriptionMakerWorld {

    data class Description(val titre: String, val texte: String)

    /**
     * @param nomBase nom du fichier source sans extension (ex: "dragon_rouge" ou, avec l'option
     *   "Garder un historique des essais", "dragon_rouge_20261013_231500").
     * @param prompt le style/couleurs voulues tel que saisi par l'utilisateur (peut etre vide,
     *   voir le lancement sans prompt porte le 21/10/2026 - meme edge case que Windows : la ligne
     *   "Rendu voulu :" reste alors sans suite, assume tel quel, pas une regression).
     */
    fun generer(nomBase: String, prompt: String): Description {
        // Suffixe d'horodatage ajoute par l'option "Garder un historique des essais"
        // (ex: "_20261013_231500") - n'a rien a faire dans un titre de depot.
        var titreBrut = nomBase.replace(Regex("_\\d{8}_\\d{6}$"), "")
        titreBrut = titreBrut.replace(Regex("[_\\-]+"), " ").trim()
        val titre = if (titreBrut.isNotEmpty()) {
            titreBrut.lowercase().split(" ").joinToString(" ") { mot ->
                if (mot.isEmpty()) mot else mot.replaceFirstChar { it.uppercase() }
            }
        } else nomBase

        var descriptionPrompt = prompt.trim()
        if (descriptionPrompt.isNotEmpty() && !Regex("[.!?]\\s*$").containsMatchIn(descriptionPrompt)) {
            descriptionPrompt += "."
        }

        val texte = buildString {
            append(titre).append("\n\n")
            append("Figurine imprimee en 3D et colorisee automatiquement, prete a trancher en multi-couleurs (AMS).\n")
            append("Rendu voulu : ").append(descriptionPrompt).append("\n\n")
            append("(Titre et description generes automatiquement par Coloriser-STL a partir du style choisi - a relire et completer avant de deposer le modele.)")
        }
        return Description(titre, texte)
    }
}
