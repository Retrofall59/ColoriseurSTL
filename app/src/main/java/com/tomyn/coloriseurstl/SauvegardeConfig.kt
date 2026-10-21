package com.tomyn.coloriseurstl

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Portage de "Sauvegarder ma config..." / "Restaurer ma config..." (Windows,
 * Obtenir-FichiersConfigConnus ligne 2673) : exporte/importe en ZIP les fichiers de config
 * locaux a l'appli - pour ne pas tout reperdre (favoris de prompts, historique des lots) en
 * changeant de telephone ou en reinstallant. Trouve en continuant la comparaison
 * Windows/Android (pas un bug, une fonctionnalite manquante - Tomyn a dit "go" pour la porter).
 *
 * Perimetre volontairement plus restreint que cote Windows : la-bas, TOUT vit dans le dossier
 * du script (y compris historique_fichiers.csv et le chemin de l'outil de melange de couleurs),
 * donc tout est inclus dans le ZIP. Cote Android, seuls les fichiers du stockage PRIVE de
 * l'appli (filesDir) sont reellement perdus a la desinstallation - "historique_fichiers.csv"
 * vit lui dans le dossier de sortie choisi par l'utilisateur (SAF), donc deja hors d'atteinte
 * d'une desinstallation, et "mode-sombre.json"/le chemin de l'outil de melange n'ont pas
 * d'equivalent Android. D'ou une liste plus courte, mais couvrant exactement ce qui serait
 * reellement perdu.
 *
 * Module pur sans dependance Android (comme GenerateurDescriptionMakerWorld.kt,
 * ReessaiReseau.kt) - verifiable par execution JVM reelle avec un vrai repertoire temporaire.
 */
object SauvegardeConfig {

    val NOMS_FICHIERS_CONNUS = listOf("prompts_favoris.json", "historique_lots.csv")

    /** Les fichiers connus qui existent reellement dans [dossierFichiers] (filesDir de l'appli). */
    fun fichiersConnus(dossierFichiers: File): List<File> =
        NOMS_FICHIERS_CONNUS.map { File(dossierFichiers, it) }.filter { it.isFile }

    /** Construit le ZIP de sauvegarde. Vide (mais valide) si aucun fichier connu n'existe encore. */
    fun exporter(dossierFichiers: File): ByteArray {
        val sortie = ByteArrayOutputStream()
        ZipOutputStream(sortie).use { zip ->
            for (fichier in fichiersConnus(dossierFichiers)) {
                zip.putNextEntry(ZipEntry(fichier.name))
                fichier.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        return sortie.toByteArray()
    }

    /**
     * Restaure dans [dossierFichiers] les fichiers connus trouves dans [octetsZip] (ecrase les
     * fichiers existants). Ignore silencieusement toute entree inconnue ou tout dossier - un ZIP
     * qui n'est pas une sauvegarde de cette appli ne doit rien casser, juste ne rien restaurer.
     * Retourne les noms effectivement restaures.
     */
    fun importer(dossierFichiers: File, octetsZip: ByteArray): List<String> {
        val restaures = mutableListOf<String>()
        ZipInputStream(ByteArrayInputStream(octetsZip)).use { zip ->
            var entree = zip.nextEntry
            while (entree != null) {
                val nomSeul = File(entree.name).name
                if (!entree.isDirectory && nomSeul in NOMS_FICHIERS_CONNUS) {
                    File(dossierFichiers, nomSeul).outputStream().use { sortieFichier -> zip.copyTo(sortieFichier) }
                    restaures.add(nomSeul)
                }
                zip.closeEntry()
                entree = zip.nextEntry
            }
        }
        return restaures
    }
}
