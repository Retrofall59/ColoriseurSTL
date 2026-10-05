import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

// Reproduction EXACTE de la logique de parsing de RenduStl.kt (charger/chargerBinaire/chargerAscii),
// sans aucune dependance android.graphics, pour pouvoir reellement executer le test (contrairement
// au rendu Canvas, qui n'est qu'un stub de declaration dans android.jar hors d'un vrai appareil).
data class Triangle(val a: FloatArray, val b: FloatArray, val c: FloatArray)

fun lireVecteur(buffer: ByteBuffer, position: Int): FloatArray =
    floatArrayOf(buffer.getFloat(position), buffer.getFloat(position + 4), buffer.getFloat(position + 8))

fun chargerBinaire(buffer: ByteBuffer, nbTriangles: Int): List<Triangle> {
    val liste = ArrayList<Triangle>(nbTriangles)
    var position = 84
    repeat(nbTriangles) {
        position += 12
        val a = lireVecteur(buffer, position); position += 12
        val b = lireVecteur(buffer, position); position += 12
        val c = lireVecteur(buffer, position); position += 12
        position += 2
        liste.add(Triangle(a, b, c))
    }
    return liste
}

fun charger(octets: ByteArray): List<Triangle>? {
    if (octets.size >= 84) {
        val buffer = ByteBuffer.wrap(octets).order(ByteOrder.LITTLE_ENDIAN)
        val nbTriangles = buffer.getInt(80)
        val tailleAttendue = 84L + nbTriangles.toLong() * 50L
        if (nbTriangles > 0 && tailleAttendue == octets.size.toLong()) {
            return chargerBinaire(buffer, nbTriangles)
        }
    }
    return null
}

fun main() {
    val octets = File("cube_test.stl").readBytes()
    val triangles = charger(octets)
    println("Fichier : ${octets.size} octets")
    println("Triangles charges : ${triangles?.size}")

    if (triangles == null || triangles.size != 12) {
        println("ECHEC : attendu 12 triangles")
        System.exit(1)
        return
    }

    // Verifie la boite englobante : le cube fait 10x10x10, centre sur l'origine (-5 a +5)
    var minX = Float.MAX_VALUE; var maxX = -Float.MAX_VALUE
    var minY = Float.MAX_VALUE; var maxY = -Float.MAX_VALUE
    var minZ = Float.MAX_VALUE; var maxZ = -Float.MAX_VALUE
    for (t in triangles) {
        for (p in arrayOf(t.a, t.b, t.c)) {
            if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0]
            if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1]
            if (p[2] < minZ) minZ = p[2]; if (p[2] > maxZ) maxZ = p[2]
        }
    }
    println("Boite englobante : X[$minX,$maxX] Y[$minY,$maxY] Z[$minZ,$maxZ]")

    val ok = minX == -5f && maxX == 5f && minY == -5f && maxY == 5f && minZ == -5f && maxZ == 5f
    println(if (ok) "=> TOUT PASSE (boite englobante exacte attendue)" else "=> ECHEC boite englobante")
    if (!ok) System.exit(1)
}
