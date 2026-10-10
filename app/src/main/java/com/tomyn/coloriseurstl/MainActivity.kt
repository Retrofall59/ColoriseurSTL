package com.tomyn.coloriseurstl

import android.Manifest
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
        // Rectifie le 07/10/2026 : premiere lecture du tableau de bord Meshy par Tomyn mal
        // interpretee (25+15+16 = 56), le vrai detail confirme juste apres est Retexture = 10
        // credits et Multi-Color Print = 10 credits, soit 20 au total - l'estimation d'origine
        // etait donc la bonne.
        private const val CREDITS_ESTIMES_PAR_FICHIER = 20
        // Cout de la seule etape Retexture (sans Multi-Color Print) - utilise pour l'estimation
        // quand l'option .obj experimentale est cochee.
        private const val CREDITS_ESTIMES_RETEXTURE_SEULE = 10
        // Confirme par Tomyn le 07/10/2026 : import 5 + texturation 10 = 15 "de base" cote
        // Tripo, plus l'etape de conversion (variable, ~5 observes) - echelle differente de
        // celle de Meshy, d'ou une constante separee.
        private const val CREDITS_ESTIMES_PAR_FICHIER_TRIPO = 20
        // Formats acceptes par l'API Meshy en entree (confirme dans la doc officielle - le .3mf
        // n'y figure PAS : Meshy ne l'accepte qu'en SORTIE, jamais comme source a coloriser).
        private val EXTENSIONS_MODELES_3D = listOf("stl", "obj", "fbx", "glb", "gltf")
        // Image -> STL (08/10/2026, idee de Tomyn, deja confirmee fonctionnelle sur la version
        // Windows) : une image dans le dossier source est detectee par son extension, sans case
        // ni onglet separe - Meshy genere le maillage avant de le coloriser normalement.
        private val EXTENSIONS_IMAGES = listOf("jpg", "jpeg", "png")
        private val EXTENSIONS_SUPPORTEES = EXTENSIONS_MODELES_3D + EXTENSIONS_IMAGES
        // Cout de l'etape Image to 3D en maillage seul (should_texture=false, modele par defaut)
        // - confirme sur la doc tarifaire officielle Meshy, meme valeur que la version Windows.
        private const val CREDITS_ESTIMES_IMAGE_VERS_3D = 20
    }

    private lateinit var texteSourceChoisie: TextView
    private lateinit var texteDossierSortie: TextView
    private lateinit var menuCategoriePrompt: Spinner
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
    private lateinit var menuFournisseur: Spinner
    private lateinit var caseComparerFournisseurs: CheckBox
    private lateinit var caseMeshyObjExperimental: CheckBox
    private lateinit var texteAssombrirTexture: TextView
    private lateinit var champAssombrirTexture: EditText

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
        menuCategoriePrompt = findViewById(R.id.menuCategoriePrompt)
        menuPrompt = findViewById(R.id.menuPrompt)
        editPrompt = findViewById(R.id.editPrompt)
        selecteurCouleurs = findViewById(R.id.selecteurCouleurs)
        menuFournisseur = findViewById(R.id.menuFournisseur)
        caseComparerFournisseurs = findViewById(R.id.caseComparerFournisseurs)
        caseMeshyObjExperimental = findViewById(R.id.caseMeshyObjExperimental)
        texteAssombrirTexture = findViewById(R.id.texteAssombrirTexture)
        champAssombrirTexture = findViewById(R.id.champAssombrirTexture)
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
        configurerMenuFournisseur()
        caseComparerFournisseurs.setOnCheckedChangeListener { _, coche ->
            menuFournisseur.isEnabled = !coche
            mettreAJourEstimation()
        }
        caseMeshyObjExperimental.setOnCheckedChangeListener { _, coche ->
            texteAssombrirTexture.isEnabled = coche
            champAssombrirTexture.isEnabled = coche
            mettreAJourEstimation()
        }
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

        // Reprise apres un vrai kill de processus (pas juste une rotation d'ecran) - ajoute le
        // 10/10/2026, bug remonte par Tomyn : ouvrir un visualiseur STL externe depuis un resultat
        // peut suffire a faire tuer le processus par Android pour recuperer de la memoire, ce qui
        // vide EtatTraitement (objet en memoire uniquement). EtatTraitement vide ET aucun
        // traitement en cours = soit un premier lancement (rien a restaurer, les fonctions
        // ci-dessous renverront des listes vides), soit exactement ce cas de figure.
        if (!EtatTraitement.enCours && EtatTraitement.resultats().isEmpty() && EtatTraitement.echecs().isEmpty()) {
            val resultatsPersistes = GestionnaireParametres.chargerResultatsPersistes(this)
            val echecsPersistes = GestionnaireParametres.chargerEchecsPersistes(this)
            if (resultatsPersistes.isNotEmpty() || echecsPersistes.isNotEmpty()) {
                EtatTraitement.restaurerResultats(resultatsPersistes)
                EtatTraitement.restaurerEchecs(echecsPersistes)
                dernierLotEchecs = echecsPersistes
                btnRelancerEchecs.visibility = if (echecsPersistes.isNotEmpty()) View.VISIBLE else View.GONE
            }
        }

        rafraichirDepuisEtatTraitement()
    }

    override fun onResume() {
        super.onResume()
        manipulateurSondage.post(sondagePeriodique)
        mettreAJourMenuFournisseur()
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

    /** Categorie actuellement selectionnee dans menuCategoriePrompt (libelle, pas position). */
    private fun categoriePromptActuelle(): String =
        menuCategoriePrompt.selectedItem?.toString() ?: PromptsPredefinis.nomsCategories.first()

    private fun configurerMenuPrompt() {
        // --- Menu "Categorie" : filtre la liste de prompts proposee par menuPrompt. ---
        val adaptateurCategories = ArrayAdapter(this, android.R.layout.simple_spinner_item, PromptsPredefinis.nomsCategories)
        adaptateurCategories.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuCategoriePrompt.adapter = adaptateurCategories

        // Rouvre l'appli sur la derniere categorie choisie, si elle existe encore.
        val categorieInitiale = GestionnaireParametres.lireDerniereCategoriePrompt(this@MainActivity)
        val positionInitiale = categorieInitiale?.let { PromptsPredefinis.nomsCategories.indexOf(it) } ?: -1
        if (positionInitiale >= 0) menuCategoriePrompt.setSelection(positionInitiale)

        menuCategoriePrompt.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val categorie = PromptsPredefinis.nomsCategories[position]
                GestionnaireParametres.ecrireDerniereCategoriePrompt(this@MainActivity, categorie)
                remplirMenuPrompt(categorie)
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        // --- Menu "Style voulu" : peuple initialement par remplirMenuPrompt ci-dessous. ---
        menuPrompt.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val categorie = categoriePromptActuelle()
                val libelle = PromptsPredefinis.libellesPour(categorie).getOrNull(position) ?: return
                val texte = PromptsPredefinis.textePour(categorie, libelle)
                if (texte != null) {
                    editPrompt.setText(texte)
                } else {
                    // "Autre" : si le champ contient encore un preset (pas une saisie perso en
                    // cours), on recharge le dernier prompt libre enregistre pour cette
                    // categorie plutot que de vider - evite d'avoir a le retaper a chaque fois.
                    if (PromptsPredefinis.categories[categorie]?.values?.contains(editPrompt.text.toString()) == true) {
                        editPrompt.setText(GestionnaireParametres.lireDernierPromptPersonnalise(this@MainActivity, categorie))
                    }
                    editPrompt.requestFocus()
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        editPrompt.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                val categorie = categoriePromptActuelle()
                val estModeAutre = PromptsPredefinis.textePour(categorie, menuPrompt.selectedItem?.toString() ?: "") == null
                if (estModeAutre) GestionnaireParametres.ecrireDernierPromptPersonnalise(this@MainActivity, categorie, s.toString())
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })

        // Peuple le menu "Style voulu" pour la categorie actuellement affichee (initiale ou
        // restauree ci-dessus) - doit venir apres la mise en place des deux listeners.
        remplirMenuPrompt(categoriePromptActuelle())
    }

    /** (Re)peuple menuPrompt avec les entrees de la categorie donnee et selectionne la premiere. */
    private fun remplirMenuPrompt(categorie: String) {
        val adaptateur = ArrayAdapter(this, android.R.layout.simple_spinner_item, PromptsPredefinis.libellesPour(categorie))
        adaptateur.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuPrompt.adapter = adaptateur
        menuPrompt.setSelection(0)
        // setSelection(0) ne declenche pas toujours onItemSelected si la position ne change pas
        // (ex. on reste sur le premier item en changeant juste de categorie) - on met donc aussi
        // a jour editPrompt directement ici pour etre sur que le texte suit bien la categorie.
        val premierLibelle = PromptsPredefinis.libellesPour(categorie).firstOrNull()
        val premierTexte = premierLibelle?.let { PromptsPredefinis.textePour(categorie, it) }
        if (premierTexte != null) editPrompt.setText(premierTexte)
    }

    /**
     * Ne propose que les fournisseurs dont une cle est renseignee (Paramètres) - jamais de
     * fournisseur exige en particulier, voir mettreAJourMenuFournisseur appele aussi au retour
     * de l'ecran Paramètres (onResume) au cas ou les cles auraient change entretemps.
     */
    private fun configurerMenuFournisseur() {
        mettreAJourMenuFournisseur()
        menuFournisseur.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val choix = menuFournisseur.selectedItem?.toString()
                if (choix == "Meshy" || choix == "Tripo") {
                    GestionnaireParametres.ecrireFournisseurChoisi(this@MainActivity, choix)
                }
                mettreAJourEstimation()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun mettreAJourMenuFournisseur() {
        val fournisseurs = mutableListOf<String>()
        if (GestionnaireParametres.lireCleApi(this).isNotBlank()) fournisseurs.add("Meshy")
        if (GestionnaireParametres.lireCleApiTripo(this).isNotBlank()) fournisseurs.add("Tripo")
        if (fournisseurs.isEmpty()) fournisseurs.add("(aucune clé renseignée)")

        val adaptateur = ArrayAdapter(this, android.R.layout.simple_spinner_item, fournisseurs)
        adaptateur.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuFournisseur.adapter = adaptateur

        val dernierChoix = GestionnaireParametres.lireFournisseurChoisi(this)
        val index = fournisseurs.indexOf(dernierChoix)
        menuFournisseur.setSelection(if (index >= 0) index else 0)
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
        collecterFichiers3dRecursif(racine, trouves)

        if (trouves.isEmpty()) {
            Toast.makeText(this, "Aucun fichier 3D supporté trouvé dans ce dossier (recherche dans les sous-dossiers incluse).", Toast.LENGTH_LONG).show()
            return
        }
        texteSourceChoisie.text = "Dossier : ${racine.name} (${trouves.size} fichier(s))"
        fichiersSource = trouves
        fichiersSourcePersistants = trouves
        afficherGalerieFichiers()
    }

    private fun collecterFichiers3dRecursif(dossier: DocumentFile, resultat: MutableList<FichierSource>) {
        for (enfant in dossier.listFiles()) {
            if (enfant.isDirectory) {
                collecterFichiers3dRecursif(enfant, resultat)
            } else if (EXTENSIONS_SUPPORTEES.any { enfant.name?.endsWith(".$it", ignoreCase = true) == true }) {
                resultat.add(FichierSource(enfant.uri, enfant.name ?: "fichier"))
            }
        }
    }

    private fun chargerDepuisFichiers(uris: List<Uri>) {
        val fichiers = uris.map { uri ->
            val nom = DocumentFile.fromSingleUri(this, uri)?.name ?: uri.lastPathSegment ?: "fichier"
            FichierSource(uri, nom)
        }
        texteSourceChoisie.text = "${fichiers.size} fichier(s) choisi(s) individuellement"
        fichiersSource = fichiers
        fichiersSourcePersistants = fichiers
        afficherGalerieFichiers()
    }

    // --- Galeries (vignettes) ---

    private fun creerVignette(
        nom: String, image: Bitmap?, avecCaseACocher: Uri? = null,
        surClic: (() -> Unit)? = null, surClicLong: (() -> Unit)? = null, badgeFournisseur: String = ""
    ): View {
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

        if (badgeFournisseur.isNotEmpty()) {
            // Badge "Meshy"/"Tripo" affiche uniquement en mode comparaison (voir
            // EtatTraitement.ResultatColorise.fournisseur) : hors de ce mode, un seul fournisseur
            // est actif a la fois, repeter son nom sur chaque vignette n'apporterait rien.
            val badge = TextView(this)
            badge.text = badgeFournisseur
            badge.textSize = 9f
            badge.setTextColor(resources.getColor(R.color.carte_blanc, theme))
            badge.setBackgroundColor(if (badgeFournisseur == "Meshy") 0xFF2D6CDF.toInt() else 0xFFDF8A2D.toInt())
            badge.setPadding(px(4), px(1), px(4), px(1))
            badge.gravity = Gravity.CENTER
            panneau.addView(badge)
        }

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
        if (surClicLong != null) panneau.setOnLongClickListener { surClicLong(); true }
        return panneau
    }

    private fun partagerFichier(uri: Uri) {
        try {
            val intent = Intent(Intent.ACTION_SEND)
            intent.type = "application/octet-stream"
            intent.putExtra(Intent.EXTRA_STREAM, uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(intent, "Partager le résultat"))
        } catch (e: Exception) {
            Toast.makeText(this, "Impossible de partager ce fichier.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun afficherGalerieFichiers() {
        galerieFichiers.removeAllViews()
        caseACocherParUri.clear()
        texteCompteurGalerie.text = "${fichiersSource.size} fichier(s) - generation des vignettes..."
        afficherOnglet(0)

        Thread {
            var reussites = 0
            for (f in fichiersSource) {
                val extension = f.nom.substringAfterLast(".", "").lowercase()
                val bitmap = try {
                    contentResolver.openInputStream(f.uri)?.use { flux ->
                        // Image -> STL (08/10/2026) : une image de depart est deja une image,
                        // pas la peine de passer par le rendu STL maison (qui echouerait dessus).
                        if (extension in EXTENSIONS_IMAGES) {
                            BitmapFactory.decodeStream(flux)
                        } else {
                            RenduStl.rendreMiniatureDepuisFlux(flux, 220, extension)
                        }
                    }
                } catch (e: Exception) { null }

                runOnUiThread {
                    galerieFichiers.addView(creerVignette(f.nom, bitmap, f.uri, surClic = {
                        ouvrirDansAppliExterne(f.uri)
                    }))
                    if (bitmap != null) reussites++
                    texteCompteurGalerie.text = "$reussites / ${fichiersSource.size} vignette(s) affichee(s)"
                    mettreAJourEstimation()
                }
            }
        }.start()
    }

    private fun mettreAJourEstimation() {
        val inclus = fichiersSource.count { f -> caseACocherParUri[f.uri]?.isChecked != false }
        if (inclus == 0) {
            texteEstimationCout.text = ""
            return
        }
        // Image -> STL (08/10/2026) : surcout Image to 3D a ajouter uniquement pour les fichiers
        // images du lot - compte a part, affiche separement pour que le surcout soit explique.
        val nbImages = fichiersSource.count { f ->
            caseACocherParUri[f.uri]?.isChecked != false && f.nom.substringAfterLast(".", "").lowercase() in EXTENSIONS_IMAGES
        }
        val surcoutImages = if (nbImages > 0) " + ~${nbImages * CREDITS_ESTIMES_IMAGE_VERS_3D} crédits Meshy pour générer le maillage des $nbImages image(s) avant colorisation" else ""

        texteEstimationCout.text = when {
            caseComparerFournisseurs.isChecked -> {
                val totalTripo = inclus * CREDITS_ESTIMES_PAR_FICHIER_TRIPO
                if (caseMeshyObjExperimental.isChecked) {
                    val totalMeshyObj = inclus * CREDITS_ESTIMES_RETEXTURE_SEULE
                    "Coût estimé : ~$totalMeshyObj crédits Meshy (Retexture seule) + ~$totalTripo crédits Tripo ($inclus fichier(s) chacun, deux échelles de crédits différentes)$surcoutImages"
                } else {
                    val totalMeshy = inclus * CREDITS_ESTIMES_PAR_FICHIER
                    "Coût estimé : ~$totalMeshy crédits Meshy + ~$totalTripo crédits Tripo ($inclus fichier(s) chacun, deux échelles de crédits différentes)$surcoutImages"
                }
            }
            menuFournisseur.selectedItem?.toString() == "Meshy" && caseMeshyObjExperimental.isChecked -> {
                val totalMeshyObj = inclus * CREDITS_ESTIMES_RETEXTURE_SEULE
                "Coût estimé : ~$totalMeshyObj crédits ($inclus fichier(s) x $CREDITS_ESTIMES_RETEXTURE_SEULE, Retexture seule - sans Multi-Color Print)$surcoutImages"
            }
            menuFournisseur.selectedItem?.toString() == "Tripo" -> {
                val totalTripo = inclus * CREDITS_ESTIMES_PAR_FICHIER_TRIPO
                val avertImages = if (nbImages > 0) " - ATTENTION : les images ne sont pas prises en charge par Tripo, elles échoueront" else ""
                "Coût estimé : ~$totalTripo crédits Tripo ($inclus fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER_TRIPO)$avertImages"
            }
            else -> "Coût estimé : ~${inclus * CREDITS_ESTIMES_PAR_FICHIER} crédits ($inclus fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER, estimation empirique)$surcoutImages"
        }
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

    /**
     * "Wi-Fi uniquement" verifie en realite l'absence de facturation au volume
     * (NET_CAPABILITY_NOT_METERED), pas litteralement le Wi-Fi - couvre aussi un partage de
     * connexion illimite ou une connexion filaire, et exclut un Wi-Fi d'hotel/avion facture au
     * volume si l'appareil le signale comme tel.
     */
    private fun connexionFactureeAuVolume(): Boolean {
        // Ne doit jamais faire planter l'appli pour un simple controle de confort - permission
        // ACCESS_NETWORK_STATE ajoutee au manifest, mais on reste defensif ici au cas ou.
        return try {
            val gestionnaireReseau = getSystemService(ConnectivityManager::class.java) ?: return false
            val reseauActif = gestionnaireReseau.activeNetwork ?: return true
            val capacites = gestionnaireReseau.getNetworkCapabilities(reseauActif) ?: return true
            !capacites.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (e: Exception) {
            false
        }
    }

    private fun lancerColorisation(fichiersAtraiter: List<Pair<Uri, String>>) {
        if (EtatTraitement.enCours) return
        if (GestionnaireParametres.lireWifiUniquement(this) && connexionFactureeAuVolume()) {
            Toast.makeText(this, "Connexion facturée au volume détectée - lancement bloqué (réglage \"Wi-Fi uniquement\" dans Paramètres).", Toast.LENGTH_LONG).show()
            return
        }

        // Au moins une des deux cles est obligatoire, peu importe laquelle - jamais une
        // exigence specifique sur Meshy precisement.
        val cleMeshy = GestionnaireParametres.lireCleApi(this)
        val cleTripo = GestionnaireParametres.lireCleApiTripo(this)
        if (cleMeshy.isBlank() && cleTripo.isBlank()) {
            Toast.makeText(this, "Aucune clé API renseignée (Meshy ou Tripo, au moins une est nécessaire).", Toast.LENGTH_LONG).show()
            startActivity(Intent(this, SettingsActivity::class.java))
            return
        }
        val comparer = caseComparerFournisseurs.isChecked
        val fournisseur: String
        if (comparer) {
            if (cleMeshy.isBlank() || cleTripo.isBlank()) {
                Toast.makeText(this, "Le mode comparaison nécessite les deux clés API (Meshy et Tripo).", Toast.LENGTH_LONG).show()
                return
            }
            fournisseur = "Comparer"  // valeur interne, jamais affichee - voir demarrerServiceColorisation
        } else {
            val choix = menuFournisseur.selectedItem?.toString()
            if (choix != "Meshy" && choix != "Tripo") {
                Toast.makeText(this, "Choisis un fournisseur (Meshy ou Tripo) avant de lancer.", Toast.LENGTH_SHORT).show()
                return
            }
            if (choix == "Meshy" && cleMeshy.isBlank()) {
                Toast.makeText(this, "Meshy est sélectionné mais sa clé API est vide.", Toast.LENGTH_LONG).show()
                return
            }
            if (choix == "Tripo" && cleTripo.isBlank()) {
                Toast.makeText(this, "Tripo est sélectionné mais sa clé API est vide.", Toast.LENGTH_LONG).show()
                return
            }
            fournisseur = choix
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

        // Verification cle+solde : seulement pour Meshy (quand il va etre utilise, donc aussi en
        // mode comparaison puisque Meshy y est toujours sollicite). Cote Tripo, desactivee -
        // l'endpoint devine (/user/balance, jamais confirme) provoquait un blocage de l'appli sur
        // la version Windows ; rien d'essentiel perdu, le vrai pipeline n'est pas touche, les
        // erreurs eventuelles remontent normalement depuis le service pendant le traitement.
        val meshyObjExperimental = caseMeshyObjExperimental.isChecked
        // N'a de sens que si meshyObjExperimental est coche (champ grise sinon) ; texte invalide
        // ou vide -> 0 (aucun assombrissement), jamais une erreur bloquante pour un simple reglage.
        val assombrirTexturePourcent = if (meshyObjExperimental) {
            champAssombrirTexture.text.toString().replace(",", ".").toDoubleOrNull()?.coerceIn(0.0, 100.0) ?: 0.0
        } else 0.0

        if (fournisseur == "Tripo") {
            demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent)
            return
        }

        btnLancer.isEnabled = false
        Thread {
            val verif = MeshyApiClient.verifierCleEtSolde(cleMeshy)
            runOnUiThread {
                btnLancer.isEnabled = true
                when (verif.statut) {
                    MeshyApiClient.StatutCle.INVALIDE -> {
                        AlertDialog.Builder(this)
                            .setTitle("Clé API invalide")
                            .setMessage("La clé API Meshy semble invalide ou expirée. Vérifie-la dans Paramètres.")
                            .setPositiveButton("OK", null)
                            .show()
                    }
                    MeshyApiClient.StatutCle.INCONNU -> {
                        AlertDialog.Builder(this)
                            .setTitle("Vérification impossible")
                            .setMessage("Impossible de vérifier la clé API ou le solde pour l'instant (problème réseau ?). Continuer quand même ?")
                            .setPositiveButton("Continuer") { _, _ -> demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent) }
                            .setNegativeButton("Annuler", null)
                            .show()
                    }
                    MeshyApiClient.StatutCle.VALIDE -> {
                        // En mode comparaison, Tripo s'ajoute a ce cout mais n'a pas d'estimation
                        // fiable (echelle de credits differente, jamais documentee avec certitude -
                        // voir TripoApiClient) : on compare juste au cout Meshy seul, honnete plutot
                        // que d'inventer un total combine.
                        val creditsParFichierMeshy = if (meshyObjExperimental) CREDITS_ESTIMES_RETEXTURE_SEULE else CREDITS_ESTIMES_PAR_FICHIER
                        val coutEstime = fichiersAtraiter.size * creditsParFichierMeshy
                        if ((verif.solde ?: 0) < coutEstime) {
                            AlertDialog.Builder(this)
                                .setTitle("Solde potentiellement insuffisant")
                                .setMessage("Solde actuel : ${verif.solde} crédits. Coût estimé pour ce lot (Meshy seul) : ~$coutEstime crédits.\n\nContinuer quand même ?")
                                .setPositiveButton("Continuer") { _, _ -> demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent) }
                                .setNegativeButton("Annuler", null)
                                .show()
                        } else {
                            demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent)
                        }
                    }
                }
            }
        }.start()
    }

    private fun demarrerServiceColorisation(fichiersAtraiter: List<Pair<Uri, String>>, dossierSortie: Uri, prompt: String, fournisseur: String, comparer: Boolean, meshyObjExperimental: Boolean, assombrirTexturePourcent: Double = 0.0) {
        val intent = Intent(this, ColorisationService::class.java).apply {
            putParcelableArrayListExtra(ColorisationService.EXTRA_URIS, ArrayList(fichiersAtraiter.map { it.first }))
            putStringArrayListExtra(ColorisationService.EXTRA_NOMS, ArrayList(fichiersAtraiter.map { it.second }))
            putExtra(ColorisationService.EXTRA_PROMPT, prompt)
            putExtra(ColorisationService.EXTRA_MAX_COULEURS, selecteurCouleurs.value)
            putExtra(ColorisationService.EXTRA_DOSSIER_SORTIE_URI, dossierSortie.toString())
            putExtra(ColorisationService.EXTRA_FOURNISSEUR, fournisseur)
            putExtra(ColorisationService.EXTRA_COMPARER, comparer)
            putExtra(ColorisationService.EXTRA_MESHY_OBJ_EXPERIMENTAL, meshyObjExperimental)
            putExtra(ColorisationService.EXTRA_ASSOMBRIR_TEXTURE_POURCENT, assombrirTexturePourcent)
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
                galerieResultats.addView(creerVignette(r.nom, r.apercu, null,
                    { ouvrirDansAppliExterne(r.uri) }, { partagerFichier(r.uri) }, r.fournisseur))
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
