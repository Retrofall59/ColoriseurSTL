package com.tomyn.coloriseurstl

import android.content.pm.PackageManager
import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.ImageButton
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

        findViewById<Button>(R.id.btnEnregistrer).setOnClickListener {
            GestionnaireParametres.ecrireCleApi(this, editCleApi.text.toString().trim())
            Toast.makeText(this, "Clé API enregistrée.", Toast.LENGTH_SHORT).show()
        }

        findViewById<TextView>(R.id.texteVersion).text = try {
            val infos = packageManager.getPackageInfo(packageName, 0)
            "ColoriseurSTL — version ${infos.versionName}"
        } catch (e: PackageManager.NameNotFoundException) {
            "ColoriseurSTL"
        }
    }
}
