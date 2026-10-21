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
import android.widget.ScrollView
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
        // 20/10/2026 : ".webp" manquait ici (present cote Windows depuis le 10/10/2026, format
        // d'entree accepte par Meshy confirme dans son changelog officiel) - un .webp choisi via
        // le selecteur de DOSSIER (pas le selecteur de fichiers, qui lui accepte "*/*") etait donc
        // silencieusement exclu par EXTENSIONS_SUPPORTEES ci-dessous, et meme choisi via le
        // selecteur de fichiers il aurait ete mal aiguille (estUneImage=false cote
        // ColorisationService, traite comme un modele 3D au lieu d'une image).
        private val EXTENSIONS_IMAGES = listOf("jpg", "jpeg", "png", "webp")
        // 20/10/2026 : .3mf non colorise - converti localement en .stl avant envoi a Meshy (voir
        // Convertisseur3MF et ColorisationService.traiterLot). Liste separee de
        // EXTENSIONS_MODELES_3D (Meshy ne l'accepte PAS directement en entree, voir plus haut),
        // meme principe que EXTENSIONS_3MF_SOURCE cote Windows. Manquait ici jusqu'a present : un
        // .3mf choisi via le selecteur de DOSSIER etait silencieusement exclu par
        // EXTENSIONS_SUPPORTEES, rendant le convertisseur inatteignable pour ce mode de selection
        // (le selecteur de FICHIERS, lui, accepte "*/*" et n'etait pas touche par ce bug).
        private val EXTENSIONS_3MF_SOURCE = listOf("3mf")
        private val EXTENSIONS_SUPPORTEES = EXTENSIONS_MODELES_3D + EXTENSIONS_IMAGES + EXTENSIONS_3MF_SOURCE
        // Cout de l'etape Image to 3D en maillage seul (should_texture=false, modele par defaut)
        // - confirme sur la doc tarifaire officielle Meshy, meme valeur que la version Windows.
        private const val CREDITS_ESTIMES_IMAGE_VERS_3D = 20
    }

    private lateinit var texteSourceChoisie: TextView
    private lateinit var texteDossierSortie: TextView
    private lateinit var menuCategoriePrompt: Spinner
    private lateinit var menuPrompt: Spinner
    private lateinit var editPrompt: EditText
    private lateinit var btnSauverPromptFavori: Button
    private lateinit var btnSupprimerPromptFavori: Button

    // 21/10/2026, porte depuis la version Windows ("Mes favoris") : charge une fois dans
    // onCreate (configurerMenuPrompt), tenu a jour en memoire et re-persiste a chaque
    // ajout/suppression - evite de relire le fichier a chaque interaction avec le menu.
    private var promptsFavoris: LinkedHashMap<String, String> = linkedMapOf()
    private val NOM_CATEGORIE_FAVORIS = "Mes favoris"
    private lateinit var selecteurCouleurs: NumberPicker
    private lateinit var btnLancer: Button
    private lateinit var btnAnnuler: Button
    private lateinit var btnRelancerEchecs: Button
    private lateinit var barreProgression: ProgressBar
    private lateinit var texteEtaLot: TextView
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
    // 20/10/2026, vague 4 : reglages avances Meshy (portes cote API dans les vagues precedentes,
    // exposes ici dans l'UI).
    private lateinit var caseSmartTopology: CheckBox
    private lateinit var menuGeometrieResolution: Spinner
    private lateinit var menuTextureResolution: Spinner
    private lateinit var caseReparationParois: CheckBox
    private lateinit var texteTailleImpression: TextView
    private lateinit var champTailleImpression: EditText
    // 20/10/2026, vague 6 : cible de polycount, Meshy ET Tripo (voir le commentaire du layout).
    private lateinit var champTrianglesVises: EditText

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
        btnSauverPromptFavori = findViewById(R.id.btnSauverPromptFavori)
        btnSupprimerPromptFavori = findViewById(R.id.btnSupprimerPromptFavori)
        selecteurCouleurs = findViewById(R.id.selecteurCouleurs)
        menuFournisseur = findViewById(R.id.menuFournisseur)
        caseComparerFournisseurs = findViewById(R.id.caseComparerFournisseurs)
        caseMeshyObjExperimental = findViewById(R.id.caseMeshyObjExperimental)
        texteAssombrirTexture = findViewById(R.id.texteAssombrirTexture)
        champAssombrirTexture = findViewById(R.id.champAssombrirTexture)
        caseSmartTopology = findViewById(R.id.caseSmartTopology)
        menuGeometrieResolution = findViewById(R.id.menuGeometrieResolution)
        menuTextureResolution = findViewById(R.id.menuTextureResolution)
        caseReparationParois = findViewById(R.id.caseReparationParois)
        texteTailleImpression = findViewById(R.id.texteTailleImpression)
        champTailleImpression = findViewById(R.id.champTailleImpression)
        champTrianglesVises = findViewById(R.id.champTrianglesVises)
        btnLancer = findViewById(R.id.btnLancer)
        btnAnnuler = findViewById(R.id.btnAnnuler)
        btnRelancerEchecs = findViewById(R.id.btnRelancerEchecs)
        barreProgression = findViewById(R.id.barreProgression)
        texteEtaLot = findViewById(R.id.texteEtaLot)
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
        findViewById<TextView>(R.id.btnGraphiqueCredits).setOnClickListener { afficherGraphiqueCredits() }
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
        configurerMenuResolutions()
        caseReparationParois.setOnCheckedChangeListener { _, coche ->
            texteTailleImpression.isEnabled = coche
            champTailleImpression.isEnabled = coche
        }
        // 21/10/2026, bug reel trouve en usage (Tomyn avait coche les deux a la fois) : Smart
        // Topology et la resolution 2k/4k exigent chacun un ai_model different et incompatible
        // cote Meshy (confirme sur leur documentation officielle) - impossible de combiner les
        // deux sans echec HTTP 400 garanti, quel que soit le correctif cote reseau. On empeche
        // directement cette combinaison dans l'interface plutot que de la laisser echouer en
        // silence plus tard (le reseau ignore quand meme Smart Topology si jamais les deux
        // arrivaient actives malgre tout, voir MeshyApiClient.genererMaillageDepuisImage).
        caseSmartTopology.setOnCheckedChangeListener { _, coche ->
            menuGeometrieResolution.isEnabled = !coche
            if (coche) {
                menuGeometrieResolution.setSelection(0)
            }
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
        menuCategoriePrompt.selectedItem?.toString() ?: nomsCategoriesAffichees().first()

    // 21/10/2026, porte depuis la version Windows ("Mes favoris") : "Mes favoris" est une
    // categorie DYNAMIQUE (son contenu vient de promptsFavoris, pas de PromptsPredefinis qui
    // reste statique/testable) - ces trois wrappers sont le seul point qui la distingue des
    // categories normales, tout le reste du menu Categorie/Style ne connait que ces fonctions.
    private fun nomsCategoriesAffichees(): List<String> = listOf(NOM_CATEGORIE_FAVORIS) + PromptsPredefinis.nomsCategories

    private fun libellesPourCatAffichee(categorie: String): List<String> =
        if (categorie == NOM_CATEGORIE_FAVORIS) promptsFavoris.keys.toList() + PromptsPredefinis.LIBELLE_AUTRE
        else PromptsPredefinis.libellesPour(categorie)

    private fun textePourCatAffichee(categorie: String, libelle: String): String? =
        if (categorie == NOM_CATEGORIE_FAVORIS) {
            if (libelle == PromptsPredefinis.LIBELLE_AUTRE) null else promptsFavoris[libelle]
        } else PromptsPredefinis.textePour(categorie, libelle)

    /** Valeurs preset de la categorie (pour detecter si editPrompt contient encore un preset). */
    private fun valeursPresetsPourCatAffichee(categorie: String): Collection<String> =
        if (categorie == NOM_CATEGORIE_FAVORIS) promptsFavoris.values
        else PromptsPredefinis.categories[categorie]?.values?.filterNotNull() ?: emptyList()

    private fun configurerMenuPrompt() {
        promptsFavoris = GestionnaireParametres.lirePromptsFavoris(this)

        // --- Menu "Categorie" : filtre la liste de prompts proposee par menuPrompt. ---
        val adaptateurCategories = ArrayAdapter(this, android.R.layout.simple_spinner_item, nomsCategoriesAffichees())
        adaptateurCategories.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuCategoriePrompt.adapter = adaptateurCategories

        // Rouvre l'appli sur la derniere categorie choisie, si elle existe encore.
        val categorieInitiale = GestionnaireParametres.lireDerniereCategoriePrompt(this@MainActivity)
        val positionInitiale = categorieInitiale?.let { nomsCategoriesAffichees().indexOf(it) } ?: -1
        if (positionInitiale >= 0) menuCategoriePrompt.setSelection(positionInitiale)

        menuCategoriePrompt.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val categorie = nomsCategoriesAffichees()[position]
                GestionnaireParametres.ecrireDerniereCategoriePrompt(this@MainActivity, categorie)
                remplirMenuPrompt(categorie)
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        // --- Menu "Style voulu" : peuple initialement par remplirMenuPrompt ci-dessous. ---
        menuPrompt.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val categorie = categoriePromptActuelle()
                val libelle = libellesPourCatAffichee(categorie).getOrNull(position) ?: return
                val texte = textePourCatAffichee(categorie, libelle)
                if (texte != null) {
                    editPrompt.setText(texte)
                } else {
                    // "Autre" : si le champ contient encore un preset (pas une saisie perso en
                    // cours), on recharge le dernier prompt libre enregistre pour cette
                    // categorie plutot que de vider - evite d'avoir a le retaper a chaque fois.
                    if (valeursPresetsPourCatAffichee(categorie).contains(editPrompt.text.toString())) {
                        editPrompt.setText(GestionnaireParametres.lireDernierPromptPersonnalise(this@MainActivity, categorie))
                    }
                    editPrompt.requestFocus()
                }
                mettreAJourVisibiliteBoutonSupprimerFavori()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        editPrompt.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                val categorie = categoriePromptActuelle()
                val estModeAutre = textePourCatAffichee(categorie, menuPrompt.selectedItem?.toString() ?: "") == null
                if (estModeAutre) GestionnaireParametres.ecrireDernierPromptPersonnalise(this@MainActivity, categorie, s.toString())
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })

        btnSauverPromptFavori.setOnClickListener { demanderNomEtSauvegarderPromptFavori(editPrompt.text.toString()) }
        btnSupprimerPromptFavori.setOnClickListener { supprimerFavoriActuel() }

        // Peuple le menu "Style voulu" pour la categorie actuellement affichee (initiale ou
        // restauree ci-dessus) - doit venir apres la mise en place des deux listeners.
        remplirMenuPrompt(categoriePromptActuelle())
    }

    /** (Re)peuple menuPrompt avec les entrees de la categorie donnee et selectionne la premiere. */
    private fun remplirMenuPrompt(categorie: String) {
        val adaptateur = ArrayAdapter(this, android.R.layout.simple_spinner_item, libellesPourCatAffichee(categorie))
        adaptateur.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuPrompt.adapter = adaptateur
        menuPrompt.setSelection(0)
        // setSelection(0) ne declenche pas toujours onItemSelected si la position ne change pas
        // (ex. on reste sur le premier item en changeant juste de categorie) - on met donc aussi
        // a jour editPrompt directement ici pour etre sur que le texte suit bien la categorie.
        val premierLibelle = libellesPourCatAffichee(categorie).firstOrNull()
        val premierTexte = premierLibelle?.let { textePourCatAffichee(categorie, it) }
        if (premierTexte != null) editPrompt.setText(premierTexte)
        mettreAJourVisibiliteBoutonSupprimerFavori()
    }

    /**
     * "Supprimer ce favori" n'a de sens que depuis "Mes favoris", sur une entree qui n'est pas
     * "Autre" - desactive sinon plutot que de disparaitre, meme choix que la version Windows
     * (le bouton reste a sa place, pas de mise en page qui saute).
     */
    private fun mettreAJourVisibiliteBoutonSupprimerFavori() {
        val libelleActuel = menuPrompt.selectedItem?.toString()
        btnSupprimerPromptFavori.isEnabled =
            categoriePromptActuelle() == NOM_CATEGORIE_FAVORIS && libelleActuel != null && libelleActuel != PromptsPredefinis.LIBELLE_AUTRE
    }

    /** Petite boite de dialogue de saisie du nom, meme esprit que cote Windows (OK/Annuler). */
    private fun demanderNomEtSauvegarderPromptFavori(texteASauver: String) {
        if (texteASauver.isBlank()) {
            Toast.makeText(this, "Le champ de prompt est vide - rien à sauver en favori.", Toast.LENGTH_SHORT).show()
            return
        }
        val champNom = EditText(this)
        champNom.hint = "Nom du favori"
        AlertDialog.Builder(this)
            .setTitle("Nom du prompt favori")
            .setView(champNom)
            .setPositiveButton("OK") { _, _ ->
                val nomChoisi = champNom.text.toString().trim()
                if (nomChoisi.isEmpty()) return@setPositiveButton
                if (nomChoisi == PromptsPredefinis.LIBELLE_AUTRE) {
                    Toast.makeText(this, "Ce nom est réservé - choisis-en un autre.", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                promptsFavoris[nomChoisi] = texteASauver
                GestionnaireParametres.ecrirePromptsFavoris(this, promptsFavoris)
                if (categoriePromptActuelle() == NOM_CATEGORIE_FAVORIS) remplirMenuPrompt(NOM_CATEGORIE_FAVORIS)
                Toast.makeText(this, "Prompt '$nomChoisi' enregistré dans tes favoris.", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Annuler", null)
            .show()
    }

    private fun supprimerFavoriActuel() {
        if (categoriePromptActuelle() != NOM_CATEGORIE_FAVORIS) return
        val libelle = menuPrompt.selectedItem?.toString() ?: return
        if (libelle == PromptsPredefinis.LIBELLE_AUTRE) return
        promptsFavoris.remove(libelle)
        GestionnaireParametres.ecrirePromptsFavoris(this, promptsFavoris)
        remplirMenuPrompt(NOM_CATEGORIE_FAVORIS)
        Toast.makeText(this, "Favori '$libelle' supprimé.", Toast.LENGTH_SHORT).show()
    }

    /**
     * Ne propose que les fournisseurs dont une cle est renseignee (Paramètres) - jamais de
     * fournisseur exige en particulier, voir mettreAJourMenuFournisseur appele aussi au retour
     * de l'ecran Paramètres (onResume) au cas ou les cles auraient change entretemps.
     */
    // 20/10/2026, vague 4 : index 0 = "" (defaut Meshy, rien envoye), voir
    // ColorisationService.coloriserAvecUnFournisseur (geometryResolution/textureResolution).
    private fun configurerMenuResolutions() {
        val adaptateurGeometrie = ArrayAdapter(
            this, android.R.layout.simple_spinner_item,
            listOf("Standard (défaut Meshy)", "2k", "4k")
        )
        adaptateurGeometrie.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuGeometrieResolution.adapter = adaptateurGeometrie

        val adaptateurTexture = ArrayAdapter(
            this, android.R.layout.simple_spinner_item,
            listOf("Standard (défaut Meshy, 2k)", "4k", "8k")
        )
        adaptateurTexture.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        menuTextureResolution.adapter = adaptateurTexture
    }

    private fun geometrieResolutionChoisie(): String = when (menuGeometrieResolution.selectedItemPosition) {
        1 -> "2k"
        2 -> "4k"
        else -> ""
    }

    private fun textureResolutionChoisie(): String = when (menuTextureResolution.selectedItemPosition) {
        1 -> "4k"
        2 -> "8k"
        else -> ""
    }

    // 20/10/2026, vague 6 : meme plage que $numTriangles cote Windows (100 a 300000) - texte
    // invalide ou vide -> defaut 30000, jamais une erreur bloquante pour un simple reglage.
    private fun trianglesVisesChoisis(): Int =
        champTrianglesVises.text.toString().toIntOrNull()?.coerceIn(100, 300000) ?: 30000

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
        surClic: (() -> Unit)? = null, surClicLong: (() -> Unit)? = null, badgeFournisseur: String = "",
        descriptionMakerWorld: String? = null
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

        // 21/10/2026, porte depuis la version Windows (bouton "Copier description" sur chaque
        // vignette, voir Generer-DescriptionMakerWorld) : le .txt est deja ecrit a cote du
        // resultat par ColorisationService, ceci evite juste d'avoir a aller le rouvrir pour
        // copier le texte a la main avant de le coller dans le formulaire de depot MakerWorld.
        if (descriptionMakerWorld != null) {
            val lienCopier = TextView(this)
            lienCopier.text = "Copier description"
            lienCopier.textSize = 9f
            lienCopier.setTextColor(0xFF2D6CDF.toInt())
            lienCopier.gravity = Gravity.CENTER
            lienCopier.setPadding(0, px(2), 0, 0)
            lienCopier.setOnClickListener {
                val presse = getSystemService(android.content.ClipboardManager::class.java)
                presse?.setPrimaryClip(android.content.ClipData.newPlainText("Description MakerWorld", descriptionMakerWorld))
                Toast.makeText(this, "Description copiée (colle-la dans le formulaire MakerWorld).", Toast.LENGTH_SHORT).show()
            }
            panneau.addView(lienCopier)
        }
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
            .setNeutralButton("Historique par fichier") { _, _ -> afficherHistoriqueFichiers() }
            .show()
    }

    /**
     * 21/10/2026, porte depuis la version Windows (Afficher-FenetreHistoriqueFichiers) :
     * contrairement a l'historique des LOTS ci-dessus (prive a l'app), celui-ci lit
     * "historique_fichiers.csv" ECRIT DANS LE DOSSIER DE SORTIE choisi (voir
     * ColorisationService.enregistrerHistoriqueFichier) - une ligne par fichier reussi, avec son
     * nom, pour le retrouver. Champ de recherche filtrant en direct, meme principe que le
     * ListView+TextBox cote Windows, mais a base de View standard (meme choix que le graphique
     * des credits, voir afficherGraphiqueCredits ci-dessus).
     */
    private fun afficherHistoriqueFichiers() {
        val dossierSortie = uriDossierSortie
        if (dossierSortie == null) {
            Toast.makeText(this, "Choisis d'abord un dossier de sortie (aucun historique par fichier sans ça).", Toast.LENGTH_SHORT).show()
            return
        }
        val racine = DocumentFile.fromTreeUri(this, dossierSortie)
        val fichierCsv = racine?.findFile("historique_fichiers.csv")
        if (fichierCsv == null) {
            Toast.makeText(this, "Aucun historique par fichier pour l'instant dans ce dossier de sortie.", Toast.LENGTH_SHORT).show()
            return
        }
        val lignesBrutes = try {
            contentResolver.openInputStream(fichierCsv.uri)?.bufferedReader()?.readLines() ?: emptyList()
        } catch (e: Exception) { emptyList() }
        // Premiere ligne = entete ("Date;Fichier;Fournisseur;Credits;CheminSortie") - ignoree.
        val entrees = lignesBrutes.drop(1).mapNotNull { ligne ->
            val champs = ligne.split(";")
            if (champs.size >= 5) champs else null
        }
        if (entrees.isEmpty()) {
            Toast.makeText(this, "Aucune ligne d'historique exploitable pour l'instant.", Toast.LENGTH_SHORT).show()
            return
        }

        val densite = resources.displayMetrics.density
        fun px(dp: Int) = (dp * densite).toInt()

        val champRecherche = EditText(this)
        champRecherche.hint = "Rechercher par nom de fichier..."

        val conteneurResultats = LinearLayout(this)
        conteneurResultats.orientation = LinearLayout.VERTICAL

        fun rafraichirResultats(filtre: String) {
            conteneurResultats.removeAllViews()
            val filtreNorm = filtre.trim().lowercase()
            val correspondances = entrees.filter { filtreNorm.isEmpty() || it[1].lowercase().contains(filtreNorm) }
            if (correspondances.isEmpty()) {
                val vide = TextView(this)
                vide.text = "Aucun résultat."
                vide.textSize = 11f
                vide.setPadding(0, px(8), 0, px(8))
                conteneurResultats.addView(vide)
                return
            }
            // Plus recent en premier (le CSV est ecrit chronologiquement croissant).
            for (champs in correspondances.asReversed()) {
                val (date, nomFichier, fournisseurLabel, credits) = champs
                val ligneVue = TextView(this)
                ligneVue.text = "$date — $nomFichier\n$fournisseurLabel, $credits crédits"
                ligneVue.textSize = 11f
                ligneVue.setPadding(0, px(6), 0, px(6))
                conteneurResultats.addView(ligneVue)
            }
        }
        rafraichirResultats("")

        champRecherche.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) { rafraichirResultats(s.toString()) }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })

        val conteneurGeneral = LinearLayout(this)
        conteneurGeneral.orientation = LinearLayout.VERTICAL
        conteneurGeneral.setPadding(px(16), px(8), px(16), px(8))
        conteneurGeneral.addView(champRecherche)
        conteneurGeneral.addView(conteneurResultats)

        val defilement = ScrollView(this)
        defilement.addView(conteneurGeneral)

        AlertDialog.Builder(this)
            .setTitle("Historique par fichier (${entrees.size} au total)")
            .setView(defilement)
            .setPositiveButton("Fermer", null)
            .show()
    }

    /**
     * 21/10/2026, porte depuis la version Windows (Afficher-FenetreGraphiqueCredits, meme
     * source de donnees : l'historique PAR LOT, pas l'historique par fichier) : la version
     * Windows dessine un vrai graphique vectoriel (Panel.Paint + GDI+) - ici, version volontairement
     * plus simple a base de View standard (une rangee par lot, barre horizontale dont la largeur
     * est proportionnelle aux credits du lot) plutot qu'un Canvas.onDraw personnalise, jamais
     * verifiable visuellement dans cet environnement de developpement sans appareil reel.
     */
    private fun afficherGraphiqueCredits() {
        val lignes = GestionnaireParametres.lireHistoriqueLots(this)
        if (lignes.isEmpty()) {
            Toast.makeText(this, "Aucun lot traité pour l'instant - le graphique se remplit à chaque lot.", Toast.LENGTH_SHORT).show()
            return
        }
        val pointsAffiches = lignes.takeLast(40)
        val maxCredits = (pointsAffiches.maxOfOrNull { it.credits } ?: 0).coerceAtLeast(1)

        val densite = resources.displayMetrics.density
        fun px(dp: Int) = (dp * densite).toInt()

        val conteneur = LinearLayout(this)
        conteneur.orientation = LinearLayout.VERTICAL
        conteneur.setPadding(px(4), px(4), px(4), px(4))

        val totalCredits = lignes.sumOf { it.credits }
        val resume = TextView(this)
        resume.text = "Derniers ${pointsAffiches.size} lot(s) affiché(s) sur ${lignes.size} au total — $totalCredits crédits consommés au total."
        resume.textSize = 11f
        resume.setPadding(0, 0, 0, px(8))
        conteneur.addView(resume)

        for (point in pointsAffiches) {
            val ligne = LinearLayout(this)
            ligne.orientation = LinearLayout.HORIZONTAL
            ligne.setPadding(0, px(3), 0, px(3))

            val etiquetteDate = TextView(this)
            etiquetteDate.text = point.date
            etiquetteDate.textSize = 9f
            etiquetteDate.layoutParams = LinearLayout.LayoutParams(px(90), LinearLayout.LayoutParams.WRAP_CONTENT)
            ligne.addView(etiquetteDate)

            val pisteBarre = LinearLayout(this)
            pisteBarre.orientation = LinearLayout.HORIZONTAL
            pisteBarre.layoutParams = LinearLayout.LayoutParams(0, px(14), 1f)

            val poidsBarre = (point.credits.toFloat() / maxCredits.toFloat()).coerceIn(0.02f, 1f)
            val barre = View(this)
            barre.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, poidsBarre)
            barre.setBackgroundColor(0xFF2D6CDF.toInt())
            pisteBarre.addView(barre)

            val reste = View(this)
            reste.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, (1f - poidsBarre).coerceIn(0f, 0.98f))
            pisteBarre.addView(reste)

            ligne.addView(pisteBarre)

            val etiquetteCredits = TextView(this)
            etiquetteCredits.text = " ${point.credits}"
            etiquetteCredits.textSize = 9f
            etiquetteCredits.layoutParams = LinearLayout.LayoutParams(px(40), LinearLayout.LayoutParams.WRAP_CONTENT)
            ligne.addView(etiquetteCredits)

            conteneur.addView(ligne)
        }

        val defilement = ScrollView(this)
        defilement.addView(conteneur)

        AlertDialog.Builder(this)
            .setTitle("Consommation de crédits par lot")
            .setView(defilement)
            .setPositiveButton("Fermer", null)
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
        // 21/10/2026, porte depuis la version Windows (Tomyn : "des fois je veux lancer sans
        // prompt") : autorise seulement si TOUS les fichiers selectionnes sont des images - Meshy
        // et Tripo peuvent alors repartir du style de la photo source elle-meme (voir
        // ColorisationService/MeshyApiClient/TripoApiClient), ce qui n'a pas de sens pour un
        // fichier .stl/.obj deja sans couleur (aucun style de "source" possible dans ce cas).
        if (prompt.isEmpty()) {
            val toutesImages = fichiersAtraiter.all { (_, nom) -> nom.substringAfterLast(".", "").lowercase() in EXTENSIONS_IMAGES }
            if (!toutesImages) {
                Toast.makeText(
                    this,
                    "Le style/couleurs voulues est vide.\n\n(Sans prompt, Meshy et Tripo ont besoin de repartir du style de l'image source - possible seulement sur des fichiers image, pas de .stl/.obj.)",
                    Toast.LENGTH_LONG
                ).show()
                return
            }
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
        // 20/10/2026, vague 4 : reglages avances Meshy - sans effet sur Tripo (voir
        // ColorisationService.coloriserAvecUnFournisseur, branche Tripo les ignore).
        val smartTopology = caseSmartTopology.isChecked
        val geometryResolution = geometrieResolutionChoisie()
        val textureResolution = textureResolutionChoisie()
        val targetPolycount = trianglesVisesChoisis()
        val reparerParois = caseReparationParois.isChecked
        // "0" (valeur par defaut du champ) -> null, pour que le service sache qu'il ne faut rien
        // envoyer (et laisser Meshy appliquer son propre defaut de 150 mm) - meme logique que
        // Obtenir-TailleImpressionChoisie cote Windows.
        val tailleImpressionMm = if (reparerParois) {
            champTailleImpression.text.toString().toIntOrNull()?.coerceIn(0, 1000)?.takeIf { it > 0 }
        } else null

        if (fournisseur == "Tripo") {
            demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent, smartTopology, geometryResolution, textureResolution, reparerParois, tailleImpressionMm, targetPolycount)
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
                            .setPositiveButton("Continuer") { _, _ -> demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent, smartTopology, geometryResolution, textureResolution, reparerParois, tailleImpressionMm, targetPolycount) }
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
                                .setPositiveButton("Continuer") { _, _ -> demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent, smartTopology, geometryResolution, textureResolution, reparerParois, tailleImpressionMm, targetPolycount) }
                                .setNegativeButton("Annuler", null)
                                .show()
                        } else {
                            demarrerServiceColorisation(fichiersAtraiter, dossierSortie, prompt, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent, smartTopology, geometryResolution, textureResolution, reparerParois, tailleImpressionMm, targetPolycount)
                        }
                    }
                }
            }
        }.start()
    }

    private fun demarrerServiceColorisation(
        fichiersAtraiter: List<Pair<Uri, String>>, dossierSortie: Uri, prompt: String, fournisseur: String,
        comparer: Boolean, meshyObjExperimental: Boolean, assombrirTexturePourcent: Double = 0.0,
        smartTopology: Boolean = false, geometryResolution: String = "", textureResolution: String = "",
        reparerParois: Boolean = false, tailleImpressionMm: Int? = null, targetPolycount: Int = 30000
    ) {
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
            putExtra(ColorisationService.EXTRA_SMART_TOPOLOGY, smartTopology)
            putExtra(ColorisationService.EXTRA_GEOMETRY_RESOLUTION, geometryResolution)
            putExtra(ColorisationService.EXTRA_TEXTURE_RESOLUTION, textureResolution)
            putExtra(ColorisationService.EXTRA_REPARER_PAROIS, reparerParois)
            tailleImpressionMm?.let { putExtra(ColorisationService.EXTRA_TAILLE_IMPRESSION_MM, it) }
            putExtra(ColorisationService.EXTRA_TARGET_POLYCOUNT, targetPolycount)
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
                    { ouvrirDansAppliExterne(r.uri) }, { partagerFichier(r.uri) }, r.fournisseur,
                    r.descriptionMakerWorld))
            }
            nombreResultatsAffiches = resultats.size
        }

        if (EtatTraitement.enCours) {
            barreProgression.visibility = View.VISIBLE
            barreProgression.max = maxOf(EtatTraitement.totalFichiersLot, 1)
            barreProgression.progress = EtatTraitement.indexFichierCourant

            // 21/10/2026, porte depuis la version Windows (Afficher-ProgressionEnCours) - demande
            // par Tomyn pour les gros lots (200+ fichiers) de son collegue dessinateur.
            if (EtatTraitement.debutTraitement > 0) {
                val secondesEcoulees = (System.currentTimeMillis() - EtatTraitement.debutTraitement) / 1000.0
                texteEtaLot.text = EstimateurEtaLot.ligneStatut(
                    EtatTraitement.indexFichierCourant, EtatTraitement.totalFichiersLot,
                    secondesEcoulees, EtatTraitement.creditsReelsLot, EtatTraitement.etapeTexte
                )
                texteEtaLot.visibility = View.VISIBLE
            }
        }

        // Detecte la transition "en cours" -> "termine" pour remettre l'interface a jour une
        // seule fois (pas a chaque sondage), meme si c'est ColorisationService qui a fini le
        // travail pendant que l'activite etait en pause/recreee entretemps.
        if (dernierEtatEnCours && !EtatTraitement.enCours) {
            dernierLotEchecs = EtatTraitement.echecs()
            btnLancer.visibility = View.VISIBLE
            btnAnnuler.visibility = View.GONE
            barreProgression.visibility = View.GONE
            texteEtaLot.visibility = View.GONE
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
