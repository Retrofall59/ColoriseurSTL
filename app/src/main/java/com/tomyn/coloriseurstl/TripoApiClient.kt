package com.tomyn.coloriseurstl

import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Appels a l'API Tripo (presignation d'upload, texturation, conversion en OBJ colore par
 * sommet), portage fidele du pipeline PowerShell (Windows) - endpoints et logique valides en
 * conditions reelles : reservation d'upload, envoi du fichier, import, texturation et conversion
 * tous confirmes fonctionnels avec de vraies cles/credits.
 *
 * Base documentee par le SDK Go officiel de VAST-AI-Research (societe editrice de Tripo) :
 *   https://pkg.go.dev/github.com/VAST-AI-Research/tripo-go-sdk
 *
 * Difference de fond avec Meshy a connaitre : Tripo encode la couleur par sommet du maillage
 * (degrade continu), pas une palette figee a N couleurs - pas de parametre "nombre de couleurs"
 * equivalent a maxCouleurs cote Tripo.
 *
 * Format de sortie OBJ (pas 3MF) depuis le 07/10/2026 : "export_vertex_colors" n'est documente
 * comme valide par Tripo que pour les formats OBJ et GLTF - demande avec 3MF, le 3MF obtenu
 * avait une palette ajoutee mais jamais appliquee a la geometrie (aucune texture visible). L'OBJ
 * est livre en ZIP (maillage + .mtl + textures) a extraire cote appelant.
 */
object TripoApiClient {

    private const val BASE_URL = "https://openapi.tripo3d.ai/v3"
    private const val INTERVALLE_POLL_MS = 1000L
    private const val TIMEOUT_TACHE_MS = 20 * 60 * 1000L

    class ErreurApi(message: String) : Exception(message)

    interface EcouteurAvancement {
        fun surProgres(etape: String, statutBrut: String, progres: Int)
    }

    data class ResultatColorisation(val urlZipObj: String, val creditsConsommes: Int)

    // 20/10/2026, porte depuis la version Windows : endpoint de solde confirme reel
    // (/account/balance), contrairement a "/user/balance" devine au depart cote Windows (jamais
    // existant, trouve et corrige lors d'une relecture du changelog) - jamais implemente du tout
    // cote Android jusqu'ici.
    enum class StatutCle { VALIDE, INVALIDE, INCONNU }
    data class VerificationCle(val statut: StatutCle, val solde: Double?)

    fun verifierCleEtSolde(cleApi: String): VerificationCle {
        return try {
            val reponse = requeteJson("GET", "/account/balance", cleApi)
            VerificationCle(StatutCle.VALIDE, reponse.optDouble("balance", 0.0))
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

    data class ResultatImageModel(val idTache: String, val creditsConsommes: Double)

    /**
     * Image -> modele 3D (porte depuis la version Windows, "oui mais pour l'image ca sera bien
     * d'avoir tripo aussi" - Tripo refusait les images jusqu'ici). "model" obligatoire depuis un
     * changement reel cote API, trouve en usage reel par Tomyn (erreur recue : "model is
     * required, allowed values: P1-20260311, P2-20260801, v2.5-20250123, v3.0-20250812,
     * v3.1-20260211") malgre la doc qui le presentait comme facultatif avec un defaut - on
     * l'envoie donc explicitement, meme correctif que cote Windows.
     *
     * @param avecTexture true = genere avec texturation integree (utilise quand il n'y a pas de
     *   prompt texte - pas d'etape Texture separee ensuite) ; false = maillage seul, texture
     *   refaite juste apres par Retexture-equivalent... mais Tripo n'a pas de "Retexture" separe
     *   de la texturation depuis l'import, donc avecTexture=false sert seulement quand un prompt
     *   sera applique via l'etape Texture normale sur le resultat (voir coloriserDepuisImage).
     */
    fun genererModeleDepuisImage(
        jetonFichier: String,
        avecTexture: Boolean,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null
    ): ResultatImageModel {
        val corps = JSONObject()
            .put("input", jetonFichier)
            .put("model", "v3.1-20260211")
            .put("texture", avecTexture)
            .put("pbr", avecTexture)
        val reponse = requeteJson("POST", "/generation/image-to-model", cleApi, corps)
        val idTache = reponse.getString("task_id")
        val tache = attendreTache(idTache, cleApi, "Image to 3D", ecouteur)
        return ResultatImageModel(idTache, tache.optDouble("credits_consumed", 0.0))
    }

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

        // --- Etape 3 : import du modele uploade ---
        // Etape obligatoire decouverte a posteriori (absente des premieres versions) : la doc
        // officielle (docs.tripo3d.ai/model-generation/import-model.html) precise qu'un fichier
        // uploade doit d'abord passer par une tache "import_model" avant de pouvoir etre texture.
        // Confirme aussi par l'historique du tableau de bord Tripo : chaque texturation en echec
        // etait precedee d'une tache import_model en succes jamais reutilisee par le code avant
        // ce correctif.
        val corpsImport = JSONObject()
            .put("type", "import_model")
            .put("file", JSONObject().put("file_token", jetonFichier))
        val reponseImport = requeteJson("POST", "/models/import", cleApi, corpsImport)
        val idImport = reponseImport.getString("task_id")

        val tacheImport = attendreTache(idImport, cleApi, "Import", ecouteur)
        // Corrige le 07/10/2026 : contrairement a ce qui etait suppose ("l'import semble
        // gratuit"), Tomyn a confirme que cette etape coute 5 credits sur son tableau de bord -
        // jamais ajoutes au total renvoye jusqu'ici, qui sous-comptait donc le vrai cout.
        val creditsImport = tacheImport.optDouble("credits_consumed", 0.0)

        val (urlSortie, creditsTextureConvert) = texturerEtConvertir(idImport, prompt, cleApi, ecouteur)

        // Credits reellement consommes, sur les TROIS etapes facturees : import (confirme a 5
        // credits, corrige le 07/10/2026), texturation (confirmee a 10 credits) et conversion.
        val creditsTotal = (creditsImport + creditsTextureConvert).toInt()
        return ResultatColorisation(urlSortie, creditsTotal)
    }

    /**
     * Etapes 4-5 factorisees (texturation puis conversion en OBJ colore par sommet) - partagees
     * entre coloriser() (source = import d'un fichier uploade) et coloriserImage() (source =
     * resultat d'Image to 3D, voir plus bas), 20/10/2026.
     */
    private fun texturerEtConvertir(
        idModeleSource: String,
        prompt: String,
        cleApi: String,
        ecouteur: EcouteurAvancement?
    ): Pair<String, Double> {
        // --- Texturation (a partir du modele source) ---
        // Champs confirmes par la vraie doc officielle (platform.tripo3d.ai/docs/texture) : le
        // champ s'appelle "original_model_task_id", pas "input" comme envoye dans les premieres
        // versions - "input" etait silencieusement ignore par l'API, qui tournait alors sans
        // jamais avoir de vraie reference de modele, d'ou l'echec systematique observe en test
        // reel (meme sur un simple cube). Le prompt texte est imbrique dans "texture_prompt.text".
        val corpsTexture = JSONObject()
            .put("original_model_task_id", idModeleSource)
            .put("texture_prompt", JSONObject().put("text", prompt))
        val reponseTexture = requeteJson("POST", "/models/texture", cleApi, corpsTexture)
        val idTexture = reponseTexture.getString("task_id")

        val tacheTexture = attendreTache(idTexture, cleApi, "Texturation", ecouteur)
        val creditsTexture = tacheTexture.optDouble("credits_consumed", 0.0)

        // --- Conversion en OBJ colore par sommet (pas en 3MF) ---
        // Changement du 07/10/2026 : "export_vertex_colors" est documente par Tripo comme valide
        // UNIQUEMENT pour les formats OBJ et GLTF (developers.tripo3d.com/en/docs/models-convert)
        // - demande avec format=3MF comme avant, ce parametre etait silencieusement ignore, d'ou
        // les 3MF recus avec une palette de 4 couleurs ajoutee mais jamais appliquee a la
        // geometrie (confirme par Tomyn : aucune texture visible, meme dans un lecteur .3mf).
        // Bambu Studio sachant lire un OBJ colore par sommet et proposer ses couleurs dans l'AMS,
        // on demande directement ce format-la a la place - meme correctif que la version Windows.
        val (urlSortie, creditsConvert) = convertirEnObj(idTexture, cleApi, ecouteur)
        return Pair(urlSortie, creditsTexture + creditsConvert)
    }

    /** Conversion seule en OBJ colore par sommet - retourne (url, credits_consommes). */
    private fun convertirEnObj(idTache: String, cleApi: String, ecouteur: EcouteurAvancement?): Pair<String, Double> {
        val corpsConvert = JSONObject()
            .put("input", idTache)
            .put("format", "OBJ")
            .put("export_vertex_colors", true)
        val reponseConvert = requeteJson("POST", "/models/convert", cleApi, corpsConvert)
        val idConvert = reponseConvert.getString("task_id")

        val tacheConvert = attendreTache(idConvert, cleApi, "Conversion OBJ", ecouteur)
        val creditsConvert = tacheConvert.optDouble("credits_consumed", 0.0)

        // Confirme par une vraie reponse Tripo complete (premier succes de bout en bout cote
        // Windows) : le champ s'appelle "output.model_url", pas "output.model" comme devine au
        // depart. L'export OBJ est livre sous forme de ZIP (maillage + .mtl + textures), pas un
        // fichier unique - a extraire cote appelant (voir ColorisationService).
        val urlSortie = tacheConvert.optJSONObject("output")?.optString("model_url")
        if (urlSortie.isNullOrEmpty()) {
            throw ErreurApi("reponse de conversion sans URL de modele exploitable - reponse brute recue : $tacheConvert")
        }
        return Pair(urlSortie, creditsConvert)
    }

    /**
     * Image -> OBJ colore (porte depuis la version Windows, "oui mais pour l'image ca sera bien
     * d'avoir tripo aussi") : reservation d'upload -> envoi -> Image to 3D -> (texturation ->
     * conversion, seulement si un prompt texte est fourni - voir genererModeleDepuisImage) ->
     * conversion en OBJ colore par sommet. Sans prompt, Image to 3D texture directement (meme
     * principe que cote Windows : la texturation integree evite de la payer deux fois).
     */
    fun coloriserImage(
        octets: ByteArray,
        extension: String,
        prompt: String,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null
    ): ResultatColorisation {
        val corpsPresign = JSONObject().put("format", extension.lowercase())
        val reponsePresign = requeteJson("POST", "/files/presign", cleApi, corpsPresign)
        val urlPresignee = reponsePresign.optString("presigned_url").ifEmpty { reponsePresign.optString("upload_url") }
        val jetonFichier = reponsePresign.optString("file_token")
        if (urlPresignee.isEmpty()) {
            throw ErreurApi("reponse de reservation d'upload sans URL exploitable - reponse brute recue : $reponsePresign")
        }
        uploaderVersUrlPresignee(urlPresignee, octets)

        val avecPrompt = prompt.isNotBlank()
        val resultatImage = genererModeleDepuisImage(jetonFichier, !avecPrompt, cleApi, ecouteur)

        if (!avecPrompt) {
            // Deja texture par Image to 3D elle-meme (avecTexture=true) - juste la conversion.
            val (urlSortie, creditsConvert) = convertirEnObj(resultatImage.idTache, cleApi, ecouteur)
            val creditsTotal = (resultatImage.creditsConsommes + creditsConvert).toInt()
            return ResultatColorisation(urlSortie, creditsTotal)
        }

        val (urlSortie, creditsTextureConvert) = texturerEtConvertir(resultatImage.idTache, prompt, cleApi, ecouteur)
        val creditsTotal = (resultatImage.creditsConsommes + creditsTextureConvert).toInt()
        return ResultatColorisation(urlSortie, creditsTotal)
    }

    /** Telecharge un fichier distant (le ZIP de l'export OBJ, ou tout autre fichier) en octets bruts. */
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
