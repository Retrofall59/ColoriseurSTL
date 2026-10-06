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
import androidx.appcompat.app.AppCompatActivity

class SettingsActivity : AppCompatActivity() {

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

        findViewById<TextView>(R.id.texteVersion).text = try {
            val infos = packageManager.getPackageInfo(packageName, 0)
            "ColoriseurSTL — version ${infos.versionName}"
        } catch (e: PackageManager.NameNotFoundException) {
            "ColoriseurSTL"
        }
    }
}
