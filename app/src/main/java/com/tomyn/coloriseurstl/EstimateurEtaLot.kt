package com.tomyn.coloriseurstl

/**
 * Portage fidele de `Obtenir-TexteEtaLot` (Windows, ligne 3746) : moyenne glissante simple
 * (temps ecoule / fichiers deja faits) x fichiers restants - pas une vraie prediction, mais
 * largement suffisant pour se faire une idee sur un gros lot plutot que de n'avoir que le
 * chrono ecoule. Utile surtout sur les lots de 200+ fichiers que le collegue dessinateur de
 * Tomyn lui envoie (la seule barre de progression ne dit pas combien de temps il reste a
 * attendre). Trouve en continuant la comparaison Windows/Android, porte sur demande de Tomyn
 * ("comme dit j'ai mon collegue dessinateur qui parfois meme souvent m'envoie des dossiers de
 * plus de 200 fichiers").
 *
 * [nombreFaits] est le compte APRES le dernier fichier termine, pas le fichier en cours de
 * traitement - meme convention que cote Windows (indexFichierCourant - 1).
 *
 * Module pur sans dependance Android (comme GenerateurDescriptionMakerWorld.kt,
 * ReessaiReseau.kt, SauvegardeConfig.kt) - verifiable par execution JVM reelle.
 */
object EstimateurEtaLot {

    /** Chaine vide tant qu'aucun fichier n'est encore termine (pas d'estimation fiable sur un
     * seul point de mesure) ou que le lot est deja termine. Sinon : " - reste <duree>". */
    fun texteEta(secondesEcoulees: Double, nombreFaits: Int, nombreTotal: Int): String {
        if (nombreFaits <= 0 || nombreFaits >= nombreTotal) return ""
        val dureeMoyenneParFichier = secondesEcoulees / nombreFaits
        val secondesRestantes = dureeMoyenneParFichier * (nombreTotal - nombreFaits)
        val resteTxt = when {
            secondesRestantes >= 3600 -> {
                val heures = (secondesRestantes / 3600).toInt()
                val minutes = ((secondesRestantes % 3600) / 60).toInt()
                "${heures}h${minutes.toString().padStart(2, '0')}"
            }
            secondesRestantes >= 60 -> "~${Math.ceil(secondesRestantes / 60).toInt()} min"
            else -> "moins d'1 min"
        }
        return " - reste $resteTxt"
    }

    /** Texte "MM:SS" pour le temps ecoule - meme format que $ecouleTexte cote Windows. */
    fun texteEcoule(secondesEcoulees: Double): String {
        val totalSecondes = secondesEcoulees.toLong().coerceAtLeast(0)
        val minutes = totalSecondes / 60
        val secondes = totalSecondes % 60
        return "${minutes.toString().padStart(2, '0')}:${secondes.toString().padStart(2, '0')}"
    }

    /**
     * Ligne de statut complete, meme forme que `$txtEstimationCout.Text` cote Windows :
     * "Fichier X/Y - ecoule : MM:SS - reste <duree> - N credit(s) depenses - <etape>".
     * [etapeTexte] optionnel (vide = omis, l'etape precise n'est pas toujours connue cote Android).
     */
    fun ligneStatut(
        indexFichierCourant: Int,
        totalFichiersLot: Int,
        secondesEcoulees: Double,
        creditsReelsLot: Int,
        etapeTexte: String = ""
    ): String {
        val ecouleTxt = texteEcoule(secondesEcoulees)
        val etaTxt = texteEta(secondesEcoulees, indexFichierCourant - 1, totalFichiersLot)
        val creditsTxt = " - $creditsReelsLot credit(s) dépensés"
        val suffixeEtape = if (etapeTexte.isNotEmpty()) " - $etapeTexte" else ""
        return "Fichier $indexFichierCourant/$totalFichiersLot - écoulé : $ecouleTxt$etaTxt$creditsTxt$suffixeEtape"
    }
}
