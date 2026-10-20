package com.tomyn.coloriseurstl

import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * 21/10/2026, porte depuis la version Windows (Verifier-MiseAJourDisponible) - adapte au modele
 * de version Android : contrairement a Windows (qui compare a la date du dernier commit sur le
 * .ps1, consulte directement a l'edition), l'APK vient d'une Release GitHub taguee (voir
 * .github/workflows/build.yml) - la comparaison se fait donc contre la derniere Release publiee
 * (releases/latest), celle avec un APK reellement telechargeable, pas contre le dernier commit
 * brut qui pourrait tres bien n'avoir jamais ete tague/compile en APK.
 */
object VerificateurMiseAJour {
    private const val URL_DERNIERE_RELEASE = "https://api.github.com/repos/Retrofall59/coloriseurstl/releases/latest"

    sealed class Resultat {
        data class NouvelleVersion(val versionDistante: String, val urlRelease: String) : Resultat()
        object AJour : Resultat()
        data class Erreur(val message: String) : Resultat()
    }

    /**
     * Extrait le numero apres "0." d'une version "0.NN" (prefixe "v" eventuel tolere, comme les
     * tags "v*" acceptes par le workflow en plus des tags numeriques bruts) - null si la chaine
     * ne correspond pas a ce format (jamais arrive jusqu'ici dans l'historique des tags, mais pas
     * suppose a vie).
     */
    private fun numeroVersion(version: String): Int? =
        Regex("^v?0\\.(\\d+)$").find(version.trim())?.groupValues?.get(1)?.toIntOrNull()

    /** Bloquant (appel reseau) - a invoquer depuis un thread d'arriere-plan, jamais le thread UI. */
    fun verifier(versionInstallee: String): Resultat {
        return try {
            val connexion = URL(URL_DERNIERE_RELEASE).openConnection() as HttpURLConnection
            connexion.requestMethod = "GET"
            connexion.setRequestProperty("User-Agent", "ColoriseurSTL")
            connexion.connectTimeout = 8000
            connexion.readTimeout = 8000
            val codeStatut = connexion.responseCode
            val flux = if (codeStatut in 200..299) connexion.inputStream else connexion.errorStream
            val texte = BufferedReader(InputStreamReader(flux, Charsets.UTF_8)).use { it.readText() }
            connexion.disconnect()
            if (codeStatut !in 200..299) {
                return Resultat.Erreur("GitHub a répondu HTTP $codeStatut - vérification impossible pour l'instant.")
            }
            val json = JSONObject(texte)
            val tagDistant = json.optString("tag_name", "")
            val urlRelease = json.optString("html_url", "")
            val numDistant = numeroVersion(tagDistant)
            val numInstalle = numeroVersion(versionInstallee)
            if (numDistant == null || numInstalle == null) {
                Resultat.Erreur("Format de version inattendu reçu de GitHub ('$tagDistant') - vérification impossible pour l'instant.")
            } else if (numDistant > numInstalle) {
                Resultat.NouvelleVersion(tagDistant, urlRelease)
            } else {
                Resultat.AJour
            }
        } catch (e: Exception) {
            Resultat.Erreur("Impossible de contacter GitHub (pas de connexion, ou GitHub inaccessible pour l'instant).")
        }
    }
}
