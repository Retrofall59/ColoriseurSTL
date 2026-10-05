package com.tomyn.coloriseurstl

import android.util.Base64
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Appels a l'API Meshy (Retexture puis Multi-Color Print), meme logique et memes parametres que
 * la version PowerShell du projet "Coloriser-STL" (Windows), deja validee en conditions reelles.
 * Documentation officielle utilisee :
 *   https://docs.meshy.ai/en/api/retexture
 *   https://docs.meshy.ai/en/api/multi-color-print
 */
object MeshyApiClient {

    private const val BASE_URL = "https://api.meshy.ai/openapi/v1"
    private const val INTERVALLE_POLL_MS = 5000L
    private const val TIMEOUT_TACHE_MS = 20 * 60 * 1000L // 20 minutes max par etape

    class ErreurApi(message: String) : Exception(message)

    enum class StatutCle { VALIDE, INVALIDE, INCONNU }
    data class VerificationCle(val statut: StatutCle, val solde: Int?)

    /**
     * Verifie la cle ET recupere le solde en un seul appel (meme endpoint /balance) :
     *   VALIDE   -> solde contient le vrai solde
     *   INVALIDE -> cle refusee par Meshy (HTTP 401/403), bloquant
     *   INCONNU  -> echec pour une autre raison (reseau, timeout...), pas bloquant en soi
     */
    fun verifierCleEtSolde(cleApi: String): VerificationCle {
        return try {
            val reponse = requete("GET", "/balance", cleApi)
            VerificationCle(StatutCle.VALIDE, reponse.optInt("balance", 0))
        } catch (e: ErreurApi) {
            if (e.message?.startsWith("HTTP 401") == true || e.message?.startsWith("HTTP 403") == true) {
                VerificationCle(StatutCle.INVALIDE, null)
            } else {
                VerificationCle(StatutCle.INCONNU, null)
            }
        } catch (e: Exception) {
            VerificationCle(StatutCle.INCONNU, null)
        }
    }

    data class ResultatTache(val statut: String, val progres: Int, val json: JSONObject)

    interface EcouteurAvancement {
        fun surProgres(etape: String, statut: String, progres: Int)
    }

    private fun requete(methode: String, chemin: String, cleApi: String, corps: JSONObject? = null): JSONObject {
        val url = URL("$BASE_URL$chemin")
        val connexion = url.openConnection() as HttpURLConnection
        try {
            connexion.requestMethod = methode
            connexion.setRequestProperty("Authorization", "Bearer $cleApi")
            connexion.connectTimeout = 30000
            connexion.readTimeout = 30000

            if (corps != null) {
                connexion.doOutput = true
                connexion.setRequestProperty("Content-Type", "application/json")
                OutputStreamWriter(connexion.outputStream, Charsets.UTF_8).use { it.write(corps.toString()) }
            }

            val codeStatut = connexion.responseCode
            val flux = if (codeStatut in 200..299) connexion.inputStream else connexion.errorStream
            val reponseTexte = BufferedReader(InputStreamReader(flux, Charsets.UTF_8)).use { it.readText() }

            if (codeStatut !in 200..299) {
                val message = try { JSONObject(reponseTexte).optString("message", reponseTexte) } catch (e: Exception) { reponseTexte }
                throw ErreurApi("HTTP $codeStatut : $message")
            }
            return JSONObject(reponseTexte)
        } finally {
            connexion.disconnect()
        }
    }

    private fun attendreTache(chemin: String, cleApi: String, libelle: String, ecouteur: EcouteurAvancement?): JSONObject {
        val debut = System.currentTimeMillis()
        while (true) {
            if (System.currentTimeMillis() - debut > TIMEOUT_TACHE_MS) {
                throw ErreurApi("$libelle : pas de reponse apres ${TIMEOUT_TACHE_MS / 60000} min")
            }
            val tache = requete("GET", chemin, cleApi)
            val statut = tache.optString("status")
            val progres = tache.optInt("progress", 0)
            when (statut) {
                "SUCCEEDED" -> return tache
                "FAILED" -> {
                    val msg = tache.optJSONObject("task_error")?.optString("message") ?: "raison inconnue"
                    throw ErreurApi("$libelle a echoue : $msg")
                }
                "CANCELED" -> throw ErreurApi("$libelle a ete annulee")
                else -> ecouteur?.surProgres(libelle, statut, progres)
            }
            Thread.sleep(INTERVALLE_POLL_MS)
        }
    }

    /**
     * Lance la texturation (etape 1) puis la reduction en couleurs imprimables (etape 2), de
     * maniere synchrone (bloquante) - a appeler depuis un thread d'arriere-plan, jamais depuis
     * le thread principal de l'interface.
     *
     * @return l'URL de telechargement du fichier .3mf final, et l'URL d'apercu fourni par Meshy
     */
    fun coloriser(
        octetsStl: ByteArray,
        prompt: String,
        maxCouleurs: Int,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null
    ): ResultatColorisation {
        val dataUri = "data:application/octet-stream;base64," + Base64.encodeToString(octetsStl, Base64.NO_WRAP)

        val corpsRetexture = JSONObject()
            .put("model_url", dataUri)
            .put("text_style_prompt", prompt)
            .put("enable_original_uv", false)
        val reponseRetexture = requete("POST", "/retexture", cleApi, corpsRetexture)
        val idRetexture = reponseRetexture.getString("result")

        val tacheRetexture = attendreTache("/retexture/$idRetexture", cleApi, "Retexture", ecouteur)
        val creditsRetexture = tacheRetexture.optInt("consumed_credits", 0)
        val urlApercu = tacheRetexture.optString("thumbnail_url", "")

        val corpsImpression = JSONObject()
            .put("input_task_id", idRetexture)
            .put("max_colors", maxCouleurs)
            .put("style", "cartoon")
            .put("printer_brand", "bambu")
        val reponseImpression = requete("POST", "/print/multi-color", cleApi, corpsImpression)
        val idImpression = reponseImpression.getString("result")

        val tacheImpression = attendreTache("/print/multi-color/$idImpression", cleApi, "Multi-Color Print", ecouteur)
        val creditsImpression = tacheImpression.optInt("consumed_credits", 0)
        val url3mf = tacheImpression.getJSONObject("model_urls").getString("3mf")

        return ResultatColorisation(url3mf, urlApercu, creditsRetexture + creditsImpression)
    }

    data class ResultatColorisation(val url3mf: String, val urlApercu: String, val creditsConsommes: Int)

    /** Telecharge un fichier distant (le .3mf final, ou l'image d'apercu) en octets bruts. */
    fun telecharger(url: String): ByteArray {
        val connexion = URL(url).openConnection() as HttpURLConnection
        try {
            connexion.connectTimeout = 30000
            connexion.readTimeout = 60000
            return connexion.inputStream.readBytes()
        } finally {
            connexion.disconnect()
        }
    }
}
