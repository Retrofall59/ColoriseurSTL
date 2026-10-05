package com.tomyn.coloriseurstl

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

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
}
