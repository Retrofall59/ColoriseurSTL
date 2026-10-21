package com.tomyn.coloriseurstl

import android.content.pm.PackageManager
import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.ImageButton
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SettingsActivity : AppCompatActivity() {

    // 21/10/2026, porte depuis la version Windows (Sauvegarder ma config.../Restaurer ma
    // config..., Obtenir-FichiersConfigConnus) - trouve en continuant la comparaison
    // Windows/Android (pas un bug, Tomyn a dit "go" pour la porter). Voir SauvegardeConfig.kt
    // pour le detail de ce qui est inclus (jamais les cles API).
    private val choixEmplacementSauvegarde = registerForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        if (uri == null) return@registerForActivityResult
        try {
            val octets = SauvegardeConfig.exporter(filesDir)
            contentResolver.openOutputStream(uri)?.use { it.write(octets) }
            Toast.makeText(this, "Config sauvegardée.", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(this, "Echec de la sauvegarde : ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private val choixFichierARestaurer = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@registerForActivityResult
        try {
            val octets = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (octets == null) {
                Toast.makeText(this, "Impossible de lire ce fichier.", Toast.LENGTH_LONG).show()
                return@registerForActivityResult
            }
            val restaures = SauvegardeConfig.importer(filesDir, octets)
            if (restaures.isEmpty()) {
                Toast.makeText(this, "Rien à restaurer dans ce fichier (pas une sauvegarde ColoriseurSTL ?).", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(this, "Config restaurée : ${restaures.joinToString(", ")}.", Toast.LENGTH_LONG).show()
            }
        } catch (e: Exception) {
            Toast.makeText(this, "Echec de la restauration : ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        findViewById<ImageButton>(R.id.btnRetour).setOnClickListener { finish() }

        val editCleApi = findViewById<EditText>(R.id.editCleApi)
        editCleApi.setText(GestionnaireParametres.lireCleApi(this))

        val btnVoirCle = findViewById<Button>(R.id.btnVoirCle)
        btnVoirCle.setOnClickListener {
            val masquee = editCleApi.inputType and InputType.TYPE_TEXT_VARIATION_PASSWORD != 0
            if (masquee) {
                editCleApi.inputType = InputType.TYPE_CLASS_TEXT
                btnVoirCle.text = "Masquer"
            } else {
                editCleApi.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                btnVoirCle.text = "Afficher"
            }
            editCleApi.setSelection(editCleApi.text.length)
        }

        val editCleApiTripo = findViewById<EditText>(R.id.editCleApiTripo)
        editCleApiTripo.setText(GestionnaireParametres.lireCleApiTripo(this))

        val btnVoirCleTripo = findViewById<Button>(R.id.btnVoirCleTripo)
        btnVoirCleTripo.setOnClickListener {
            val masquee = editCleApiTripo.inputType and InputType.TYPE_TEXT_VARIATION_PASSWORD != 0
            if (masquee) {
                editCleApiTripo.inputType = InputType.TYPE_CLASS_TEXT
                btnVoirCleTripo.text = "Masquer"
            } else {
                editCleApiTripo.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                btnVoirCleTripo.text = "Afficher"
            }
            editCleApiTripo.setSelection(editCleApiTripo.text.length)
        }

        val switchWifi = findViewById<Switch>(R.id.switchWifiUniquement)
        switchWifi.isChecked = GestionnaireParametres.lireWifiUniquement(this)
        switchWifi.setOnCheckedChangeListener { _, coche ->
            GestionnaireParametres.ecrireWifiUniquement(this, coche)
        }

        findViewById<Button>(R.id.btnEnregistrer).setOnClickListener {
            GestionnaireParametres.ecrireCleApi(this, editCleApi.text.toString().trim())
            GestionnaireParametres.ecrireCleApiTripo(this, editCleApiTripo.text.toString().trim())
            Toast.makeText(this, "Clés API enregistrées.", Toast.LENGTH_SHORT).show()
        }

        findViewById<Button>(R.id.btnSauvegarderConfig).setOnClickListener {
            if (SauvegardeConfig.fichiersConnus(filesDir).isEmpty()) {
                Toast.makeText(this, "Rien à sauvegarder pour l'instant (aucun favori ni historique encore créé).", Toast.LENGTH_LONG).show()
                return@setOnClickListener
            }
            val horodatage = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.FRANCE).format(Date())
            choixEmplacementSauvegarde.launch("coloriser-stl-config_$horodatage.zip")
        }

        findViewById<Button>(R.id.btnRestaurerConfig).setOnClickListener {
            choixFichierARestaurer.launch(arrayOf("application/zip", "application/octet-stream"))
        }

        val versionInstallee = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: ""
        } catch (e: PackageManager.NameNotFoundException) { "" }
        findViewById<TextView>(R.id.texteVersion).text = if (versionInstallee.isNotEmpty()) {
            "ColoriseurSTL — version $versionInstallee"
        } else "ColoriseurSTL"

        // 21/10/2026, porte depuis la version Windows (Vérifier-MiseAJourDisponible) - adapte au
        // modele Android (compare a la derniere Release GitHub, voir VerificateurMiseAJour).
        findViewById<Button>(R.id.btnVerifierMiseAJour).setOnClickListener {
            if (versionInstallee.isEmpty()) {
                Toast.makeText(this, "Numéro de version introuvable - vérification impossible.", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            Toast.makeText(this, "Vérification en cours...", Toast.LENGTH_SHORT).show()
            Thread {
                val resultat = VerificateurMiseAJour.verifier(versionInstallee)
                runOnUiThread {
                    when (resultat) {
                        is VerificateurMiseAJour.Resultat.NouvelleVersion -> {
                            androidx.appcompat.app.AlertDialog.Builder(this)
                                .setTitle("Mise à jour disponible")
                                .setMessage("Une version plus récente de ColoriseurSTL est disponible sur GitHub.\n\nCette copie : $versionInstallee\nDernière publiée : ${resultat.versionDistante}")
                                .setPositiveButton("Ouvrir la page de la release") { _, _ ->
                                    if (resultat.urlRelease.isNotEmpty()) {
                                        try {
                                            startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(resultat.urlRelease)))
                                        } catch (e: Exception) { }
                                    }
                                }
                                .setNegativeButton("Plus tard", null)
                                .show()
                        }
                        is VerificateurMiseAJour.Resultat.AJour ->
                            Toast.makeText(this, "Cette copie est à jour (version $versionInstallee).", Toast.LENGTH_LONG).show()
                        is VerificateurMiseAJour.Resultat.Erreur ->
                            Toast.makeText(this, resultat.message, Toast.LENGTH_LONG).show()
                    }
                }
            }.start()
        }
    }
}
