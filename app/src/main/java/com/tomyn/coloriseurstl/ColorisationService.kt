package com.tomyn.coloriseurstl

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.net.Uri
import android.os.Environment
import android.os.IBinder
import android.os.StatFs
import androidx.core.app.NotificationCompat
import androidx.documentfile.provider.DocumentFile
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * Fait tourner le traitement en premier plan, independamment de MainActivity - contrairement a
 * l'ancienne version (simple Thread lance depuis l'activite), ceci continue meme si l'activite
 * est detruite (rotation, manque de memoire) OU si l'utilisateur quitte completement l'appli
 * (retire de la liste des taches recentes). C'est la vraie garantie qu'apporte un service en
 * premier plan : la notification obligatoire qui l'accompagne EST ce qui permet a Android de ne
 * pas le tuer comme un processus d'arriere-plan ordinaire.
 *
 * Toutes les donnees du lot (fichiers, prompt, etc.) transitent par l'Intent de demarrage ;
 * l'avancement et les resultats passent par EtatTraitement (singleton partage), que
 * MainActivity sonde pour se mettre a jour - pas de callback direct vers l'activite, qui peut
 * tres bien ne pas exister au moment ou le service termine.
 */
class ColorisationService : Service() {

    companion object {
        const val EXTRA_URIS = "uris"
        const val EXTRA_NOMS = "noms"
        const val EXTRA_PROMPT = "prompt"
        const val EXTRA_MAX_COULEURS = "max_couleurs"
        const val EXTRA_DOSSIER_SORTIE_URI = "dossier_sortie_uri"
        const val EXTRA_HORODATAGE = "horodatage"
        const val EXTRA_REESSAI_SEULEMENT = "reessai_seulement"
        const val EXTRA_FOURNISSEUR = "fournisseur"
        const val EXTRA_COMPARER = "comparer"
        const val EXTRA_MESHY_OBJ_EXPERIMENTAL = "meshy_obj_experimental"
        // Porte depuis la version Windows le 10/10/2026 (reglage ajoute le 08/10/2026 cote
        // Windows, pas encore porte jusqu'ici) - voir assombrirFichierImage plus bas.
        const val EXTRA_ASSOMBRIR_TEXTURE_POURCENT = "assombrir_texture_pourcent"

        private const val ID_CANAL = "colorisation"
        private const val ID_NOTIFICATION = 1001
        const val ACTION_ANNULER = "com.tomyn.coloriseurstl.ANNULER"
        // Estimation large (les .3mf colorises observes jusqu'ici restent en dessous), par
        // prudence plutot que de sous-estimer et tomber a court en plein milieu du lot.
        private const val ESTIMATION_OCTETS_PAR_FICHIER = 20L * 1024 * 1024
    }

    private var threadTraitement: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        creerCanalNotification()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_ANNULER) {
            EtatTraitement.annulationDemandee = true
            return START_NOT_STICKY
        }

        if (intent == null || EtatTraitement.enCours) {
            // Deja en cours (ex: l'activite a renvoye le meme Intent apres une recreation) -
            // on ne relance pas un deuxieme traitement en parallele.
            return START_NOT_STICKY
        }

        // Variante depreciee (pas la nouvelle version typee API 33+) volontairement : minSdk
        // est 26, la nouvelle surcharge n'existerait pas sur les appareils plus anciens.
        @Suppress("DEPRECATION")
        val uris: ArrayList<Uri> = intent.getParcelableArrayListExtra(EXTRA_URIS) ?: arrayListOf()
        val noms: ArrayList<String> = intent.getStringArrayListExtra(EXTRA_NOMS) ?: arrayListOf()
        val prompt = intent.getStringExtra(EXTRA_PROMPT) ?: ""
        val maxCouleurs = intent.getIntExtra(EXTRA_MAX_COULEURS, 4)
        val dossierSortieUri = Uri.parse(intent.getStringExtra(EXTRA_DOSSIER_SORTIE_URI))
        val avecHorodatage = intent.getBooleanExtra(EXTRA_HORODATAGE, false)
        val fournisseur = intent.getStringExtra(EXTRA_FOURNISSEUR) ?: "Meshy"
        val comparer = intent.getBooleanExtra(EXTRA_COMPARER, false)
        val meshyObjExperimental = intent.getBooleanExtra(EXTRA_MESHY_OBJ_EXPERIMENTAL, false)
        val assombrirTexturePourcent = intent.getDoubleExtra(EXTRA_ASSOMBRIR_TEXTURE_POURCENT, 0.0)

        startForeground(ID_NOTIFICATION, construireNotificationProgression(0, uris.size, "Demarrage..."))

        EtatTraitement.reinitialiserPourNouveauLot()
        GestionnaireParametres.viderResultatsLotPersistes(this)
        EtatTraitement.totalFichiersLot = uris.size

        threadTraitement = Thread {
            traiterLot(uris, noms, prompt, maxCouleurs, dossierSortieUri, avecHorodatage, fournisseur, comparer, meshyObjExperimental, assombrirTexturePourcent)
        }
        threadTraitement?.start()

        return START_NOT_STICKY
    }

    /** Ecrit a la fois dans EtatTraitement (lu par MainActivite tant que le processus est en vie)
     * et sur le disque (voir GestionnaireParametres) - pour survivre a un kill de processus en
     * cours de lot, pas seulement une fois le lot termine. */
    private fun ajouterResultat(resultat: EtatTraitement.ResultatColorise) {
        EtatTraitement.ajouterResultat(resultat)
        GestionnaireParametres.ajouterResultatPersiste(this, resultat)
    }

    private fun ajouterEchec(echec: EtatTraitement.FichierEchec) {
        EtatTraitement.ajouterEchec(echec)
        GestionnaireParametres.ajouterEchecPersiste(this, echec)
    }

    private fun traiterLot(
        uris: List<Uri>, noms: List<String>, prompt: String, maxCouleurs: Int,
        dossierSortieUri: Uri, avecHorodatage: Boolean, fournisseur: String, comparer: Boolean,
        meshyObjExperimental: Boolean, assombrirTexturePourcent: Double = 0.0
    ) {
        val cleMeshy = GestionnaireParametres.lireCleApi(this)
        val cleTripo = GestionnaireParametres.lireCleApiTripo(this)
        val cleApi = if (fournisseur == "Tripo") cleTripo else cleMeshy
        val racineSortie = DocumentFile.fromTreeUri(this, dossierSortieUri)
        var reussites = 0
        // Comptes separes par fournisseur, utilises seulement en mode comparaison (voir plus bas
        // et terminerService) - un fichier compte comme une "reussite" globale des qu'AU MOINS UN
        // des deux fournisseurs a abouti, meme fonctionnement que la version Windows.
        var reussitesMeshy = 0
        var reussitesTripo = 0

        if (racineSortie == null) {
            EtatTraitement.ecrireJournal("ERREUR : dossier de sortie inaccessible.")
            terminerService(0)
            return
        }

        // Verification d'espace disque AVANT de commencer, pour eviter exactement la situation
        // rencontree sur la version Windows ("espace insuffisant") en plein milieu d'un lot.
        // Limite honnete : Storage Access Framework ne donne pas d'API simple pour connaitre
        // l'espace libre d'un DOSSIER PRECIS choisi via SAF - cette verification approxime avec
        // l'espace libre du stockage principal de l'appareil, qui couvre le cas courant (dossier
        // choisi dans le stockage interne) mais pas forcement un cas plus rare (carte SD externe,
        // fournisseur de stockage distant). Mieux vaut une estimation approximative que rien.
        val espaceLibreApprox = Environment.getExternalStorageDirectory()?.let { StatFs(it.path).availableBytes } ?: Long.MAX_VALUE
        val espaceEstimeNecessaire = uris.size.toLong() * ESTIMATION_OCTETS_PAR_FICHIER
        if (espaceLibreApprox < espaceEstimeNecessaire) {
            EtatTraitement.ecrireJournal(
                "ERREUR : espace disque insuffisant (estimation approximative - ${espaceLibreApprox / 1024 / 1024} Mo libres, " +
                "~${espaceEstimeNecessaire / 1024 / 1024} Mo estimes necessaires pour ${uris.size} fichier(s))."
            )
            terminerService(0)
            return
        }

        for (i in uris.indices) {
            if (EtatTraitement.annulationDemandee) {
                EtatTraitement.ecrireJournal("\n=== Annule par l'utilisateur (fichiers restants non traites) ===")
                break
            }
            EtatTraitement.indexFichierCourant = i + 1
            val uri = uris[i]
            val nom = noms[i]
            mettreAJourNotification(i + 1, uris.size, nom)

            try {
                EtatTraitement.ecrireJournal("\n=== $nom ===")
                val octets = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw Exception("impossible de lire le fichier")

                if (octets.size > 50 * 1024 * 1024) {
                    throw Exception("fichier de ${octets.size / 1024 / 1024} Mo, limite Meshy = 50 Mo - non envoye")
                }

                if (comparer) {
                    // Les deux fournisseurs tournent l'un apres l'autre sur le MEME fichier deja lu
                    // en memoire (pas de double lecture), chacun avec son propre try/catch
                    // independant : l'echec de l'un ne doit jamais empecher de recuperer le
                    // resultat de l'autre - meme logique que la version Windows.
                    var auMoinsUnReussi = false
                    try {
                        coloriserAvecUnFournisseur("Meshy", cleMeshy, octets, nom, prompt, maxCouleurs, racineSortie, avecHorodatage, "_meshy", i, uris.size, "Meshy", meshyObjExperimental, assombrirTexturePourcent)
                        reussitesMeshy++
                        auMoinsUnReussi = true
                    } catch (e: Exception) {
                        if (e.message == "ANNULATION_DEMANDEE") throw e
                        EtatTraitement.ecrireJournal("  ECHEC Meshy sur $nom : ${e.message}")
                    }
                    try {
                        coloriserAvecUnFournisseur("Tripo", cleTripo, octets, nom, prompt, maxCouleurs, racineSortie, avecHorodatage, "_tripo", i, uris.size, "Tripo", false, 0.0)
                        reussitesTripo++
                        auMoinsUnReussi = true
                    } catch (e: Exception) {
                        if (e.message == "ANNULATION_DEMANDEE") throw e
                        EtatTraitement.ecrireJournal("  ECHEC Tripo sur $nom : ${e.message}")
                    }
                    if (auMoinsUnReussi) {
                        reussites++
                    } else {
                        ajouterEchec(EtatTraitement.FichierEchec(uri, nom, "echec sur les deux fournisseurs (Meshy et Tripo)"))
                    }
                } else {
                    coloriserAvecUnFournisseur(fournisseur, cleApi, octets, nom, prompt, maxCouleurs, racineSortie, avecHorodatage, "", i, uris.size, "", meshyObjExperimental, assombrirTexturePourcent)
                    reussites++
                }
            } catch (e: Exception) {
                if (e.message == "ANNULATION_DEMANDEE") {
                    EtatTraitement.ecrireJournal("\n=== Annule par l'utilisateur (en cours de traitement de $nom) ===")
                    break
                }
                EtatTraitement.ecrireJournal("  ECHEC sur $nom : ${e.message}")
                ajouterEchec(EtatTraitement.FichierEchec(uri, nom, e.message ?: "erreur inconnue"))
            }
        }

        terminerService(reussites, comparer, reussitesMeshy, reussitesTripo, uris.size)
    }

    /**
     * Colorise UN fichier (deja lu en memoire) avec UN fournisseur, enregistre le resultat (fichier
     * de sortie + vignette dans EtatTraitement) et retourne les credits consommes. Factorise entre
     * le mode simple et le mode comparaison (voir traiterLot) - jette une exception en cas d'echec,
     * y compris "ANNULATION_DEMANDEE", a l'appelant de decider quoi en faire dans chaque mode.
     */
    private val EXTENSIONS_IMAGES = listOf("jpg", "jpeg", "png")

    private fun coloriserAvecUnFournisseur(
        fournisseurEffectif: String, cleApi: String, octets: ByteArray, nom: String, prompt: String,
        maxCouleurs: Int, racineSortie: DocumentFile, avecHorodatage: Boolean, suffixeFournisseur: String,
        indexFichier: Int, totalFichiers: Int, badgeFournisseur: String, meshyObjExperimental: Boolean,
        assombrirTexturePourcent: Double = 0.0
    ): Int {
        val suffixe = suffixeFournisseur + if (avecHorodatage) {
            "_colorise_" + java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(java.util.Date())
        } else "_colorise"
        val nomBase = nom.substringBeforeLast(".")
        val extensionFichier = nom.substringAfterLast(".", "").lowercase()
        val estUneImage = extensionFichier in EXTENSIONS_IMAGES

        if (fournisseurEffectif == "Tripo") {
            // Image -> STL (08/10/2026) : pas encore pris en charge cote Tripo dans cette
            // version, Meshy seulement pour le moment - erreur explicite plutot qu'un echec API
            // confus (Tripo recevrait l'image comme si c'etait un modele 3D).
            if (estUneImage) {
                throw Exception("les images ne sont pas encore prises en charge cote Tripo dans cette version - utilise Meshy pour une image")
            }
            // Depuis le 07/10/2026 : Tripo sort un .obj colore par sommet (plus un .3mf, voir
            // TripoApiClient) livre en ZIP - extrait dans un sous-dossier dedie, meme logique que
            // la version Windows.
            EtatTraitement.ecrireJournal("  Envoi a l'API Texture (Tripo)...")
            val extension = nom.substringAfterLast(".", "")
            val resultat = TripoApiClient.coloriser(
                octets, extension, prompt, cleApi,
                object : TripoApiClient.EcouteurAvancement {
                    override fun surProgres(etape: String, statutBrut: String, progres: Int) {
                        if (EtatTraitement.annulationDemandee) throw TripoApiClient.ErreurApi("ANNULATION_DEMANDEE")
                        EtatTraitement.ecrireJournal("    $etape : statut brut recu = '$statutBrut' ($progres%)...")
                        mettreAJourNotification(indexFichier + 1, totalFichiers, "$nom - $etape")
                    }
                }
            )
            EtatTraitement.ecrireJournal("  Termine (${resultat.creditsConsommes} credits).")
            val octetsZip = TripoApiClient.telecharger(resultat.urlZipObj)
            val nomDossier = nomBase + suffixe
            val sousDossier = racineSortie.createDirectory(nomDossier)
                ?: throw Exception("impossible de creer le sous-dossier de sortie ($nomDossier)")
            val fichierObj = extraireZipDansSousDossier(octetsZip, sousDossier)
                ?: throw Exception("le ZIP recu de Tripo ne contient aucun fichier .obj")
            EtatTraitement.ecrireJournal("  -> Enregistre : $nomDossier/${fichierObj.name} (ouvrir ce fichier dans Bambu Studio)")

            // Pas d'equivalent connu a l'apercu fourni par Meshy (thumbnail_url) cote Tripo -
            // reste a null, l'appelant affiche alors le placeholder habituel.
            ajouterResultat(EtatTraitement.ResultatColorise(fichierObj.uri, "$nomDossier/${fichierObj.name}", null, badgeFournisseur))
            enregistrerHistoriqueFichier(racineSortie, nom, "Tripo", resultat.creditsConsommes, "$nomDossier/${fichierObj.name}")
            EtatTraitement.creditsReelsLot += resultat.creditsConsommes
            return resultat.creditsConsommes
        }

        // Image -> STL (08/10/2026, idee de Tomyn, deja confirmee fonctionnelle sur la version
        // Windows) : genere d'abord le maillage via Image to 3D (maillage seul), avant d'enchainer
        // sur EXACTEMENT le meme pipeline de colorisation que pour un modele 3D fourni directement
        // (meme case .obj experimentale, meme palette) - le task_id resultant sert directement de
        // source a la Retexture, sans jamais telecharger de fichier intermediaire.
        var idTacheSource: String? = null
        var creditsImage3D = 0
        if (estUneImage) {
            EtatTraitement.ecrireJournal("  Image detectee - envoi a l'API Image to 3D (maillage seul)...")
            val resultatImage = MeshyApiClient.genererMaillageDepuisImage(
                octets, extensionFichier, cleApi,
                object : MeshyApiClient.EcouteurAvancement {
                    override fun surProgres(etape: String, statut: String, progres: Int) {
                        if (EtatTraitement.annulationDemandee) throw MeshyApiClient.ErreurApi("ANNULATION_DEMANDEE")
                        EtatTraitement.ecrireJournal("    $etape : $statut ($progres%)...")
                        mettreAJourNotification(indexFichier + 1, totalFichiers, "$nom - $etape")
                    }
                }
            )
            idTacheSource = resultatImage.idTache
            creditsImage3D = resultatImage.creditsConsommes
            EtatTraitement.ecrireJournal("  Maillage genere depuis l'image (${creditsImage3D} credits).")
        }

        if (meshyObjExperimental) {
            // Option experimentale (portee depuis la version Windows, confirmee fonctionnelle en
            // conditions reelles) : saute Multi-Color Print, recupere directement le .obj texture
            // de l'etape Retexture - une seule etape facturee, moins cher, et couleurs souvent
            // plus fideles que l'equivalent Tripo.
            EtatTraitement.ecrireJournal("  Envoi a l'API Retexture (export .obj)...")
            val resultat = MeshyApiClient.coloriserObjExperimental(
                if (idTacheSource == null) octets else null, idTacheSource, prompt, cleApi,
                object : MeshyApiClient.EcouteurAvancement {
                    override fun surProgres(etape: String, statut: String, progres: Int) {
                        if (EtatTraitement.annulationDemandee) throw MeshyApiClient.ErreurApi("ANNULATION_DEMANDEE")
                        EtatTraitement.ecrireJournal("    $etape : $statut ($progres%)...")
                        mettreAJourNotification(indexFichier + 1, totalFichiers, "$nom - $etape")
                    }
                }
            )
            EtatTraitement.ecrireJournal("  Termine (${resultat.creditsConsommes} credits).")
            val nomDossier = nomBase + suffixe
            val sousDossier = racineSortie.createDirectory(nomDossier)
                ?: throw Exception("impossible de creer le sous-dossier de sortie ($nomDossier)")
            val fichierObj = telechargerVersSousDossier(sousDossier, resultat.urlObj)
                ?: throw Exception("impossible d'enregistrer le .obj")
            resultat.urlMtl?.let { telechargerVersSousDossier(sousDossier, it) }
            resultat.urlTexture?.let { url ->
                val fichierTexture = telechargerVersSousDossier(sousDossier, url)
                // Assombrissement de la texture (porte depuis la version Windows le 10/10/2026,
                // reglage ajoute le 08/10/2026 cote Windows) : precompense l'eclaircissement du
                // melange automatique de Bambu Studio quand le jeu de filaments comprend du blanc
                // - voir assombrirFichierImage. Uniquement la texture, jamais le .obj ni le .mtl.
                if (fichierTexture != null && assombrirTexturePourcent > 0) {
                    assombrirFichierImage(fichierTexture, assombrirTexturePourcent)
                    EtatTraitement.ecrireJournal("  Texture assombrie de $assombrirTexturePourcent% (reglage utilisateur).")
                }
            }
            EtatTraitement.ecrireJournal("  -> Enregistre : $nomDossier/${fichierObj.name} (un \"reparer le maillage\" peut etre propose a l'ouverture, normal pour un import OBJ)")

            val apercu = if (resultat.urlApercu.isNotEmpty()) {
                try {
                    val octetsApercu = MeshyApiClient.telecharger(resultat.urlApercu)
                    BitmapFactory.decodeByteArray(octetsApercu, 0, octetsApercu.size)
                } catch (e: Exception) { null }
            } else null

            ajouterResultat(EtatTraitement.ResultatColorise(fichierObj.uri, "$nomDossier/${fichierObj.name}", apercu, badgeFournisseur))
            val totalCredits = creditsImage3D + resultat.creditsConsommes
            enregistrerHistoriqueFichier(racineSortie, nom, "Meshy (.obj)", totalCredits, "$nomDossier/${fichierObj.name}")
            EtatTraitement.creditsReelsLot += totalCredits
            return totalCredits
        }

        // --- Meshy, chemin habituel (.3mf via Multi-Color Print) ---
        EtatTraitement.ecrireJournal("  Envoi a l'API Retexture...")
        val resultat = MeshyApiClient.coloriser(
            if (idTacheSource == null) octets else null, idTacheSource, prompt, maxCouleurs, cleApi,
            object : MeshyApiClient.EcouteurAvancement {
                override fun surProgres(etape: String, statut: String, progres: Int) {
                    if (EtatTraitement.annulationDemandee) throw MeshyApiClient.ErreurApi("ANNULATION_DEMANDEE")
                    EtatTraitement.ecrireJournal("    $etape : $statut ($progres%)...")
                    mettreAJourNotification(indexFichier + 1, totalFichiers, "$nom - $etape")
                }
            }
        )
        EtatTraitement.ecrireJournal("  Termine (${resultat.creditsConsommes} credits).")
        val octetsResultat = MeshyApiClient.telecharger(resultat.url3mf)
        val nomSortie = nomBase + suffixe + ".3mf"
        val fichierSortie = racineSortie.createFile("application/octet-stream", nomSortie)
            ?: throw Exception("impossible de creer le fichier de sortie")
        contentResolver.openOutputStream(fichierSortie.uri)?.use { it.write(octetsResultat) }
            ?: throw Exception("impossible d'ecrire le fichier de sortie")

        EtatTraitement.ecrireJournal("  -> Enregistre : $nomSortie")

        val apercu = if (resultat.urlApercu.isNotEmpty()) {
            try {
                val octetsApercu = MeshyApiClient.telecharger(resultat.urlApercu)
                BitmapFactory.decodeByteArray(octetsApercu, 0, octetsApercu.size)
            } catch (e: Exception) { null }
        } else null

        ajouterResultat(EtatTraitement.ResultatColorise(fichierSortie.uri, nomSortie, apercu, badgeFournisseur))
        val totalCredits = creditsImage3D + resultat.creditsConsommes
        enregistrerHistoriqueFichier(racineSortie, nom, "Meshy", totalCredits, nomSortie)
        EtatTraitement.creditsReelsLot += totalCredits
        return totalCredits
    }

    /**
     * Assombrit l'image de texture .obj recue de Meshy - porte depuis la version Windows (meme
     * principe : multiplie R/G/B par un facteur via une matrice de couleurs, alpha inchange),
     * reglage ajoute le 08/10/2026 cote Windows (demande de Tomyn) pour precompenser
     * l'eclaircissement du melange automatique de Bambu Studio quand le jeu de filaments
     * choisi comprend du blanc (voir le README pour le detail). Pourcentage <= 0 ne fait rien.
     */
    private fun assombrirFichierImage(fichier: DocumentFile, pourcentageAssombrissement: Double) {
        if (pourcentageAssombrissement <= 0) return
        try {
            val octetsOriginaux = contentResolver.openInputStream(fichier.uri)?.use { it.readBytes() } ?: return
            val bitmapSource = BitmapFactory.decodeByteArray(octetsOriginaux, 0, octetsOriginaux.size) ?: return
            val facteur = (1.0 - (pourcentageAssombrissement / 100.0)).coerceAtLeast(0.0).toFloat()
            val matrice = ColorMatrix(
                floatArrayOf(
                    facteur, 0f, 0f, 0f, 0f,
                    0f, facteur, 0f, 0f, 0f,
                    0f, 0f, facteur, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
                )
            )
            val bitmapAssombri = Bitmap.createBitmap(bitmapSource.width, bitmapSource.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmapAssombri)
            val peinture = Paint().apply { colorFilter = ColorMatrixColorFilter(matrice) }
            canvas.drawBitmap(bitmapSource, 0f, 0f, peinture)
            val formatPng = fichier.name?.lowercase()?.endsWith(".png") == true
            val format = if (formatPng) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
            // "wt" (write+truncate) : necessaire pour ecraser le fichier existant via le
            // ContentResolver - un simple openOutputStream(uri) sans mode n'est pas garanti de
            // tronquer sur tous les fournisseurs SAF.
            contentResolver.openOutputStream(fichier.uri, "wt")?.use { sortie ->
                bitmapAssombri.compress(format, 92, sortie)
            }
        } catch (e: Exception) {
            EtatTraitement.ecrireJournal("  (assombrissement de la texture ignore : ${e.message})")
        }
    }

    /**
     * Historique PAR FICHIER (porte depuis la version Windows le 10/10/2026, ajoute le 08/10/2026
     * cote Windows a la demande de Tomyn) : contrairement a l'historique par LOT
     * (GestionnaireParametres.ajouterHistoriqueLot, un total par lancement), garde une ligne par
     * fichier reussi - nom, fournisseur, credits consommes, chemin de sortie. Les resultats
     * Meshy/Tripo ne sont pas recuperables depuis leur API passe 3 jours (politique officielle),
     * donc ceci ne remplace pas une sauvegarde du dossier de sortie, juste un journal local
     * complementaire.
     *
     * Ecrit dans le DOSSIER DE SORTIE choisi (pas l'espace prive de l'appli comme
     * GestionnaireParametres.ajouterHistoriqueLot) : contrairement a Windows ou le fichier est
     * juste a cote du script, l'espace prive Android n'est pas consultable par Tomyn sans outil
     * special - le dossier de sortie, lui, est deja l'endroit ou il va chercher ses fichiers
     * colorises.
     */
    private fun enregistrerHistoriqueFichier(racineSortie: DocumentFile, nomFichier: String, fournisseurLabel: String, credits: Int, cheminSortie: String) {
        try {
            val nomCsv = "historique_fichiers.csv"
            var fichierCsv = racineSortie.findFile(nomCsv)
            val estNouveau = fichierCsv == null
            if (fichierCsv == null) {
                fichierCsv = racineSortie.createFile("text/csv", nomCsv) ?: return
            }
            val ancienContenu = if (!estNouveau) {
                contentResolver.openInputStream(fichierCsv.uri)?.use { it.readBytes() } ?: ByteArray(0)
            } else ByteArray(0)
            val date = java.text.SimpleDateFormat("dd/MM/yyyy HH:mm").format(java.util.Date())
            val ligne = "$date;$nomFichier;$fournisseurLabel;$credits;$cheminSortie\n"
            contentResolver.openOutputStream(fichierCsv.uri, "wt")?.use { sortie ->
                sortie.write(ancienContenu)
                if (estNouveau) sortie.write("Date;Fichier;Fournisseur;Credits;CheminSortie\n".toByteArray())
                sortie.write(ligne.toByteArray())
            }
        } catch (e: Exception) {
            // Jamais bloquant - meme logique que l'historique de lot existant.
        }
    }

    /**
     * Extrait un ZIP (octets deja en memoire) dans un sous-dossier SAF, fichier par fichier -
     * pas d'API ZipFile classique utilisable directement sur un DocumentFile, donc lecture
     * manuelle via ZipInputStream puis ecriture de chaque entree via le ContentResolver. Les
     * eventuels sous-dossiers internes au ZIP sont aplatis (seul le nom de fichier est garde) :
     * Tripo ne renvoie jamais plusieurs fichiers de meme nom dans un seul ZIP, pas de risque de
     * collision. Retourne le DocumentFile du premier ".obj" trouve (fichier a ouvrir dans Bambu
     * Studio), ou null si le ZIP n'en contient aucun.
     */
    private fun extraireZipDansSousDossier(octetsZip: ByteArray, sousDossier: DocumentFile): DocumentFile? {
        var fichierObj: DocumentFile? = null
        ZipInputStream(ByteArrayInputStream(octetsZip)).use { zip ->
            var entree = zip.nextEntry
            while (entree != null) {
                if (!entree.isDirectory) {
                    val nomEntree = entree.name.substringAfterLast("/")
                    if (nomEntree.isNotEmpty()) {
                        val fichier = sousDossier.createFile("application/octet-stream", nomEntree)
                        if (fichier != null) {
                            contentResolver.openOutputStream(fichier.uri)?.use { sortie -> zip.copyTo(sortie) }
                            if (nomEntree.endsWith(".obj", ignoreCase = true) && fichierObj == null) {
                                fichierObj = fichier
                            }
                        }
                    }
                }
                zip.closeEntry()
                entree = zip.nextEntry
            }
        }
        return fichierObj
    }

    /** Telecharge une URL distante et l'enregistre dans un sous-dossier SAF, nommee d'apres le dernier segment de l'URL. */
    private fun telechargerVersSousDossier(sousDossier: DocumentFile, url: String): DocumentFile? {
        val nomFichier = Uri.parse(url).lastPathSegment?.substringAfterLast("/") ?: return null
        val octets = MeshyApiClient.telecharger(url)
        val fichier = sousDossier.createFile("application/octet-stream", nomFichier) ?: return null
        contentResolver.openOutputStream(fichier.uri)?.use { it.write(octets) } ?: return null
        return fichier
    }

    private fun terminerService(
        reussites: Int,
        comparer: Boolean = false,
        reussitesMeshy: Int = 0,
        reussitesTripo: Int = 0,
        totalFichiers: Int = 0
    ) {
        val echecs = EtatTraitement.echecs().size
        val texteBilan = if (comparer) {
            "Meshy $reussitesMeshy/$totalFichiers reussite(s), Tripo $reussitesTripo/$totalFichiers reussite(s)"
        } else {
            "$reussites reussite(s), $echecs echec(s)"
        }
        EtatTraitement.ecrireJournal("\n=== Bilan : $texteBilan ===")
        EtatTraitement.enCours = false

        val gestionnaire = getSystemService(NotificationManager::class.java)
        val notificationFin = NotificationCompat.Builder(this, ID_CANAL)
            .setContentTitle("Colorisation terminee")
            .setContentText(texteBilan)
            .setSmallIcon(R.drawable.ic_bobine)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        gestionnaire.notify(ID_NOTIFICATION, notificationFin)

        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    private fun creerCanalNotification() {
        val gestionnaire = getSystemService(NotificationManager::class.java)
        val canal = NotificationChannel(ID_CANAL, "Colorisation STL", NotificationManager.IMPORTANCE_LOW)
        canal.description = "Avancement de la colorisation de figurines via Meshy"
        gestionnaire.createNotificationChannel(canal)
    }

    private fun construireNotificationProgression(courant: Int, total: Int, texte: String): Notification {
        val intentOuvrirAppli = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntentOuvrir = PendingIntent.getActivity(
            this, 0, intentOuvrirAppli,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Bouton "Annuler" directement sur la notification : pas besoin de rouvrir l'appli pour
        // arreter un traitement en cours, meme fonctionnement que le bouton dans l'appli (envoie
        // la meme action au service, deja geree dans onStartCommand).
        val intentAnnuler = Intent(this, ColorisationService::class.java).apply { action = ACTION_ANNULER }
        val pendingIntentAnnuler = PendingIntent.getService(
            this, 0, intentAnnuler,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, ID_CANAL)
            .setContentTitle("Colorisation en cours ($courant/$total)")
            .setContentText(texte)
            .setSmallIcon(R.drawable.ic_bobine)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(total, courant, false)
            .setContentIntent(pendingIntentOuvrir)
            .addAction(0, "Annuler", pendingIntentAnnuler)
            .build()
    }

    private fun mettreAJourNotification(courant: Int, total: Int, texte: String) {
        val gestionnaire = getSystemService(NotificationManager::class.java)
        gestionnaire.notify(ID_NOTIFICATION, construireNotificationProgression(courant, total, texte))
    }

    override fun onDestroy() {
        super.onDestroy()
        threadTraitement = null
    }
}
