package com.tomyn.coloriseurstl

import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * Portage de `Invoquer-AvecReessaiReseau` (Windows, Coloriser-STL-GUI.ps1 ligne 3718) : la
 * version Android n'avait AUCUNE logique de reessai sur les appels reseau (MeshyApiClient.kt,
 * TripoApiClient.kt faisaient tous des appels HttpURLConnection en une seule tentative), alors
 * que Windows enveloppe quasiment tous ses appels (polling, POST, telechargements) dans ce
 * mecanisme - ecart de fiabilite reel compte tenu de l'usage mobile de l'appli (reseau
 * intermittent), trouve par comparaison systematique Windows/Android, jamais signale par Tomyn.
 *
 * Ne reessaie QUE sur une erreur clairement transitoire (coupure, delai depasse, DNS, 5xx) -
 * jamais sur une vraie erreur API (4xx, cle invalide, contenu refuse, etc.), exactement comme
 * cote Windows (regex $script:REGEX_ERREUR_RESEAU_TRANSITOIRE).
 *
 * Module pur sans dependance Android - verifiable par execution JVM reelle (pas seulement
 * compilation), comme GenerateurDescriptionMakerWorld.kt.
 */
object ReessaiReseau {

    const val TENTATIVES_PAR_DEFAUT = 3
    const val DELAI_MS_PAR_DEFAUT = 4000L
    private const val PAS_ATTENTE_ANNULATION_MS = 200L

    /**
     * Meme marqueur que cote Windows ($script:ANNULATION_MARQUEUR / "ANNULATION_DEMANDEE") -
     * ColorisationService.kt reconnait deja ce message partout ailleurs dans le pipeline
     * (`if (e.message == "ANNULATION_DEMANDEE") ...`), donc jeter cette exception depuis ici
     * s'integre sans rien changer cote appelant.
     */
    class AnnulationDemandeeException : Exception("ANNULATION_DEMANDEE")

    // Equivalent du regex Windows $script:REGEX_ERREUR_RESEAU_TRANSITOIRE, adapte au texte des
    // messages produits par requete()/requeteJson()/telecharger() ici (ex: "HTTP 503 : ...") et
    // aux messages d'exceptions Java usuels (timeout, connexion reinitialisee/refusee...).
    private val REGEX_MESSAGE_TRANSITOIRE = Regex(
        "(?i)timed?[\\s-]?out|delai d'attente|unable to connect|impossible de se connecter|" +
            "connection.*(reset|refused|closed)|connexion.*(reinitialisee|refusee|fermee|interrompue)|" +
            "forcibly closed|existing connection was closed|could not be resolved|" +
            "temporarily unavailable|service unavailable|gateway time-?out|bad gateway"
    )
    private val REGEX_STATUT_5XX = Regex("""\bHTTP 5\d{2}\b""")

    /** Vrai seulement pour une erreur reseau transitoire - jamais pour une vraie erreur API. */
    fun estErreurTransitoire(e: Throwable): Boolean {
        if (e is SocketTimeoutException || e is ConnectException ||
            e is UnknownHostException || e is InterruptedIOException
        ) {
            return true
        }
        val message = e.message ?: return false
        return REGEX_STATUT_5XX.containsMatchIn(message) || REGEX_MESSAGE_TRANSITOIRE.containsMatchIn(message)
    }

    /**
     * Execute [bloc], en reessayant jusqu'a [tentatives] fois (avec [delaiMs] entre chaque) si et
     * seulement si l'erreur rencontree est transitoire. Relance immediatement toute autre erreur.
     * A appeler depuis un thread d'arriere-plan (bloquant, comme les appels reseau sous-jacents).
     *
     * [estAnnule] est reverifie avant chaque tentative ET toutes les ~200ms pendant l'attente
     * entre deux tentatives (comme la boucle DoEvents cote Windows) - une annulation demandee par
     * l'utilisateur pendant les 4s d'attente interrompt immediatement plutot que de patienter pour
     * rien. [surTentativeEchouee] permet a l'appelant de logguer la tentative manquee (tentative,
     * total, message, delai avant le prochain essai) - ReessaiReseau reste sans dependance Android
     * (donc testable par vraie execution JVM) en laissant le "ou" du log a l'appelant.
     */
    fun <T> executer(
        tentatives: Int = TENTATIVES_PAR_DEFAUT,
        delaiMs: Long = DELAI_MS_PAR_DEFAUT,
        estAnnule: () -> Boolean = { false },
        surTentativeEchouee: (tentative: Int, max: Int, messageErreur: String, delaiMs: Long) -> Unit = { _, _, _, _ -> },
        bloc: () -> T
    ): T {
        var derniereErreur: Exception? = null
        for (tentative in 1..tentatives) {
            if (estAnnule()) throw AnnulationDemandeeException()
            try {
                return bloc()
            } catch (e: AnnulationDemandeeException) {
                throw e
            } catch (e: Exception) {
                derniereErreur = e
                if (tentative >= tentatives || !estErreurTransitoire(e)) {
                    throw e
                }
                surTentativeEchouee(tentative, tentatives, e.message ?: e.toString(), delaiMs)
                val finAttente = System.currentTimeMillis() + delaiMs
                while (System.currentTimeMillis() < finAttente) {
                    if (estAnnule()) throw AnnulationDemandeeException()
                    try {
                        Thread.sleep(PAS_ATTENTE_ANNULATION_MS)
                    } catch (ie: InterruptedException) {
                        Thread.currentThread().interrupt()
                        throw e
                    }
                }
            }
        }
        throw derniereErreur ?: IllegalStateException("echec reseau sans erreur capturee")
    }
}
