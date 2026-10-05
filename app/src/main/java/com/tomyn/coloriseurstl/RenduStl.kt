package com.tomyn.coloriseurstl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Rendu STL fait maison : lit le fichier (binaire ou ASCII), projette en vue isometrique fixe,
 * ombrage simple par triangle, algorithme du peintre pour l'occultation. Portage direct de la
 * version PowerShell/C# du projet "Coloriser-STL" (Windows), deja validee en conditions reelles
 * sur de vrais modeles telecharges - meme mathematique, juste traduite vers android.graphics.
 *
 * Pas de vraie camera 3D interactive, juste une miniature statique - suffisant pour un apercu
 * en galerie.
 */
object RenduStl {

    private data class Triangle(val a: FloatArray, val b: FloatArray, val c: FloatArray)

    // Limite tres haute : un allegement naif (un triangle sur N dans l'ordre du fichier plutot
    // que par zone de la surface) laisse des trous un peu partout plutot qu'une vraie silhouette
    // pleine - observe en conditions reelles sur la version Windows. Mieux vaut un rendu un peu
    // plus lent mais complet.
    private const val MAX_TRIANGLES = 300_000

    /** @param octets contenu brut du fichier STL (deja lu, peu importe la source : SAF, fichier local...) */
    fun rendreMiniature(octets: ByteArray, taillePixels: Int): Bitmap? {
        var triangles = charger(octets) ?: return null
        if (triangles.isEmpty()) return null

        if (triangles.size > MAX_TRIANGLES) {
            val pas = triangles.size.toDouble() / MAX_TRIANGLES
            val reduit = ArrayList<Triangle>(MAX_TRIANGLES)
            var i = 0.0
            while (i < triangles.size) {
                reduit.add(triangles[i.toInt()])
                i += pas
            }
            triangles = reduit
        }

        var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE; var minZ = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE; var maxZ = -Float.MAX_VALUE
        for (t in triangles) {
            for (p in arrayOf(t.a, t.b, t.c)) {
                if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0]
                if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1]
                if (p[2] < minZ) minZ = p[2]; if (p[2] > maxZ) maxZ = p[2]
            }
        }
        val centreX = (minX + maxX) / 2f
        val centreY = (minY + maxY) / 2f
        val centreZ = (minZ + maxZ) / 2f

        val angleX = Math.toRadians(35.264)
        val angleY = Math.toRadians(45.0)
        val cosX = cos(angleX); val sinX = sin(angleX)
        val cosY = cos(angleY); val sinY = sin(angleY)

        fun transformer(p: FloatArray): DoubleArray {
            val x = (p[0] - centreX).toDouble()
            val y = (p[1] - centreY).toDouble()
            val z = (p[2] - centreZ).toDouble()
            val x1 = x * cosY + z * sinY
            val z1 = -x * sinY + z * cosY
            val y2 = y * cosX - z1 * sinX
            val z2 = y * sinX + z1 * cosX
            return doubleArrayOf(x1, y2, z2)
        }

        fun normaliser(v: DoubleArray): DoubleArray {
            val longueur = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
            if (longueur < 1e-9) return doubleArrayOf(0.0, 0.0, 1.0)
            return doubleArrayOf(v[0] / longueur, v[1] / longueur, v[2] / longueur)
        }

        // L'echelle doit se baser sur l'etendue APRES rotation (projetee a l'ecran), pas sur la
        // boite englobante brute avant rotation : pour un cube par exemple, la diagonale projetee
        // en vue isometrique depasse largement la plus grande arete, ce qui coupait les coins du
        // rendu (jusqu'a ~19% hors cadre mesure sur un cube de test). Premiere passe de projection
        // uniquement pour mesurer l'etendue reelle a l'ecran, avant de fixer l'echelle definitive.
        var etenduProjeteeX = 0.0
        var etenduProjeteeY = 0.0
        for (t in triangles) {
            for (p in arrayOf(t.a, t.b, t.c)) {
                val proj = transformer(p)
                if (abs(proj[0]) * 2 > etenduProjeteeX) etenduProjeteeX = abs(proj[0]) * 2
                if (abs(proj[1]) * 2 > etenduProjeteeY) etenduProjeteeY = abs(proj[1]) * 2
            }
        }
        var etendue = max(etenduProjeteeX, etenduProjeteeY)
        if (etendue <= 0.0) etendue = 1.0

        val echelle = (taillePixels * 0.85) / etendue
        val lumiere = normaliser(doubleArrayOf(0.4, 0.6, 0.7))

        data class TriangleProjete(val chemin: Path, val profondeur: Double, val intensite: Double)

        val projetes = ArrayList<TriangleProjete>(triangles.size)
        for (t in triangles) {
            val pa = transformer(t.a)
            val pb = transformer(t.b)
            val pc = transformer(t.c)

            val u = doubleArrayOf(pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
            val v = doubleArrayOf(pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
            val normale = normaliser(doubleArrayOf(
                u[1] * v[2] - u[2] * v[1],
                u[2] * v[0] - u[0] * v[2],
                u[0] * v[1] - u[1] * v[0]
            ))
            val intensite = max(0.15, abs(normale[0] * lumiere[0] + normale[1] * lumiere[1] + normale[2] * lumiere[2]))

            val demi = taillePixels / 2.0
            val x1 = (demi + pa[0] * echelle).toFloat(); val y1 = (demi - pa[1] * echelle).toFloat()
            val x2 = (demi + pb[0] * echelle).toFloat(); val y2v = (demi - pb[1] * echelle).toFloat()
            val x3 = (demi + pc[0] * echelle).toFloat(); val y3 = (demi - pc[1] * echelle).toFloat()

            val chemin = Path()
            chemin.moveTo(x1, y1)
            chemin.lineTo(x2, y2v)
            chemin.lineTo(x3, y3)
            chemin.close()

            projetes.add(TriangleProjete(chemin, (pa[2] + pb[2] + pc[2]) / 3.0, intensite))
        }

        projetes.sortBy { it.profondeur }

        val bmp = Bitmap.createBitmap(taillePixels, taillePixels, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.style = Paint.Style.FILL

        for (tp in projetes) {
            val niveau = min(235.0, max(40.0, 90.0 + tp.intensite * 140.0)).toInt()
            paint.color = Color.rgb((niveau * 0.55).toInt(), (niveau * 0.65).toInt(), niveau)
            canvas.drawPath(tp.chemin, paint)
        }

        return bmp
    }

    private fun lireTout(flux: InputStream): ByteArray {
        val tampon = ByteArrayOutputStream()
        val bloc = ByteArray(16384)
        var n: Int
        while (flux.read(bloc).also { n = it } != -1) tampon.write(bloc, 0, n)
        return tampon.toByteArray()
    }

    fun rendreMiniatureDepuisFlux(flux: InputStream, taillePixels: Int): Bitmap? =
        rendreMiniature(lireTout(flux), taillePixels)

    private fun charger(octets: ByteArray): List<Triangle>? {
        if (octets.size >= 84) {
            val buffer = ByteBuffer.wrap(octets).order(ByteOrder.LITTLE_ENDIAN)
            val nbTriangles = buffer.getInt(80)
            val tailleAttendue = 84L + nbTriangles.toLong() * 50L
            if (nbTriangles > 0 && tailleAttendue == octets.size.toLong()) {
                return chargerBinaire(buffer, nbTriangles)
            }
        }
        return chargerAscii(octets)
    }

    private fun chargerBinaire(buffer: ByteBuffer, nbTriangles: Int): List<Triangle> {
        val liste = ArrayList<Triangle>(nbTriangles)
        var position = 84
        repeat(nbTriangles) {
            position += 12 // normale stockee dans le fichier, ignoree (recalculee depuis les sommets)
            val a = lireVecteur(buffer, position); position += 12
            val b = lireVecteur(buffer, position); position += 12
            val c = lireVecteur(buffer, position); position += 12
            position += 2 // attribut
            liste.add(Triangle(a, b, c))
        }
        return liste
    }

    private fun lireVecteur(buffer: ByteBuffer, position: Int): FloatArray =
        floatArrayOf(buffer.getFloat(position), buffer.getFloat(position + 4), buffer.getFloat(position + 8))

    private fun chargerAscii(octets: ByteArray): List<Triangle> {
        val liste = ArrayList<Triangle>()
        val sommetsCourants = ArrayList<FloatArray>()
        val texte = String(octets, Charsets.US_ASCII)
        for (ligneBrute in texte.lineSequence()) {
            val ligne = ligneBrute.trim()
            if (ligne.startsWith("vertex", ignoreCase = true)) {
                val parties = ligne.split(Regex("\\s+")).filter { it.isNotEmpty() }
                if (parties.size >= 4) {
                    try {
                        val x = parties[1].toFloat()
                        val y = parties[2].toFloat()
                        val z = parties[3].toFloat()
                        sommetsCourants.add(floatArrayOf(x, y, z))
                    } catch (e: NumberFormatException) { /* ligne mal formee : ignoree */ }
                }
            } else if (ligne.startsWith("endfacet", ignoreCase = true)) {
                if (sommetsCourants.size == 3) {
                    liste.add(Triangle(sommetsCourants[0], sommetsCourants[1], sommetsCourants[2]))
                }
                sommetsCourants.clear()
            }
        }
        return liste
    }
}
