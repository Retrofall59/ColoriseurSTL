package com.tomyn.coloriseurstl

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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
    private const val CLE_PROMPT_PERSONNALISE = "dernier_prompt_personnalise"
    private const val CLE_NB_COULEURS = "nb_couleurs"
    private const val CLE_DOSSIER_SORTIE = "dossier_sortie_uri"

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

    fun lireDernierPromptPersonnalise(context: Context): String =
        prefs(context).getString(CLE_PROMPT_PERSONNALISE, "") ?: ""

    fun ecrireDernierPromptPersonnalise(context: Context, texte: String) {
        prefs(context).edit().putString(CLE_PROMPT_PERSONNALISE, texte).apply()
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
}
