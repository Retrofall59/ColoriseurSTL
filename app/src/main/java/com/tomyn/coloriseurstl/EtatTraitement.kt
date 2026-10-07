package com.tomyn.coloriseurstl

import android.graphics.Bitmap
import android.net.Uri

/**
 * Etat du traitement en cours, partage entre ColorisationService (qui l'ecrit, depuis un thread
 * d'arriere-plan) et MainActivity (qui le lit en sondant periodiquement pour rafraichir
 * l'affichage). Objet singleton (survit a la destruction/recreation de l'activite, comme les
 * listes "persistantes" de MainActivity) - c'est ce qui permet au traitement de continuer
 * independamment de l'ecran, et a l'ecran de retrouver ou en est le traitement a tout moment,
 * meme apres avoir ete recree.
 *
 * Les listes sont des copies defensives (synchronized) cote lecture pour eviter une
 * ConcurrentModificationException si le service modifie la liste pendant que l'activite la lit -
 * usage volontairement simple (pas de corountines/Flow) pour rester coherent avec le reste du
 * projet, qui n'utilise aucune bibliotheque de concurrence avancee.
 */
object EtatTraitement {
    // fournisseur : "Meshy" ou "Tripo" en mode comparaison (affiche comme badge sur la vignette,
    // voir MainActivity.creerVignette) ; chaine vide hors comparaison (un seul fournisseur actif,
    // pas besoin de le repeter sur chaque vignette).
    data class ResultatColorise(val uri: Uri, val nom: String, val apercu: Bitmap?, val fournisseur: String = "")
    data class FichierEchec(val uri: Uri, val nom: String, val raison: String)

    @Volatile var enCours: Boolean = false
    @Volatile var annulationDemandee: Boolean = false
    @Volatile var indexFichierCourant: Int = 0
    @Volatile var totalFichiersLot: Int = 0
    @Volatile var etapeTexte: String = ""
    @Volatile var debutTraitement: Long = 0L
    @Volatile var creditsReelsLot: Int = 0

    private val journalInterne = StringBuilder()
    private val resultatsInternes = mutableListOf<ResultatColorise>()
    private val echecsInternes = mutableListOf<FichierEchec>()

    @Synchronized fun ecrireJournal(ligne: String) {
        if (journalInterne.isNotEmpty()) journalInterne.append("\n")
        journalInterne.append(ligne)
    }

    @Synchronized fun journalComplet(): String = journalInterne.toString()

    @Synchronized fun viderJournal() { journalInterne.clear() }

    @Synchronized fun ajouterResultat(resultat: ResultatColorise) { resultatsInternes.add(resultat) }

    @Synchronized fun resultats(): List<ResultatColorise> = resultatsInternes.toList()

    @Synchronized fun viderResultats() { resultatsInternes.clear() }

    @Synchronized fun ajouterEchec(echec: FichierEchec) { echecsInternes.add(echec) }

    @Synchronized fun echecs(): List<FichierEchec> = echecsInternes.toList()

    @Synchronized fun viderEchecs() { echecsInternes.clear() }

    fun reinitialiserPourNouveauLot() {
        viderJournal()
        viderResultats()
        viderEchecs()
        enCours = true
        annulationDemandee = false
        indexFichierCourant = 0
        debutTraitement = System.currentTimeMillis()
        creditsReelsLot = 0
    }
}
