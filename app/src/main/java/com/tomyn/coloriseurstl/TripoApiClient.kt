package com.tomyn.coloriseurstl

import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Appels a l'API Tripo (presignation d'upload, texturation, conversion en 3MF colore), portage
 * fidele du pipeline PowerShell (Windows) - endpoints et logique valides en conditions reelles :
 * reservation d'upload, envoi du fichier, creation de tache de texturation et suivi de
 * progression tous confirmes fonctionnels avec de vraies cles/credits. Seule la toute derniere
 * etape (conversion /models/convert) n'a pas encore ete vue aboutir jusqu'au bout - les echecs
 * rencontres venaient d'erreurs internes cote serveur Tripo (confirme par les messages d'erreur
 * eux-memes), pas d'un probleme dans ces appels.
 *
 * Base documentee par le SDK Go officiel de VAST-AI-Research (societe editrice de Tripo) :
 *   https://pkg.go.dev/github.com/VAST-AI-Research/tripo-go-sdk
 *
 * Difference de fond avec Meshy a connaitre : Tripo encode la couleur par sommet du maillage
 * (degrade continu), pas une palette figee a N couleurs - pas de parametre "nombre de couleurs"
 * equivalent a maxCouleurs cote Tripo.
 */
object TripoApiClient {

    private const val BASE_URL = "https://openapi.tripo3d.ai/v3"
    private const val INTERVALLE_POLL_MS = 1000L
    private const val TIMEOUT_TACHE_MS = 20 * 60 * 1000L

    class ErreurApi(message: String) : Exception(message)

    interface EcouteurAvancement {
        fun surProgres(etape: String, statutBrut: String, progres: Int)
    }

    data class ResultatColorisation(val url3mf: String, val creditsConsommes: Int)

    private fun requeteJson(methode: String, chemin: String, cleApi: String, corps: JSONObject? = null): JSONObject {
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
            val reponse = JSONObject(reponseTexte)
            // La reponse Tripo enveloppe les donnees dans un champ "data" (confirme en test
            // reel), contrairement a Meshy qui renvoie directement l'objet a plat.
            return reponse.optJSONObject("data") ?: reponse
        } finally {
            connexion.disconnect()
        }
    }

    /**
     * Upload brut d'un tableau d'octets vers une URL presignee (S3). setFixedLengthStreamingMode
     * avec la taille exacte plutot qu'un envoi fragmente - evite le probleme rencontre cote
     * Windows (Invoke-WebRequest y envoyait parfois un encodage que les URL S3 signees
     * n'acceptent pas, provoquant un blocage silencieux ; corrige la-bas avec WebClient, qui
     * envoie lui aussi un Content-Length exact - meme principe applique ici des le depart).
     */
    private fun uploaderVersUrlPresignee(urlPresignee: String, octets: ByteArray) {
        val connexion = URL(urlPresignee).openConnection() as HttpURLConnection
        try {
            connexion.requestMethod = "PUT"
            connexion.doOutput = true
            connexion.setRequestProperty("Content-Type", "application/octet-stream")
            connexion.setFixedLengthStreamingMode(octets.size)
            connexion.connectTimeout = 30000
            connexion.readTimeout = 60000
            connexion.outputStream.use { it.write(octets) }
            val codeStatut = connexion.responseCode
            if (codeStatut !in 200..299) {
                throw ErreurApi("echec de l'envoi du fichier vers l'URL presignee (HTTP $codeStatut)")
            }
        } finally {
            connexion.disconnect()
        }
    }

    private fun attendreTache(idTache: String, cleApi: String, libelle: String, ecouteur: EcouteurAvancement?): JSONObject {
        val debut = System.currentTimeMillis()
        while (true) {
            if (System.currentTimeMillis() - debut > TIMEOUT_TACHE_MS) {
                throw ErreurApi("$libelle : pas de reponse apres ${TIMEOUT_TACHE_MS / 60000} min")
            }
            val tache = requeteJson("GET", "/tasks/$idTache", cleApi)
            val statutBrut = tache.optString("status", "")
            val progres = tache.optInt("progress", 0)
            // Correspondance large et insensible a la casse : le nom exact des statuts Tripo n'a
            // jamais ete confirme avec certitude (contrairement a Meshy) - on couvre plusieurs
            // formulations plausibles plutot que d'attendre un seul mot precis qui pourrait ne
            // jamais arriver.
            when {
                statutBrut.matches(Regex("(?i)^(success|succeeded|completed|done|finished)$")) -> return tache
                statutBrut.matches(Regex("(?i)^(failed|failure|error)$")) ->
                    throw ErreurApi("$libelle a echoue : ${tache.optString("error_message", "raison inconnue")}")
                statutBrut.matches(Regex("(?i)^(banned|blocked|rejected)$")) ->
                    throw ErreurApi("$libelle refusee (contenu signale par Tripo)")
                statutBrut.matches(Regex("(?i)^(cancelled|canceled)$")) ->
                    throw ErreurApi("$libelle a ete annulee")
                else -> ecouteur?.surProgres(libelle, statutBrut, progres)
            }
            Thread.sleep(INTERVALLE_POLL_MS)
        }
    }

    /**
     * Pipeline complet : reservation d'upload -> envoi du fichier -> texturation -> conversion en
     * 3MF colore (couleur par sommet). Synchrone (bloquant) - a appeler depuis un thread
     * d'arriere-plan, jamais depuis le thread principal de l'interface.
     */
    fun coloriser(
        octets: ByteArray,
        extension: String,
        prompt: String,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null
    ): ResultatColorisation {
        // --- Etape 1 : reserver une URL d'upload ---
        val corpsPresign = JSONObject().put("format", extension.lowercase())
        val reponsePresign = requeteJson("POST", "/files/presign", cleApi, corpsPresign)
        // "upload_url" est accepte comme alias de "presigned_url" selon la doc trouvee.
        val urlPresignee = reponsePresign.optString("presigned_url").ifEmpty { reponsePresign.optString("upload_url") }
        val jetonFichier = reponsePresign.optString("file_token")
        if (urlPresignee.isEmpty()) {
            throw ErreurApi("reponse de reservation d'upload sans URL exploitable - reponse brute recue : $reponsePresign")
        }

        // --- Etape 2 : uploader le fichier brut sur cette URL ---
        uploaderVersUrlPresignee(urlPresignee, octets)

        // --- Etape 3 : texturation ---
        val corpsTexture = JSONObject().put("input", jetonFichier).put("prompt", prompt)
        val reponseTexture = requeteJson("POST", "/models/texture", cleApi, corpsTexture)
        val idTexture = reponseTexture.getString("task_id")

        attendreTache(idTexture, cleApi, "Texturation", ecouteur)

        // --- Etape 4 : conversion en 3MF colore ---
        val corpsConvert = JSONObject()
            .put("input", idTexture)
            .put("format", "3MF")
            .put("export_vertex_colors", true)
        val reponseConvert = requeteJson("POST", "/models/convert", cleApi, corpsConvert)
        val idConvert = reponseConvert.getString("task_id")

        val tacheConvert = attendreTache(idConvert, cleApi, "Conversion 3MF", ecouteur)

        // Le nom exact du champ de sortie est une deduction par analogie avec les autres
        // endpoints Tripo documentes - jamais confirme en conditions reelles (la conversion n'a
        // encore jamais abouti jusqu'au bout lors des tests).
        val sortie = tacheConvert.optJSONObject("output")
        val urlSortie = sortie?.optString("model") ?: tacheConvert.optString("model")
        if (urlSortie.isNullOrEmpty()) {
            throw ErreurApi("reponse de conversion sans URL de modele exploitable - reponse brute recue : $tacheConvert")
        }

        // Tripo facture par operation ; le total exact par fichier n'est pas extrait ici faute
        // d'avoir confirme ou il se trouve dans la reponse - meme choix que cote Windows.
        return ResultatColorisation(urlSortie, 0)
    }

    /** Telecharge un fichier distant (le .3mf final) en octets bruts. */
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
