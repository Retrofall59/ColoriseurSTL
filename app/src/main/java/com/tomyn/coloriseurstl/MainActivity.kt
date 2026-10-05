package com.tomyn.coloriseurstl

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.GridLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.NumberPicker
import android.widget.ProgressBar
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile

class MainActivity : AppCompatActivity() {

    private data class FichierSource(val uri: Uri, val nom: String)

    companion object {
        // Survit a la destruction/recreation de l'activite (rotation, manque de memoire) -
        // le traitement lui-meme vit desormais dans ColorisationService (voir EtatTraitement),
        // mais la LISTE DE DEPART (avant meme de lancer) a besoin du meme traitement pour ne
        // pas disparaitre dans les memes circonstances.
        private var fichiersSourcePersistants: List<FichierSource> = emptyList()
        private const val CREDITS_ESTIMES_PAR_FICHIER = 20
    }

    private lateinit var texteSourceChoisie: TextView
    private lateinit var texteDossierSortie: TextView
    private lateinit var menuPrompt: Spinner
    private lateinit var editPrompt: EditText
    private lateinit var selecteurCouleurs: NumberPicker
    private lateinit var btnLancer: Button
    private lateinit var btnAnnuler: Button
    private lateinit var btnRelancerEchecs: Button
    private lateinit var barreProgression: ProgressBar
    private lateinit var texteEstimationCout: TextView
    private lateinit var texteCompteurGalerie: TextView
    private lateinit var galerieFichiers: GridLayout
    private lateinit var galerieResultats: GridLayout
    private lateinit var texteJournal: TextView
    private lateinit var ongletFichiers: Button
    private lateinit var ongletResultats: Button
    private lateinit var ongletAvancement: Button

    private var fichiersSource: List<FichierSource> = emptyList()
    private var uriDossierSortie: Uri? = null
    private val caseACocherParUri = mutableMapOf<Uri, CheckBox>()
    private var dernierLotEchecs: List<EtatTraitement.FichierEchec> = emptyList()
    private var nombreResultatsAffiches = 0
    private var dernierEtatEnCours = false

    private val manipulateurSondage = Handler(Looper.getMainLooper())
    private val sondagePeriodique = object : Runnable {
        override fun run() {
            rafraichirDepuisEtatTraitement()
            manipulateurSondage.postDelayed(this, 1000)
        }
    }

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

    // Android 13+ : sans cette permission, le service tourne quand meme mais la notification de
    // progression ne s'affiche pas. Jamais bloquant si refusee, juste moins pratique.
    private val demandePermissionNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        texteSourceChoisie = findViewById(R.id.texteSourceChoisie)
        texteDossierSortie = findViewById(R.id.texteDossierSortie)
        menuPrompt = findViewById(R.id.menuPrompt)
        editPrompt = findViewById(R.id.editPrompt)
        selecteurCouleurs = findViewById(R.id.selecteurCouleurs)
        btnLancer = findViewById(R.id.btnLancer)
        btnAnnuler = findViewById(R.id.btnAnnuler)
        btnRelancerEchecs = findViewById(R.id.btnRelancerEchecs)
        barreProgression = findViewById(R.id.barreProgression)
        texteEstimationCout = findViewById(R.id.texteEstimationCout)
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
        findViewById<ImageButton>(R.id.btnHistorique).setOnClickListener { afficherHistorique() }
        findViewById<Button>(R.id.btnChoisirDossier).setOnClickListener { selectionDossierSource.launch(null) }
        findViewById<Button>(R.id.btnChoisirFichiers).setOnClickListener { selectionFichiers.launch(arrayOf("*/*")) }
        findViewById<Button>(R.id.btnChoisirDossierSortie).setOnClickListener { selectionDossierSortie.launch(null) }
        findViewById<Button>(R.id.btnToutCocher).setOnClickListener {
            caseACocherParUri.values.forEach { it.isChecked = true }
            mettreAJourEstimation()
        }
        findViewById<Button>(R.id.btnToutDecocher).setOnClickListener {
            caseACocherParUri.values.forEach { it.isChecked = false }
            mettreAJourEstimation()
        }

        configurerSelecteurCouleurs()
        configurerMenuPrompt()
        configurerOnglets()
        demanderPermissionNotificationsSiNecessaire()
        proposerExemptionBatterieSiNecessaire()

        btnLancer.setOnClickListener {
            val fichiersInclus = fichiersSource.filter { f -> caseACocherParUri[f.uri]?.isChecked != false }
            lancerColorisation(fichiersInclus.map { it.uri to it.nom })
        }
        btnAnnuler.setOnClickListener {
            EtatTraitement.annulationDemandee = true
            btnAnnuler.isEnabled = false
            btnAnnuler.text = "Annulation..."
        }
        btnRelancerEchecs.setOnClickListener {
            lancerColorisation(dernierLotEchecs.map { it.uri to it.nom })
        }

        GestionnaireParametres.lireDossierSortieUri(this)?.let { texte ->
            try {
                val uri = Uri.parse(texte)
                uriDossierSortie = uri
                texteDossierSortie.text = nomAffichableDossier(uri)
            } catch (e: Exception) { /* uri invalide : on laisse l'utilisateur en choisir un nouveau */ }
        }

        // Reconstruit la galerie de depart si l'activite vient d'etre recreee.
        if (fichiersSourcePersistants.isNotEmpty()) {
            fichiersSource = fichiersSourcePersistants
            afficherGalerieFichiers()
        }

        // Si un traitement tournait deja (service toujours actif malgre la recreation de
        // l'activite), on rattrape l'etat tout de suite plutot que d'attendre le premier sondage.
        if (EtatTraitement.enCours) {
            basculerBoutonsVersEnCours()
        }
        rafraichirDepuisEtatTraitement()
    }

    override fun onResume() {
        super.onResume()
        manipulateurSondage.post(sondagePeriodique)
    }

    override fun onPause() {
        super.onPause()
        manipulateurSondage.removeCallbacks(sondagePeriodique)
    }

    /**
     * Certains telephones (Xiaomi, Huawei, et d'autres marques avec une gestion de batterie tres
     * agressive) peuvent tuer un service en premier plan malgre les garanties normales d'Android.
     * Pas un bug cote appli dans ce cas - juste un reglage a exempter manuellement. Affiche une
     * seule fois (pas a chaque lancement), et n'ouvre que l'ecran general des parametres batterie
     * (pas de demande directe d'exemption via une permission speciale, pour rester simple).
     */
    private fun proposerExemptionBatterieSiNecessaire() {
        if (GestionnaireParametres.messageBatterieDejaVu(this)) return
        GestionnaireParametres.marquerMessageBatterieVu(this)
        AlertDialog.Builder(this)
            .setTitle("Un conseil pour les gros lots")
            .setMessage("Sur certains téléphones (Xiaomi, Huawei...), la gestion de batterie peut arrêter le traitement en arrière-plan même pendant un lot en cours. Si ça arrive, exempte ColoriserSTL de l'optimisation de batterie dans les réglages.")
            .setPositiveButton("Ouvrir les réglages batterie") { _, _ ->
                try {
                    startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                } catch (e: Exception) { /* ecran absent sur certains appareils : pas bloquant */ }
            }
            .setNegativeButton("Plus tard", null)
            .show()
    }

    private fun demanderPermissionNotificationsSiNecessaire() {
        if (Build.VERSION.SDK_INT >= 33) {
            val dejaAccordee = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            if (!dejaAccordee) demandePermissionNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
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
                    if (PromptsPredefinis.liste.values.contains(editPrompt.text.toString())) {
                        editPrompt.setText(GestionnaireParametres.lireDernierPromptPersonnalise(this@MainActivity))
                    }
                    editPrompt.requestFocus()
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        editPrompt.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                val estModeAutre = PromptsPredefinis.liste[menuPrompt.selectedItem?.toString()] == null
                if (estModeAutre) GestionnaireParametres.ecrireDernierPromptPersonnalise(this@MainActivity, s.toString())
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })
    }

    private fun configurerOnglets() {
        ongletFichiers.setOnClickListener { afficherOnglet(0) }
        ongletResultats.setOnClickListener { afficherOnglet(1) }
        ongletAvancement.setOnClickListener { afficherOnglet(2) }
        afficherOnglet(0)
    }

    private fun afficherOnglet(index: Int) {
        galerieFichiers.visibility = if (index == 0) View.VISIBLE else View.GONE
        findViewById<View>(R.id.barreOutilsGalerieFichiers).visibility = if (index == 0) View.VISIBLE else View.GONE
        galerieResultats.visibility = if (index == 1) View.VISIBLE else View.GONE
        texteJournal.visibility = if (index == 2) View.VISIBLE else View.GONE
        texteCompteurGalerie.visibility = if (index == 2) View.GONE else View.VISIBLE
        texteCompteurGalerie.text = when (index) {
            0 -> "${fichiersSource.size} fichier(s)"
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
        fichiersSourcePersistants = trouves
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
        fichiersSourcePersistants = fichiers
        afficherGalerieFichiers()
    }

    // --- Galeries (vignettes) ---

    private fun creerVignette(nom: String, image: Bitmap?, avecCaseACocher: Uri? = null, surClic: (() -> Unit)? = null): View {
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

        if (avecCaseACocher != null) {
            val caseACocher = CheckBox(this)
            caseACocher.isChecked = true
            caseACocher.text = "Inclure"
            caseACocher.textSize = 10f
            caseACocher.setOnCheckedChangeListener { _, _ -> mettreAJourEstimation() }
            panneau.addView(caseACocher)
            caseACocherParUri[avecCaseACocher] = caseACocher
        }

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
        caseACocherParUri.clear()
        texteCompteurGalerie.text = "${fichiersSource.size} fichier(s) - generation des vignettes..."
        afficherOnglet(0)

        Thread {
            var reussites = 0
            for (f in fichiersSource) {
                val bitmap = try {
                    contentResolver.openInputStream(f.uri)?.use { flux ->
                        RenduStl.rendreMiniatureDepuisFlux(flux, 220)
                    }
                } catch (e: Exception) { null }

                runOnUiThread {
                    galerieFichiers.addView(creerVignette(f.nom, bitmap, f.uri) {
                        ouvrirDansAppliExterne(f.uri)
                    })
                    if (bitmap != null) reussites++
                    texteCompteurGalerie.text = "$reussites / ${fichiersSource.size} vignette(s) affichee(s)"
                    mettreAJourEstimation()
                }
            }
        }.start()
    }

    private fun mettreAJourEstimation() {
        val inclus = fichiersSource.count { f -> caseACocherParUri[f.uri]?.isChecked != false }
        texteEstimationCout.text = if (inclus == 0) "" else
            "Coût estimé : ~${inclus * CREDITS_ESTIMES_PAR_FICHIER} crédits ($inclus fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER, estimation empirique)"
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

    // --- Historique ---

    private fun afficherHistorique() {
        val lignes = GestionnaireParametres.lireHistoriqueLots(this)
        val texte = if (lignes.isEmpty()) {
            "Aucun lot traité pour l'instant."
        } else {
            val total = lignes.sumOf { it.credits }
            val totalReussites = lignes.sumOf { it.reussites }
            buildString {
                for (l in lignes) append("${l.date} — ${l.fichiers} fichier(s), ${l.reussites} réussi(s), ${l.echecs} échec(s), ${l.credits} crédits\n")
                append("\nTotal : $totalReussites figurine(s) réussie(s), $total crédits consommés (sur ${lignes.size} lot(s))")
            }
        }
        AlertDialog.Builder(this)
            .setTitle("Historique des lots")
            .setMessage(texte)
            .setPositiveButton("Fermer", null)
            .setNegativeButton("Vider l'historique") { _, _ -> GestionnaireParametres.viderHistoriqueLots(this) }
            .show()
    }

    // --- Lancement de la colorisation (via le service en premier plan) ---

    private fun lancerColorisation(fichiersAtraiter: List<Pair<Uri, String>>) {
        if (EtatTraitement.enCours) return
        val cleApi = GestionnaireParametres.lireCleApi(this)
        if (cleApi.isBlank()) {
            Toast.makeText(this, "Clé API Meshy manquante : configure-la dans Paramètres.", Toast.LENGTH_LONG).show()
            startActivity(Intent(this, SettingsActivity::class.java))
            return
        }
        if (fichiersAtraiter.isEmpty()) {
            Toast.makeText(this, "Aucun fichier inclus.", Toast.LENGTH_SHORT).show()
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

        btnLancer.isEnabled = false
        // Verification cle+solde = appel reseau, jamais sur le thread principal.
        Thread {
            val verif = MeshyApiClient.verifierCleEtSolde(cleApi)
            runOnUiThread {
                btnLancer.isEnabled = true
                when (verif.statut) {
                    MeshyApiClient.StatutCle.INVALIDE -> {
                        AlertDialog.Builder(this)
                            .setTitle("Clé API invalide")
                            .setMessage("La clé API semble invalide ou expirée (refusée par Meshy). Vérifie-la dans Paramètres.")
                            .setPositiveButton("OK", null)
                            .show()
                    }
                    MeshyApiClient.StatutCle.INCONNU -> {
                        AlertDialog.Builder(this)
                            .setTitle("Vérification impossible")
                            .setMessage("Impossible de vérifier la clé API ou le solde pour l'instant (problème réseau ?). Continuer quand même ?")
                            .setPositiveButton("Continuer") { _, _ -> demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt) }
                            .setNegativeButton("Annuler", null)
                            .show()
                    }
                    MeshyApiClient.StatutCle.VALIDE -> {
                        val coutEstime = fichiersAtraiter.size * CREDITS_ESTIMES_PAR_FICHIER
                        if ((verif.solde ?: 0) < coutEstime) {
                            AlertDialog.Builder(this)
                                .setTitle("Solde potentiellement insuffisant")
                                .setMessage("Solde actuel : ${verif.solde} crédits. Coût estimé pour ce lot : ~$coutEstime crédits.\n\nContinuer quand même ?")
                                .setPositiveButton("Continuer") { _, _ -> demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt) }
                                .setNegativeButton("Annuler", null)
                                .show()
                        } else {
                            demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt)
                        }
                    }
                }
            }
        }.start()
    }

    private fun demarrerServiceColorisation(fichiersAtraiter: List<Pair<Uri, String>>, dossierSortie: Uri, prompt: String) {
        val intent = Intent(this, ColorisationService::class.java).apply {
            putParcelableArrayListExtra(ColorisationService.EXTRA_URIS, ArrayList(fichiersAtraiter.map { it.first }))
            putStringArrayListExtra(ColorisationService.EXTRA_NOMS, ArrayList(fichiersAtraiter.map { it.second }))
            putExtra(ColorisationService.EXTRA_PROMPT, prompt)
            putExtra(ColorisationService.EXTRA_MAX_COULEURS, selecteurCouleurs.value)
            putExtra(ColorisationService.EXTRA_DOSSIER_SORTIE_URI, dossierSortie.toString())
        }
        galerieResultats.removeAllViews()
        nombreResultatsAffiches = 0
        texteJournal.text = ""
        ContextCompat.startForegroundService(this, intent)
        basculerBoutonsVersEnCours()
        afficherOnglet(2)
    }

    private fun basculerBoutonsVersEnCours() {
        btnLancer.visibility = View.GONE
        btnRelancerEchecs.visibility = View.GONE
        btnAnnuler.visibility = View.VISIBLE
        btnAnnuler.isEnabled = true
        btnAnnuler.text = "Annuler"
        barreProgression.visibility = View.VISIBLE
        barreProgression.isIndeterminate = false
    }

    // --- Sondage periodique de EtatTraitement (fait tourner par ColorisationService) ---

    private fun rafraichirDepuisEtatTraitement() {
        texteJournal.text = EtatTraitement.journalComplet()

        val resultats = EtatTraitement.resultats()
        if (resultats.size > nombreResultatsAffiches) {
            for (i in nombreResultatsAffiches until resultats.size) {
                val r = resultats[i]
                galerieResultats.addView(creerVignette(r.nom, r.apercu, null) { ouvrirDansAppliExterne(r.uri) })
            }
            nombreResultatsAffiches = resultats.size
        }

        if (EtatTraitement.enCours) {
            barreProgression.visibility = View.VISIBLE
            barreProgression.max = maxOf(EtatTraitement.totalFichiersLot, 1)
            barreProgression.progress = EtatTraitement.indexFichierCourant
        }

        // Detecte la transition "en cours" -> "termine" pour remettre l'interface a jour une
        // seule fois (pas a chaque sondage), meme si c'est ColorisationService qui a fini le
        // travail pendant que l'activite etait en pause/recreee entretemps.
        if (dernierEtatEnCours && !EtatTraitement.enCours) {
            dernierLotEchecs = EtatTraitement.echecs()
            btnLancer.visibility = View.VISIBLE
            btnAnnuler.visibility = View.GONE
            barreProgression.visibility = View.GONE
            btnRelancerEchecs.visibility = if (dernierLotEchecs.isNotEmpty()) View.VISIBLE else View.GONE
            mettreAJourEstimation()

            val reussites = resultats.size
            val echecs = dernierLotEchecs.size
            Toast.makeText(this, "Terminé : $reussites réussite(s), $echecs échec(s).", Toast.LENGTH_LONG).show()

            try {
                GestionnaireParametres.ajouterHistoriqueLot(this, reussites + echecs, reussites, echecs, EtatTraitement.creditsReelsLot)
            } catch (e: Exception) { /* l'historique n'est qu'un plus, jamais bloquant */ }
        }
        dernierEtatEnCours = EtatTraitement.enCours
    }
}
