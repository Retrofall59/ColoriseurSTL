package com.tomyn.coloriseurstl

import java.io.BufferedReader
import java.io.ByteArrayInputStream
import java.io.InputStreamReader
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Compte le nombre de triangles d'un .stl binaire ou d'un .obj, porte depuis la version Windows
 * (15/10/2026 pour le .stl, 16/10/2026 pour le .obj) - sert a decider si une simplification
 * automatique (Remesh cote Meshy, Retopology/decimate cote Tripo) est utile AVANT la colorisation,
 * pour ne pas envoyer un maillage inutilement lourd (voir SEUIL_TRIANGLES_REMESH_AUTO dans
 * ColorisationService). N'utilise que java.io/java.nio (aucune API Android) - verifiable avec un
 * vrai JDK, meme principe que Convertisseur3MF.
 *
 * Opere sur un ByteArray deja en memoire (pas un chemin de fichier) - Android lit les fichiers
 * via Storage Access Framework, pas de File classique disponible pour un contenu SAF.
 */
object CompteurTriangles {

    /**
     * Point d'entree unique (16/10/2026 cote Windows) - choisit le bon compteur selon l'extension,
     * sans que l'appelant ait besoin de savoir lequel utiliser. Renvoie null pour toute autre
     * extension (ASCII .stl non detecte, .3mf deja converti avant d'arriver ici, images...) - pas
     * de simplification automatique dans ces cas, exactement comme cote Windows.
     */
    fun obtenirNombreTriangles(nomFichier: String, octets: ByteArray): Int? {
        return when (nomFichier.substringAfterLast(".", "").lowercase()) {
            "stl" -> obtenirNombreTrianglesStl(octets)
            "obj" -> obtenirNombreTrianglesObj(octets)
            else -> null
        }
    }

    /**
     * Nombre de triangles d'un .stl BINAIRE, lu directement dans son en-tete (octets 80-83, entier
     * non signe sur 4 octets, little-endian - standard du format), pas besoin de parser toute la
     * geometrie. Verification croisee : la taille de fichier attendue pour ce nombre de triangles
     * (84 + N*50 octets) doit correspondre EXACTEMENT a la taille reelle - sinon c'est tres
     * probablement de l'ASCII (qui peut aussi commencer par n'importe quoi dans ses 80 premiers
     * octets, donc ne pas se fier au header seul) ou un fichier corrompu, et on renvoie null plutot
     * que de risquer un faux resultat.
     */
    private fun obtenirNombreTrianglesStl(octets: ByteArray): Int? {
        if (octets.size < 84) return null
        val buffer = ByteBuffer.wrap(octets, 80, 4).order(ByteOrder.LITTLE_ENDIAN)
        val nbTriangles = buffer.int.toLong() and 0xFFFFFFFFL // uint32 -> Long non signe
        val tailleAttendue = 84L + nbTriangles * 50L
        if (tailleAttendue == octets.size.toLong() && nbTriangles <= Int.MAX_VALUE.toLong()) {
            return nbTriangles.toInt()
        }
        return null
    }

    /**
     * Nombre de triangles d'un .obj - contrairement au .stl binaire, l'en-tete .obj ne contient
     * aucun compteur : il faut compter les lignes de face ("f ..."). Un .obj peut melanger des
     * faces triangulaires et des polygones a plus de 3 sommets (quads, etc.) - chaque face a N
     * sommets correspond a N-2 triangles une fois triangulee (triangulation en eventail, la plus
     * courante), donc le compte final est une ESTIMATION du nombre de triangles APRES
     * triangulation, pas un simple compte de lignes "f". Lecture ligne par ligne (pas tout charger
     * en memoire d'un coup) pour rester leger, puisque c'est justement les gros fichiers que ce
     * compteur sert a detecter.
     */
    private fun obtenirNombreTrianglesObj(octets: ByteArray): Int? {
        var total = 0L
        BufferedReader(InputStreamReader(ByteArrayInputStream(octets), Charsets.UTF_8)).use { lecteur ->
            var ligne = lecteur.readLine()
            while (ligne != null) {
                val l = ligne.trimStart()
                if (l.length >= 3 && l[0] == 'f' && (l[1] == ' ' || l[1] == '\t')) {
                    val sommets = l.substring(1).trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
                    if (sommets.size >= 3) total += (sommets.size - 2)
                }
                ligne = lecteur.readLine()
            }
        }
        if (total <= 0) return null
        if (total > Int.MAX_VALUE) return Int.MAX_VALUE
        return total.toInt()
    }
}
