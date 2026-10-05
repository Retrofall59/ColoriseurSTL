package com.tomyn.coloriseurstl

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.GridLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.NumberPicker
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.documentfile.provider.DocumentFile

class MainActivity : AppCompatActivity() {

    private data class FichierSource(val uri: Uri, val nom: String)

    private lateinit var texteSourceChoisie: TextView
    private lateinit var texteDossierSortie: TextView
    private lateinit var menuPrompt: Spinner
    private lateinit var editPrompt: EditText
    private lateinit var selecteurCouleurs: NumberPicker
    private lateinit var btnLancer: Button
    private lateinit var texteCompteurGalerie: TextView
    private lateinit var galerieFichiers: GridLayout
    private lateinit var galerieResultats: GridLayout
    private lateinit var texteJournal: TextView
    private lateinit var ongletFichiers: Button
    private lateinit var ongletResultats: Button
    private lateinit var ongletAvancement: Button

    private var fichiersSource: List<FichierSource> = emptyList()
    private var uriDossierSortie: Uri? = null
    private var traitementEnCours = false

    // --- Selecteurs de fichiers/dossiers (Storage Access Framework) ---

    private val selectionDossierSource = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            chargerDepuisDossier(uri)
        }
    }

    private val selectionFichiers = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) {
            for (uri in uris) contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            chargerDepuisFichiers(uris)
        }
    }

    private val selectionDossierSortie = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            uriDossierSortie = uri
            GestionnaireParametres.ecrireDossierSortieUri(this, uri.toString())
            texteDossierSortie.text = nomAffichableDossier(uri)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        texteSourceChoisie = findViewById(R.id.texteSourceChoisie)
        texteDossierSortie = findViewById(R.id.texteDossierSortie)
        menuPrompt = findViewById(R.id.menuPrompt)
        editPrompt = findViewById(R.id.editPrompt)
        selecteurCouleurs = findViewById(R.id.selecteurCouleurs)
        btnLancer = findViewById(R.id.btnLancer)
        texteCompteurGalerie = findViewById(R.id.texteCompteurGalerie)
        galerieFichiers = findViewById(R.id.galerieFichiers)
        galerieResultats = findViewById(R.id.galerieResultats)
        texteJournal = findViewById(R.id.texteJournal)
        ongletFichiers = findViewById(R.id.ongletFichiers)
        ongletResultats = findViewById(R.id.ongletResultats)
        ongletAvancement = findViewById(R.id.ongletAvancement)

        findViewById<ImageButton>(R.id.btnParametres).setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        findViewById<Button>(R.id.btnChoisirDossier).setOnClickListener { selectionDossierSource.launch(null) }
        findViewById<Button>(R.id.btnChoisirFichiers).setOnClickListener { selectionFichiers.launch(arrayOf("*/*")) }
        findViewById<Button>(R.id.btnChoisirDossierSortie).setOnClickListener { selectionDossierSortie.launch(null) }

        configurerSelecteurCouleurs()
        configurerMenuPrompt()
        configurerOnglets()

        btnLancer.setOnClickListener { lancerColorisation() }

        // Dossier de sortie precedemment choisi (persiste grace a takePersistableUriPermission)
        GestionnaireParametres.lireDossierSortieUri(this)?.let { texte ->
            try {
                val uri = Uri.parse(texte)
                uriDossierSortie = uri
                texteDossierSortie.text = nomAffichableDossier(uri)
            } catch (e: Exception) { /* uri invalide : on laisse l'utilisateur en choisir un nouveau */ }
        }
    }

    private fun configurerSelecteurCouleurs() {
        selecteurCouleurs.minValue = 1
        selecteurCouleurs.maxValue = 16
        selecteurCouleurs.value = GestionnaireParametres.lireNbCouleurs(this)
        selecteurCouleurs.setOnValueChangedListener { _, _, nouvelleValeur ->
            GestionnaireParametres.ecrireNbCouleurs(this, nouvelleValeur)
        }
    }

    private fun configurerMenuPrompt() {
        val adaptateur = ArrayAdapter(this, android.R.layout.simple_spinner_item, PromptsPredefinis.libelles)
        adaptateur.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuPrompt.adapter = adaptateur

        editPrompt.setText(PromptsPredefinis.liste.values.first())

        menuPrompt.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val libelle = PromptsPredefinis.libelles[position]
                val texte = PromptsPredefinis.liste[libelle]
                if (texte != null) {
                    editPrompt.setText(texte)
                } else {
                    // "Autre" : on vide seulement si le champ contenait encore un preset (pas une
                    // saisie personnelle qu'on viendrait d'ecraser par erreur)
                    if (PromptsPredefinis.liste.values.contains(editPrompt.text.toString())) {
                        editPrompt.setText("")
                    }
                    editPrompt.requestFocus()
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun configurerOnglets() {
        ongletFichiers.setOnClickListener { afficherOnglet(0) }
        ongletResultats.setOnClickListener { afficherOnglet(1) }
        ongletAvancement.setOnClickListener { afficherOnglet(2) }
        afficherOnglet(0)
    }

    private fun afficherOnglet(index: Int) {
        galerieFichiers.visibility = if (index == 0) View.VISIBLE else View.GONE
        galerieResultats.visibility = if (index == 1) View.VISIBLE else View.GONE
        texteJournal.visibility = if (index == 2) View.VISIBLE else View.GONE
        texteCompteurGalerie.visibility = if (index == 2) View.GONE else View.VISIBLE
        texteCompteurGalerie.text = when (index) {
            0 -> "${fichiersSource.size} fichier(s)"
            1 -> ""
            else -> ""
        }
    }

    private fun nomAffichableDossier(uri: Uri): String =
        DocumentFile.fromTreeUri(this, uri)?.name ?: uri.lastPathSegment ?: uri.toString()

    // --- Chargement des fichiers source ---

    private fun chargerDepuisDossier(uriDossier: Uri) {
        val racine = DocumentFile.fromTreeUri(this, uriDossier)
        if (racine == null || !racine.isDirectory) {
            Toast.makeText(this, "Dossier introuvable.", Toast.LENGTH_SHORT).show()
            return
        }
        val trouves = ArrayList<FichierSource>()
        collecterStlRecursif(racine, trouves)

        if (trouves.isEmpty()) {
            Toast.makeText(this, "Aucun fichier .stl trouvé dans ce dossier (recherche dans les sous-dossiers incluse).", Toast.LENGTH_LONG).show()
            return
        }
        texteSourceChoisie.text = "Dossier : ${racine.name} (${trouves.size} fichier(s) .stl)"
        fichiersSource = trouves
        afficherGalerieFichiers()
    }

    private fun collecterStlRecursif(dossier: DocumentFile, resultat: MutableList<FichierSource>) {
        for (enfant in dossier.listFiles()) {
            if (enfant.isDirectory) {
                collecterStlRecursif(enfant, resultat)
            } else if (enfant.name?.endsWith(".stl", ignoreCase = true) == true) {
                resultat.add(FichierSource(enfant.uri, enfant.name ?: "fichier.stl"))
            }
        }
    }

    private fun chargerDepuisFichiers(uris: List<Uri>) {
        val fichiers = uris.map { uri ->
            val nom = DocumentFile.fromSingleUri(this, uri)?.name ?: uri.lastPathSegment ?: "fichier.stl"
            FichierSource(uri, nom)
        }
        texteSourceChoisie.text = "${fichiers.size} fichier(s) choisi(s) individuellement"
        fichiersSource = fichiers
        afficherGalerieFichiers()
    }

    // --- Galeries (vignettes) ---

    private fun creerVignette(nom: String, image: Bitmap?, surClic: (() -> Unit)? = null): View {
        val densite = resources.displayMetrics.density
        fun px(dp: Int) = (dp * densite).toInt()

        val panneau = LinearLayout(this)
        panneau.orientation = LinearLayout.VERTICAL
        panneau.setPadding(px(6), px(6), px(6), px(6))
        val paramsPanneau = GridLayout.LayoutParams()
        paramsPanneau.width = px(110)
        paramsPanneau.height = GridLayout.LayoutParams.WRAP_CONTENT
        paramsPanneau.setMargins(px(4), px(4), px(4), px(4))
        panneau.layoutParams = paramsPanneau
        panneau.setBackgroundColor(resources.getColor(R.color.carte_blanc, theme))

        val boiteImage = ImageView(this)
        boiteImage.layoutParams = LinearLayout.LayoutParams(px(98), px(98))
        boiteImage.scaleType = ImageView.ScaleType.CENTER_CROP
        if (image != null) boiteImage.setImageBitmap(image)
        else boiteImage.setImageResource(android.R.drawable.ic_menu_report_image)
        panneau.addView(boiteImage)

        val etiquette = TextView(this)
        etiquette.text = nom
        etiquette.textSize = 10f
        etiquette.gravity = Gravity.CENTER
        etiquette.setPadding(0, px(4), 0, 0)
        etiquette.maxLines = 2
        panneau.addView(etiquette)

        if (surClic != null) panneau.setOnClickListener { surClic() }
        return panneau
    }

    private fun afficherGalerieFichiers() {
        galerieFichiers.removeAllViews()
        texteCompteurGalerie.text = "${fichiersSource.size} fichier(s) - generation des vignettes..."
        afficherOnglet(0)

        // Rendu en arriere-plan (meme pour un simple dessin, la lecture de fichiers potentiellement
        // gros ne doit jamais bloquer l'interface).
        Thread {
            var reussites = 0
            for (f in fichiersSource) {
                val bitmap = try {
                    contentResolver.openInputStream(f.uri)?.use { flux ->
                        RenduStl.rendreMiniatureDepuisFlux(flux, 220)
                    }
                } catch (e: Exception) { null }

                runOnUiThread {
                    galerieFichiers.addView(creerVignette(f.nom, bitmap) {
                        ouvrirDansAppliExterne(f.uri)
                    })
                    if (bitmap != null) reussites++
                    texteCompteurGalerie.text = "$reussites / ${fichiersSource.size} vignette(s) affichee(s)"
                }
            }
        }.start()
    }

    private fun ouvrirDansAppliExterne(uri: Uri) {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.setDataAndType(uri, "application/octet-stream")
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(this, "Aucune appli pour ouvrir ce fichier sur cet appareil.", Toast.LENGTH_SHORT).show()
        }
    }

    // --- Lancement de la colorisation ---

    private fun lancerColorisation() {
        if (traitementEnCours) return

        val cleApi = GestionnaireParametres.lireCleApi(this)
        if (cleApi.isBlank()) {
            Toast.makeText(this, "Clé API Meshy manquante : configure-la dans Paramètres.", Toast.LENGTH_LONG).show()
            startActivity(Intent(this, SettingsActivity::class.java))
            return
        }
        if (fichiersSource.isEmpty()) {
            Toast.makeText(this, "Aucun fichier .stl sélectionné.", Toast.LENGTH_SHORT).show()
            return
        }
        val dossierSortie = uriDossierSortie
        if (dossierSortie == null) {
            Toast.makeText(this, "Choisis d'abord un dossier de sortie.", Toast.LENGTH_SHORT).show()
            return
        }
        val prompt = editPrompt.text.toString().trim()
        if (prompt.isEmpty()) {
            Toast.makeText(this, "Le style/couleurs voulues est vide.", Toast.LENGTH_SHORT).show()
            return
        }
        val maxCouleurs = selecteurCouleurs.value

        traitementEnCours = true
        btnLancer.isEnabled = false
        texteJournal.text = ""
        galerieResultats.removeAllViews()
        afficherOnglet(2)

        val racineSortie = DocumentFile.fromTreeUri(this, dossierSortie)
        if (racineSortie == null) {
            ecrireJournal("ERREUR : dossier de sortie inaccessible.")
            traitementEnCours = false
            btnLancer.isEnabled = true
            return
        }

        Thread {
            var reussites = 0
            var echecs = 0
            for (f in fichiersSource) {
                try {
                    ecrireJournalThread("\n=== ${f.nom} ===")
                    val octets = contentResolver.openInputStream(f.uri)?.use { it.readBytes() }
                        ?: throw Exception("impossible de lire le fichier")

                    ecrireJournalThread("  Envoi à l'API Retexture...")
                    val resultat = MeshyApiClient.coloriser(
                        octets, prompt, maxCouleurs, cleApi,
                        object : MeshyApiClient.EcouteurAvancement {
                            override fun surProgres(etape: String, statut: String, progres: Int) {
                                ecrireJournalThread("    $etape : $statut ($progres%)...")
                            }
                        }
                    )
                    ecrireJournalThread("  Terminé (${resultat.creditsConsommes} crédits).")

                    val octetsResultat = MeshyApiClient.telecharger(resultat.url3mf)
                    val nomSortie = f.nom.substringBeforeLast(".") + "_colorise.3mf"
                    val fichierSortie = racineSortie.createFile("application/octet-stream", nomSortie)
                        ?: throw Exception("impossible de créer le fichier de sortie")
                    contentResolver.openOutputStream(fichierSortie.uri)?.use { it.write(octetsResultat) }
                        ?: throw Exception("impossible d'écrire le fichier de sortie")

                    ecrireJournalThread("  -> Enregistré : $nomSortie")

                    val apercu = if (resultat.urlApercu.isNotEmpty()) {
                        try {
                            val octetsApercu = MeshyApiClient.telecharger(resultat.urlApercu)
                            BitmapFactory.decodeByteArray(octetsApercu, 0, octetsApercu.size)
                        } catch (e: Exception) { null }
                    } else null

                    runOnUiThread {
                        galerieResultats.addView(creerVignette(nomSortie, apercu) {
                            ouvrirDansAppliExterne(fichierSortie.uri)
                        })
                    }
                    reussites++
                } catch (e: Exception) {
                    ecrireJournalThread("  ECHEC sur ${f.nom} : ${e.message}")
                    echecs++
                }
            }

            ecrireJournalThread("\n=== Bilan : $reussites réussite(s), $echecs échec(s) ===")
            runOnUiThread {
                traitementEnCours = false
                btnLancer.isEnabled = true
                Toast.makeText(this, "Terminé : $reussites réussite(s), $echecs échec(s).", Toast.LENGTH_LONG).show()
            }
        }.start()
    }

    private fun ecrireJournal(texte: String) {
        texteJournal.append(if (texteJournal.text.isEmpty()) texte else "\n$texte")
    }

    private fun ecrireJournalThread(texte: String) {
        runOnUiThread { ecrireJournal(texte) }
    }
}
