package com.tomyn.coloriseurstl

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Contrairement aux lecteurs RFID (aucun secret a proteger), cette appli stocke une vraie cle
 * API - chiffree via EncryptedSharedPreferences (cle maitresse geree par le Keystore Android),
 * equivalent mobile du cle_api.enc chiffre avec le compte Windows sur la version PowerShell.
 */
object GestionnaireParametres {

    private const val FICHIER = "coloriseurstl_parametres_chiffre"
    private const val CLE_API_MESHY = "cle_api_meshy"
    private const val CLE_API_TRIPO = "cle_api_tripo"
    private const val CLE_FOURNISSEUR = "fournisseur_choisi"
    private const val CLE_PROMPT_PERSONNALISE_PREFIXE = "dernier_prompt_personnalise_"
    private const val CLE_CATEGORIE_PROMPT = "derniere_categorie_prompt"
    private const val CLE_NB_COULEURS = "nb_couleurs"
    private const val CLE_DOSSIER_SORTIE = "dossier_sortie_uri"
    private const val CLE_MESSAGE_BATTERIE_VU = "message_batterie_vu"
    private const val CLE_WIFI_UNIQUEMENT = "wifi_uniquement"

    private fun prefs(context: Context): SharedPreferences {
        val cleMaitresse = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context, FICHIER, cleMaitresse,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun lireCleApi(context: Context): String = prefs(context).getString(CLE_API_MESHY, "") ?: ""

    fun ecrireCleApi(context: Context, cle: String) {
        prefs(context).edit().putString(CLE_API_MESHY, cle).apply()
    }

    // --- Tripo : fournisseur de secours, optionnel independamment de Meshy - voir MainActivity
    // pour la logique "au moins une des deux cles est obligatoire, peu importe laquelle". ---
    fun lireCleApiTripo(context: Context): String = prefs(context).getString(CLE_API_TRIPO, "") ?: ""

    fun ecrireCleApiTripo(context: Context, cle: String) {
        prefs(context).edit().putString(CLE_API_TRIPO, cle).apply()
    }

    fun lireFournisseurChoisi(context: Context): String = prefs(context).getString(CLE_FOURNISSEUR, "") ?: ""

    fun ecrireFournisseurChoisi(context: Context, fournisseur: String) {
        prefs(context).edit().putString(CLE_FOURNISSEUR, fournisseur).apply()
    }

    /** Slug simple pour deriver une cle de preference stable a partir d'un nom de categorie. */
    private fun slugCategorie(categorie: String): String =
        categorie.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')

    // Memoire du dernier texte libre ("Autre") saisi, separee par categorie - evite de melanger
    // par exemple le texte libre tape pour un personnage avec celui tape pour une piece
    // mecanique. Equivalent du fichier "dernier_prompt_<categorie>.txt" cote Windows.
    fun lireDernierPromptPersonnalise(context: Context, categorie: String): String =
        prefs(context).getString(CLE_PROMPT_PERSONNALISE_PREFIXE + slugCategorie(categorie), "") ?: ""

    fun ecrireDernierPromptPersonnalise(context: Context, categorie: String, texte: String) {
        prefs(context).edit().putString(CLE_PROMPT_PERSONNALISE_PREFIXE + slugCategorie(categorie), texte).apply()
    }

    /** Derniere categorie de prompt selectionnee, pour rouvrir l'appli sur le meme menu. */
    fun lireDerniereCategoriePrompt(context: Context): String? = prefs(context).getString(CLE_CATEGORIE_PROMPT, null)

    fun ecrireDerniereCategoriePrompt(context: Context, categorie: String) {
        prefs(context).edit().putString(CLE_CATEGORIE_PROMPT, categorie).apply()
    }

    fun lireNbCouleurs(context: Context): Int = prefs(context).getInt(CLE_NB_COULEURS, 4)

    fun ecrireNbCouleurs(context: Context, valeur: Int) {
        prefs(context).edit().putInt(CLE_NB_COULEURS, valeur).apply()
    }

    fun lireDossierSortieUri(context: Context): String? = prefs(context).getString(CLE_DOSSIER_SORTIE, null)

    fun ecrireDossierSortieUri(context: Context, uri: String) {
        prefs(context).edit().putString(CLE_DOSSIER_SORTIE, uri).apply()
    }

    // --- Historique des lots : stockage simple, non chiffre (rien de sensible dedans),
    // dans l'espace prive de l'appli (pas besoin de Storage Access Framework pour ca). ---

    data class EntreeHistorique(val date: String, val fichiers: Int, val reussites: Int, val echecs: Int, val credits: Int)

    private fun fichierHistorique(context: Context) = File(context.filesDir, "historique_lots.csv")

    fun ajouterHistoriqueLot(context: Context, fichiers: Int, reussites: Int, echecs: Int, credits: Int) {
        val date = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.FRANCE).format(Date())
        val ligne = "$date;$fichiers;$reussites;$echecs;$credits\n"
        try { fichierHistorique(context).appendText(ligne) } catch (e: Exception) { }
    }

    fun lireHistoriqueLots(context: Context): List<EntreeHistorique> {
        val fichier = fichierHistorique(context)
        if (!fichier.exists()) return emptyList()
        return try {
            fichier.readLines().mapNotNull { ligne ->
                val champs = ligne.split(";")
                if (champs.size >= 5) {
                    EntreeHistorique(champs[0], champs[1].toIntOrNull() ?: 0, champs[2].toIntOrNull() ?: 0, champs[3].toIntOrNull() ?: 0, champs[4].toIntOrNull() ?: 0)
                } else null
            }
        } catch (e: Exception) { emptyList() }
    }

    fun viderHistoriqueLots(context: Context) {
        try { fichierHistorique(context).delete() } catch (e: Exception) { }
    }

    fun messageBatterieDejaVu(context: Context): Boolean = prefs(context).getBoolean(CLE_MESSAGE_BATTERIE_VU, false)

    fun marquerMessageBatterieVu(context: Context) {
        prefs(context).edit().putBoolean(CLE_MESSAGE_BATTERIE_VU, true).apply()
    }

    fun lireWifiUniquement(context: Context): Boolean = prefs(context).getBoolean(CLE_WIFI_UNIQUEMENT, false)

    fun ecrireWifiUniquement(context: Context, valeur: Boolean) {
        prefs(context).edit().putBoolean(CLE_WIFI_UNIQUEMENT, valeur).apply()
    }

    // --- Persistance du dernier lot (ajoute le 10/10/2026, bug remonte par Tomyn) : EtatTraitement
    // garde les resultats/echecs uniquement en memoire (objet singleton), ce qui suffit pour une
    // simple rotation d'ecran mais pas pour un vrai kill de processus par Android - ce qui arrive
    // typiquement en ouvrant un visualiseur STL externe depuis un resultat (appli mise en arriere
    // plan, memoire reclamee, surtout avec plusieurs Bitmap d'apercu en memoire). Ecrit ici au fil
    // de l'eau par ColorisationService (un resultat/echec a la fois, pas juste en fin de lot - un
    // kill en plein milieu du lot ne doit pas perdre ce qui est deja fait), et relu par
    // MainActivity.onCreate quand EtatTraitement redemarre a vide. Stockage non chiffre (aucun
    // secret ici, juste des Uri/noms de fichiers deja visibles a l'ecran) dans l'espace prive de
    // l'appli (filesDir, pas cacheDir - cacheDir peut etre vide par le systeme a tout moment, ce
    // qui irait justement a l'encontre du but recherche).
    private fun fichierResultatsPersistes(context: Context) = File(context.filesDir, "dernier_lot_resultats.jsonl")
    private fun fichierEchecsPersistes(context: Context) = File(context.filesDir, "dernier_lot_echecs.jsonl")
    private fun dossierApercusPersistes(context: Context) = File(context.filesDir, "dernier_lot_apercus")

    fun ajouterResultatPersiste(context: Context, resultat: EtatTraitement.ResultatColorise) {
        try {
            var nomApercu = ""
            if (resultat.apercu != null) {
                val dossier = dossierApercusPersistes(context).apply { mkdirs() }
                nomApercu = "apercu_${System.nanoTime()}.png"
                File(dossier, nomApercu).outputStream().use { flux ->
                    resultat.apercu.compress(Bitmap.CompressFormat.PNG, 90, flux)
                }
            }
            val json = JSONObject().apply {
                put("uri", resultat.uri.toString())
                put("nom", resultat.nom)
                put("fournisseur", resultat.fournisseur)
                put("apercu", nomApercu)
            }
            fichierResultatsPersistes(context).appendText(json.toString() + "\n")
        } catch (e: Exception) {
            // La persistance n'est qu'un filet de securite contre un kill de processus - jamais
            // bloquant pour le traitement lui-meme si l'ecriture echoue pour une raison ou une autre.
        }
    }

    fun ajouterEchecPersiste(context: Context, echec: EtatTraitement.FichierEchec) {
        try {
            val json = JSONObject().apply {
                put("uri", echec.uri.toString())
                put("nom", echec.nom)
                put("raison", echec.raison)
            }
            fichierEchecsPersistes(context).appendText(json.toString() + "\n")
        } catch (e: Exception) { }
    }

    fun chargerResultatsPersistes(context: Context): List<EtatTraitement.ResultatColorise> {
        val fichier = fichierResultatsPersistes(context)
        if (!fichier.exists()) return emptyList()
        return try {
            fichier.readLines().mapNotNull { ligne ->
                if (ligne.isBlank()) return@mapNotNull null
                val json = JSONObject(ligne)
                val nomApercu = json.optString("apercu", "")
                val apercu = if (nomApercu.isNotEmpty()) {
                    try { BitmapFactory.decodeFile(File(dossierApercusPersistes(context), nomApercu).absolutePath) } catch (e: Exception) { null }
                } else null
                EtatTraitement.ResultatColorise(Uri.parse(json.getString("uri")), json.getString("nom"), apercu, json.optString("fournisseur", ""))
            }
        } catch (e: Exception) { emptyList() }
    }

    fun chargerEchecsPersistes(context: Context): List<EtatTraitement.FichierEchec> {
        val fichier = fichierEchecsPersistes(context)
        if (!fichier.exists()) return emptyList()
        return try {
            fichier.readLines().mapNotNull { ligne ->
                if (ligne.isBlank()) return@mapNotNull null
                val json = JSONObject(ligne)
                EtatTraitement.FichierEchec(Uri.parse(json.getString("uri")), json.getString("nom"), json.optString("raison", "raison inconnue"))
            }
        } catch (e: Exception) { emptyList() }
    }

    fun viderResultatsLotPersistes(context: Context) {
        try {
            fichierResultatsPersistes(context).delete()
            fichierEchecsPersistes(context).delete()
            dossierApercusPersistes(context).deleteRecursively()
        } catch (e: Exception) { }
    }
}
