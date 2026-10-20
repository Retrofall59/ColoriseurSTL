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
    // 20/10/2026, porte depuis la version Windows (commit 5ae2cc4, deja confirme sur ce
    // changelog Meshy) : l'endpoint /balance renvoie en realite deux soldes separes
    // (monthly_credits = quota mensuel qui se reinitialise, permanent_credits = credits achetes
    // qui ne se reinitialisent jamais) plutot qu'un seul chiffre - "solde" reste le TOTAL des
    // deux (compatibilite avec le seul appelant existant, la verification avant lancement dans
    // MainActivity), monthlyCredits/permanentCredits/monthlyResetsAt donnent le detail.
    data class VerificationCle(
        val statut: StatutCle,
        val solde: Int?,
        val monthlyCredits: Int? = null,
        val permanentCredits: Int? = null,
        val monthlyResetsAt: String? = null
    )

    /**
     * Verifie la cle ET recupere le solde en un seul appel (meme endpoint /balance) :
     *   VALIDE   -> solde contient le vrai solde
     *   INVALIDE -> cle refusee par Meshy (HTTP 401/403), bloquant
     *   INCONNU  -> echec pour une autre raison (reseau, timeout...), pas bloquant en soi
     */
    fun verifierCleEtSolde(cleApi: String): VerificationCle {
        return try {
            val reponse = requete("GET", "/balance", cleApi)
            val mensuel = if (reponse.has("monthly_credits")) reponse.optInt("monthly_credits", 0) else null
            val permanent = if (reponse.has("permanent_credits")) reponse.optInt("permanent_credits", 0) else null
            val soldeTotal = if (mensuel != null || permanent != null) {
                (mensuel ?: 0) + (permanent ?: 0)
            } else {
                reponse.optInt("balance", 0)
            }
            VerificationCle(
                StatutCle.VALIDE, soldeTotal, mensuel, permanent,
                reponse.optString("monthly_resets_at", "").ifEmpty { null }
            )
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

    // 20/10/2026, porte depuis la version Windows (Tomyn : "VASY" puis "OK pour moi" sur
    // l'Analyze gratuite) : diagnostic d'imprimabilite de Meshy (parois trop fines, etancheite,
    // trous, faces degenerees). "print/analyze" est gratuit (0 credit, documente "This endpoint
    // is free") et NE MODIFIE RIEN au maillage - sert de filtre avant de payer "print/repair"
    // (+10 credits, voir reparerImprimabilite) : pas la peine de reparer une piece saine.
    data class DiagnosticImprimabilite(val tache: JSONObject, val parosTropFines: Boolean)

    fun analyserImprimabilite(
        idTacheSource: String,
        cleApi: String,
        typeImprimante: String = "fdm",
        tailleImpressionMm: Int? = null,
        ecouteur: EcouteurAvancement? = null
    ): DiagnosticImprimabilite {
        val corps = JSONObject().put("input_task_id", idTacheSource).put("printer_type", typeImprimante)
        // "intended_print_longest_side_mm" (1-1000 mm documente) - seulement si renseigne,
        // sinon Meshy applique son propre defaut (150 mm pour une tache chainee).
        if (tailleImpressionMm != null && tailleImpressionMm > 0) {
            corps.put("intended_print_longest_side_mm", tailleImpressionMm)
        }
        val reponse = requete("POST", "/print/analyze", cleApi, corps)
        val idAnalyse = reponse.getString("result")
        val tache = attendreTache("/print/analyze/$idAnalyse", cleApi, "Analyse imprimabilite", ecouteur)
        val diag = tache.optJSONObject("printability")
        val tropFines = diag?.optJSONObject("thin_walls")?.optBoolean("has_thin_walls", false) ?: false
        return DiagnosticImprimabilite(tache, tropFines)
    }

    data class ResultatReparationImprimabilite(val idTache: String, val creditsConsommes: Int)

    /**
     * "Repair Printability" de Meshy (porte depuis la version Windows, +10 credits) : epaissit
     * automatiquement les parois plus fines que le minimum imprimable (FDM = 1.0 mm, documente),
     * AVANT la Retexture - la texture existante est supprimee par cette reparation, d'ou le besoin
     * de la lancer sur le maillage NU puis retexturer le resultat juste apres, jamais apres coup.
     * Chaine par input_task_id (meme principe que genererMaillageDepuisImage) : idTacheSource doit
     * etre une tache Meshy existante possedant un asset .glb, pas un nouvel upload.
     */
    fun reparerImprimabilite(
        idTacheSource: String,
        cleApi: String,
        typeImprimante: String = "fdm",
        tailleImpressionMm: Int? = null,
        ecouteur: EcouteurAvancement? = null
    ): ResultatReparationImprimabilite {
        val corps = JSONObject().put("input_task_id", idTacheSource).put("printer_type", typeImprimante)
        if (tailleImpressionMm != null && tailleImpressionMm > 0) {
            corps.put("intended_print_longest_side_mm", tailleImpressionMm)
        }
        val reponse = requete("POST", "/print/repair", cleApi, corps)
        val idReparation = reponse.getString("result")
        val tache = attendreTache("/print/repair/$idReparation", cleApi, "Reparation imprimabilite", ecouteur)
        return ResultatReparationImprimabilite(tache.getString("id"), tache.optInt("consumed_credits", 0))
    }

    /**
     * Orchestre Analyze (gratuit) puis Repair (10 credits, seulement si necessaire) - c'est cette
     * fonction qu'appelle le pipeline de colorisation, plus reparerImprimabilite directement.
     * Retourne null si aucune reparation n'a ete necessaire (l'appelant garde alors la tache
     * source d'origine comme point de depart pour la Retexture).
     */
    fun reparerParoisSiNecessaire(
        idTacheSource: String,
        cleApi: String,
        typeImprimante: String = "fdm",
        tailleImpressionMm: Int? = null,
        ecouteur: EcouteurAvancement? = null
    ): ResultatReparationImprimabilite? {
        val diagnostic = analyserImprimabilite(idTacheSource, cleApi, typeImprimante, tailleImpressionMm, ecouteur)
        if (!diagnostic.parosTropFines) return null
        // Meme taille d'impression passee a la Reparation qu'a l'Analyse qui l'a decidee - sinon
        // le seuil utilise par Repair ne correspondrait pas a celui qui a determine qu'elle etait necessaire.
        return reparerImprimabilite(idTacheSource, cleApi, typeImprimante, tailleImpressionMm, ecouteur)
    }

    data class ResultatImage3D(val idTache: String, val creditsConsommes: Int)

    /**
     * Image -> STL (ajoute le 08/10/2026, idee de Tomyn, portee depuis la version Windows deja
     * confirmee fonctionnelle en conditions reelles) : "Image to 3D" de Meshy, maillage SEUL
     * (should_texture=false) - la texture est refaite juste apres par la Retexture habituelle
     * avec le prompt choisi par l'utilisateur, pas celle (generique) que ferait Image to 3D
     * elle-meme. Payer la texturation deux fois (une ici, une a la Retexture) n'aurait aucun sens.
     * Le task_id retourne s'utilise directement comme input_task_id de la Retexture (voir
     * coloriser/coloriserObjExperimental ci-dessous), sans jamais telecharger de fichier
     * intermediaire.
     */
    fun genererMaillageDepuisImage(
        octetsImage: ByteArray,
        extensionFichier: String,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null,
        targetPolycount: Int = 30000,
        smartTopology: Boolean = false,
        geometryResolution: String = ""
    ): ResultatImage3D {
        // 20/10/2026 : .webp (porte depuis la version Windows, deja confirme dans le changelog
        // Meshy du 10/10/2026 comme format d'entree accepte) - manquait ici, seuls jpg/jpeg/png
        // etaient reconnus, un .webp partait donc etiquete "image/png" a tort.
        val mime = when (extensionFichier.lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "webp" -> "image/webp"
            else -> "image/png"
        }
        val dataUri = "data:$mime;base64," + Base64.encodeToString(octetsImage, Base64.NO_WRAP)

        // 20/10/2026 : "should_remesh"/"target_polycount" (porte depuis la version Windows,
        // reglage de base deja confirme sur ce changelog - Meshy ignore "target_polycount" sans
        // "should_remesh=true" explicite, d'ou le maillage brut et clairseme obtenu jusqu'ici
        // sans ce parametre). Pas encore de reglage utilisateur equivalent cote Android (pas de
        // selecteur "Triangles vises" dans l'interface) - valeur fixe pour l'instant, identique
        // au defaut Windows (30000), a exposer dans l'interface dans une passe ulterieure.
        val corps = JSONObject()
            .put("image_url", dataUri)
            .put("should_texture", false)
            .put("should_remesh", true)
            .put("target_polycount", targetPolycount)

        // 20/10/2026 : Smart Topology (meshy-t2.5) et geometry_resolution (2k/4k) - portes depuis
        // la version Windows, meme logique (Smart Topology plafonne a 30000 triangles max, voir
        // le commentaire equivalent cote Windows). Pas de case/menu cote Android pour l'instant
        // (parametres par defaut desactives, $false/"") - l'appel les accepte deja pour que la
        // future UI n'ait qu'a les brancher, sans toucher a nouveau a ce fichier.
        if (smartTopology) {
            val cible = if (targetPolycount > 30000) 30000 else targetPolycount
            corps.put("target_polycount", cible)
            corps.put("model_type", "smart-topology")
            corps.put("ai_model", "meshy-t2.5")
        }
        // CORRECTIF du 20/10/2026 : trouve en usage reel sur un vrai telephone (erreur HTTP 400
        // recue : "geometry_resolution '4k' requires ai_model 'meshy-7.1'") - l'hypothese de
        // depart ("l'API defaut silencieusement sur meshy-7.1 si on ne precise rien") etait
        // fausse, meme erreur corrigee cote Windows en parallele.
        // CORRECTIF du 21/10/2026 : trouve en usage reel (Tomyn avait coche Smart Topology ET une
        // resolution 4k en meme temps - meme erreur HTTP 400, car Smart Topology exige
        // ai_model "meshy-t2.5" alors que geometry_resolution exige ai_model "meshy-7.1" : les deux
        // sont INCOMPATIBLES, confirme sur la documentation officielle Meshy. Smart Topology est
        // prioritaire ici (deja actif juste au-dessus) - geometry_resolution est simplement ignore
        // dans ce cas plutot que d'envoyer une requete vouee a l'echec (le journal d'appel previent
        // deja Tomyn de ce choix, voir ColorisationService).
        if (!smartTopology && (geometryResolution == "2k" || geometryResolution == "4k")) {
            corps.put("geometry_resolution", geometryResolution)
            corps.put("ai_model", "meshy-7.1")
        }

        val reponse = requete("POST", "/image-to-3d", cleApi, corps)
        val idTache = reponse.getString("result")

        val tache = attendreTache("/image-to-3d/$idTache", cleApi, "Image to 3D", ecouteur)
        return ResultatImage3D(idTache, tache.optInt("consumed_credits", 0))
    }

    data class ResultatRemesh(val idTache: String, val creditsConsommes: Int)

    /**
     * Simplifie un .stl/.obj trop lourd via l'API Remesh de Meshy, AVANT la Retexture (porte
     * depuis la version Windows, 15/10/2026 - voir CompteurTriangles et le seuil
     * SEUIL_TRIANGLES_REMESH_AUTO dans ColorisationService) : evite d'envoyer un maillage
     * inutilement lourd a la Retexture. Le task_id retourne s'utilise directement comme
     * input_task_id de la Retexture, meme principe que genererMaillageDepuisImage ci-dessus.
     * "glb" ajoute a cote de "stl" dans target_formats - necessaire si la reparation des parois
     * (reparerParoisSiNecessaire) est activee juste apres, qui exige que la tache source possede
     * un asset .glb.
     */
    fun remesher(
        octetsStl: ByteArray,
        cleApi: String,
        targetPolycount: Int = 30000,
        ecouteur: EcouteurAvancement? = null
    ): ResultatRemesh {
        val dataUri = "data:application/octet-stream;base64," + Base64.encodeToString(octetsStl, Base64.NO_WRAP)
        val formats = org.json.JSONArray().put("stl").put("glb")
        val corps = JSONObject()
            .put("model_url", dataUri)
            .put("target_polycount", targetPolycount)
            .put("target_formats", formats)
        val reponse = requete("POST", "/remesh", cleApi, corps)
        val idTache = reponse.getString("result")
        val tache = attendreTache("/remesh/$idTache", cleApi, "Remesh", ecouteur)
        return ResultatRemesh(idTache, tache.optInt("consumed_credits", 0))
    }

    /**
     * Lance la texturation (etape 1) puis la reduction en couleurs imprimables (etape 2), de
     * maniere synchrone (bloquante) - a appeler depuis un thread d'arriere-plan, jamais depuis
     * le thread principal de l'interface.
     *
     * @param octetsStl ignore si idTacheSource est fourni (source = image deja transformee en
     *   maillage par genererMaillageDepuisImage, voir ci-dessus) - sinon le modele 3D a coloriser.
     * @param idTacheSource task_id Meshy a reutiliser comme source (ex: resultat d'Image to 3D),
     *   ou null pour coloriser directement octetsStl.
     * @return l'URL de telechargement du fichier .3mf final, et l'URL d'apercu fourni par Meshy
     */
    fun coloriser(
        octetsStl: ByteArray?,
        idTacheSource: String?,
        prompt: String,
        maxCouleurs: Int,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null,
        textureResolution: String = ""
    ): ResultatColorisation {
        val corpsRetexture = JSONObject()
            .put("text_style_prompt", prompt)
            .put("enable_original_uv", false)
        if (idTacheSource != null) {
            corpsRetexture.put("input_task_id", idTacheSource)
        } else {
            val dataUri = "data:application/octet-stream;base64," + Base64.encodeToString(octetsStl!!, Base64.NO_WRAP)
            corpsRetexture.put("model_url", dataUri)
        }
        // 20/10/2026 : "texture_resolution" (2k/4k/8k) - porte depuis la version Windows
        // (troisieme relecture du changelog Meshy), parametre de l'API Retexture elle-meme,
        // distinct de "geometry_resolution" ci-dessus (qui ne concerne que Image to 3D). Vide par
        // defaut = on ne precise rien, Meshy applique son propre defaut ("2k").
        if (textureResolution == "4k" || textureResolution == "8k") {
            corpsRetexture.put("texture_resolution", textureResolution)
        }
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

    data class ResultatColorisationObj(
        val urlObj: String,
        val urlMtl: String?,
        val urlTexture: String?,
        val urlApercu: String,
        val creditsConsommes: Int
    )

    /**
     * Variante experimentale (ajoutee le 07/10/2026, portee depuis la version Windows deja
     * confirmee fonctionnelle en conditions reelles) : s'arrete apres l'etape Retexture, sans
     * passer par Multi-Color Print - recupere directement le .obj texture (UV/PBR) + son .mtl +
     * son image de texture depuis "model_urls"/"texture_urls" de la reponse Retexture, plutot que
     * la palette a N couleurs fixe de Multi-Color Print. Une seule etape facturee : moins cher
     * (confirme a l'usage : ~40 credits au lieu de ~56), et Bambu Studio propose quand meme sa
     * boite de dialogue de correspondance automatique des couleurs a l'ouverture d'un .obj,
     * exactement comme pour l'export Tripo.
     */
    fun coloriserObjExperimental(
        octetsStl: ByteArray?,
        idTacheSource: String?,
        prompt: String,
        cleApi: String,
        ecouteur: EcouteurAvancement? = null,
        textureResolution: String = ""
    ): ResultatColorisationObj {
        val corpsRetexture = JSONObject()
            .put("text_style_prompt", prompt)
            .put("enable_original_uv", false)
        if (idTacheSource != null) {
            corpsRetexture.put("input_task_id", idTacheSource)
        } else {
            val dataUri = "data:application/octet-stream;base64," + Base64.encodeToString(octetsStl!!, Base64.NO_WRAP)
            corpsRetexture.put("model_url", dataUri)
        }
        if (textureResolution == "4k" || textureResolution == "8k") {
            corpsRetexture.put("texture_resolution", textureResolution)
        }
        val reponseRetexture = requete("POST", "/retexture", cleApi, corpsRetexture)
        val idRetexture = reponseRetexture.getString("result")

        val tacheRetexture = attendreTache("/retexture/$idRetexture", cleApi, "Retexture", ecouteur)
        val creditsRetexture = tacheRetexture.optInt("consumed_credits", 0)
        val urlApercu = tacheRetexture.optString("thumbnail_url", "")

        val urlsModele = tacheRetexture.optJSONObject("model_urls")
        val urlObj = urlsModele?.optString("obj", "") ?: ""
        if (urlObj.isEmpty()) {
            throw ErreurApi("reponse Retexture sans URL .obj exploitable - reponse brute recue : $tacheRetexture")
        }
        val urlMtl = urlsModele?.optString("mtl", "")?.ifEmpty { null }
        val urlsTexture = tacheRetexture.optJSONArray("texture_urls")
        val urlTexture = if (urlsTexture != null && urlsTexture.length() > 0) {
            urlsTexture.getJSONObject(0).optString("base_color", "").ifEmpty { null }
        } else null

        return ResultatColorisationObj(urlObj, urlMtl, urlTexture, urlApercu, creditsRetexture)
    }

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
