package com.tomyn.coloriseurstl

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Environment
import android.os.IBinder
import android.os.StatFs
import androidx.core.app.NotificationCompat
import androidx.documentfile.provider.DocumentFile

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

        startForeground(ID_NOTIFICATION, construireNotificationProgression(0, uris.size, "Demarrage..."))

        EtatTraitement.reinitialiserPourNouveauLot()
        EtatTraitement.totalFichiersLot = uris.size

        threadTraitement = Thread {
            traiterLot(uris, noms, prompt, maxCouleurs, dossierSortieUri, avecHorodatage)
        }
        threadTraitement?.start()

        return START_NOT_STICKY
    }

    private fun traiterLot(
        uris: List<Uri>, noms: List<String>, prompt: String, maxCouleurs: Int,
        dossierSortieUri: Uri, avecHorodatage: Boolean
    ) {
        val cleApi = GestionnaireParametres.lireCleApi(this)
        val racineSortie = DocumentFile.fromTreeUri(this, dossierSortieUri)
        var reussites = 0

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

                EtatTraitement.ecrireJournal("  Envoi a l'API Retexture...")
                val resultat = MeshyApiClient.coloriser(
                    octets, prompt, maxCouleurs, cleApi,
                    object : MeshyApiClient.EcouteurAvancement {
                        override fun surProgres(etape: String, statut: String, progres: Int) {
                            if (EtatTraitement.annulationDemandee) throw MeshyApiClient.ErreurApi("ANNULATION_DEMANDEE")
                            EtatTraitement.ecrireJournal("    $etape : $statut ($progres%)...")
                            mettreAJourNotification(i + 1, uris.size, "$nom - $etape")
                        }
                    }
                )
                EtatTraitement.ecrireJournal("  Termine (${resultat.creditsConsommes} credits).")

                val octetsResultat = MeshyApiClient.telecharger(resultat.url3mf)
                val suffixe = if (avecHorodatage) {
                    "_colorise_" + java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(java.util.Date())
                } else "_colorise"
                val nomSortie = nom.substringBeforeLast(".") + suffixe + ".3mf"
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

                EtatTraitement.ajouterResultat(EtatTraitement.ResultatColorise(fichierSortie.uri, nomSortie, apercu))
                EtatTraitement.creditsReelsLot += resultat.creditsConsommes
                reussites++
            } catch (e: Exception) {
                if (e.message == "ANNULATION_DEMANDEE") {
                    EtatTraitement.ecrireJournal("\n=== Annule par l'utilisateur (en cours de traitement de $nom) ===")
                    break
                }
                EtatTraitement.ecrireJournal("  ECHEC sur $nom : ${e.message}")
                EtatTraitement.ajouterEchec(EtatTraitement.FichierEchec(uri, nom, e.message ?: "erreur inconnue"))
            }
        }

        terminerService(reussites)
    }

    private fun terminerService(reussites: Int) {
        val echecs = EtatTraitement.echecs().size
        EtatTraitement.ecrireJournal("\n=== Bilan : $reussites reussite(s), $echecs echec(s) ===")
        EtatTraitement.enCours = false

        val gestionnaire = getSystemService(NotificationManager::class.java)
        val notificationFin = NotificationCompat.Builder(this, ID_CANAL)
            .setContentTitle("Colorisation terminee")
            .setContentText("$reussites reussite(s), $echecs echec(s)")
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
