package com.tomyn.coloriseurstl

import org.w3c.dom.Document
import org.w3c.dom.Element
import org.w3c.dom.Node
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Conversion .3mf -> .stl binaire, portee depuis la version Windows (20/10/2026, Tomyn :
 * "j'ai plusieurs 3MF non colorises que je voudrais coloriser") - l'API Meshy n'accepte en entree
 * que .glb/.gltf/.obj/.fbx/.stl (le .3mf n'y figure que comme format de SORTIE, jamais comme
 * entree), donc extraction du maillage directement depuis le .3mf (un ZIP contenant un XML au
 * format "3D Manufacturing Format") et reexport en .stl binaire, traite ensuite exactement comme
 * n'importe quel autre .stl par le reste du pipeline.
 *
 * Portee volontairement limitee a un .3mf "simple" (meme perimetre que la version Windows) : un
 * seul niveau de <components> est resolu recursivement (le format permet d'imbriquer
 * indefiniment, mais les .3mf rencontres ici ne le font pas), et SEUL le maillage geometrique est
 * repris - aucune couleur/texture n'est lue depuis le .3mf meme s'il y en avait (hors sujet : le
 * but de l'appli est de (re)generer des couleurs avec l'IA, pas de preserver celles d'un .3mf deja
 * colorise differemment).
 *
 * Gere l'Extension de Production 3MF (un <component> peut pointer, via un attribut "path", vers
 * un AUTRE fichier XML interne au zip qui contient le vrai <object> - layout standard produit par
 * Bambu Studio/Orca Slicer/PrusaSlicer pour les .3mf a gros maillage), meme cas reel rencontre
 * cote Windows ("aucun maillage exploitable trouve" avant ce correctif).
 *
 * N'utilise que javax.xml/java.util.zip/java.io (aucune API Android) - verifiable avec un vrai
 * JDK/kotlinc, pas seulement par compilation contre des stubs.
 */
object Convertisseur3MF {

    class Erreur3MF(message: String) : Exception(message)

    data class Resultat3MF(val octetsStl: ByteArray, val nbTriangles: Int, val nbObjets: Int)

    private data class Sommet(val x: Double, val y: Double, val z: Double)
    private data class Triangle(val v1: Int, val v2: Int, val v3: Int)
    private data class Composant(val objectId: String, val transform: String?, val chemin: String?)
    private class DocumentAnalyse {
        val maillages = mutableMapOf<String, Pair<MutableList<Sommet>, MutableList<Triangle>>>()
        val composants = mutableMapOf<String, MutableList<Composant>>()
    }

    private val IDENTITE = doubleArrayOf(
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    )

    fun convertirVersStl(octets3mf: ByteArray, nomFichier: String): Resultat3MF {
        val entrees = litEntreesZip(octets3mf)
        val cheminModele = entrees.keys.firstOrNull { it.endsWith("3dmodel.model", ignoreCase = true) }
            ?: throw Erreur3MF("aucun '3dmodel.model' trouve dans ce .3mf (fichier corrompu ou pas un vrai .3mf ?)")

        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val documentsCharges = mutableMapOf<String, DocumentAnalyse>()

        fun chargerXml(bytes: ByteArray): Document =
            factory.newDocumentBuilder().parse(ByteArrayInputStream(bytes))

        fun enfantDirectParNomLocal(parent: Element, nomLocal: String): Element? {
            val enfants = parent.childNodes
            for (i in 0 until enfants.length) {
                val n = enfants.item(i)
                if (n.nodeType == Node.ELEMENT_NODE && (n as Element).localName == nomLocal) return n
            }
            return null
        }

        fun analyserDocument(doc: Document): DocumentAnalyse {
            val resultat = DocumentAnalyse()
            val objets = doc.getElementsByTagNameNS("*", "object")
            for (i in 0 until objets.length) {
                val noeudObjet = objets.item(i) as? Element ?: continue
                val id = noeudObjet.getAttribute("id")
                if (id.isNullOrEmpty()) continue
                val mesh = enfantDirectParNomLocal(noeudObjet, "mesh")
                if (mesh != null) {
                    val sommets = mutableListOf<Sommet>()
                    val vertices = mesh.getElementsByTagNameNS("*", "vertex")
                    for (v in 0 until vertices.length) {
                        val ve = vertices.item(v) as Element
                        sommets.add(
                            Sommet(
                                ve.getAttribute("x").toDouble(),
                                ve.getAttribute("y").toDouble(),
                                ve.getAttribute("z").toDouble()
                            )
                        )
                    }
                    val triangles = mutableListOf<Triangle>()
                    val tris = mesh.getElementsByTagNameNS("*", "triangle")
                    for (t in 0 until tris.length) {
                        val te = tris.item(t) as Element
                        triangles.add(
                            Triangle(
                                te.getAttribute("v1").toInt(),
                                te.getAttribute("v2").toInt(),
                                te.getAttribute("v3").toInt()
                            )
                        )
                    }
                    resultat.maillages[id] = Pair(sommets, triangles)
                    continue
                }
                val composantsNoeud = enfantDirectParNomLocal(noeudObjet, "components")
                if (composantsNoeud != null) {
                    val liste = mutableListOf<Composant>()
                    val comps = composantsNoeud.getElementsByTagNameNS("*", "component")
                    for (c in 0 until comps.length) {
                        val ce = comps.item(c) as Element
                        val attrs = ce.attributes
                        var chemin: String? = null
                        for (a in 0 until attrs.length) {
                            val attr = attrs.item(a)
                            if (attr.localName == "path") {
                                chemin = attr.nodeValue
                                break
                            }
                        }
                        liste.add(
                            Composant(
                                ce.getAttribute("objectid"),
                                ce.getAttribute("transform").ifEmpty { null },
                                chemin
                            )
                        )
                    }
                    resultat.composants[id] = liste
                }
            }
            return resultat
        }

        fun obtenirDocument(chemin: String): DocumentAnalyse {
            val cheminNormalise = chemin.trimStart('/')
            documentsCharges[cheminNormalise]?.let { return it }
            // Recherche exacte, puis insensible a la casse (certains exporteurs sont approximatifs
            // sur la casse des chemins internes au zip).
            val bytes = entrees[cheminNormalise]
                ?: entrees.entries.firstOrNull { it.key.equals(cheminNormalise, ignoreCase = true) }?.value
            if (bytes == null) {
                val vide = DocumentAnalyse()
                documentsCharges[cheminNormalise] = vide
                return vide
            }
            val document = analyserDocument(chargerXml(bytes))
            documentsCharges[cheminNormalise] = document
            return document
        }

        val xmlRacine = chargerXml(entrees.getValue(cheminModele))
        val documentRacine = analyserDocument(xmlRacine)
        documentsCharges[cheminModele.trimStart('/')] = documentRacine

        fun analyserTransform(texte: String?): DoubleArray {
            if (texte.isNullOrBlank()) return IDENTITE
            val n = texte.trim().split(Regex("\\s+")).map { it.toDouble() }
            if (n.size != 12) return IDENTITE
            return doubleArrayOf(
                n[0], n[1], n[2], 0.0,
                n[3], n[4], n[5], 0.0,
                n[6], n[7], n[8], 0.0,
                n[9], n[10], n[11], 1.0
            )
        }

        fun multiplierTransform(a: DoubleArray, b: DoubleArray): DoubleArray {
            val r = DoubleArray(16)
            for (ligne in 0 until 4) {
                for (col in 0 until 4) {
                    var somme = 0.0
                    for (k in 0 until 4) somme += a[ligne * 4 + k] * b[k * 4 + col]
                    r[ligne * 4 + col] = somme
                }
            }
            return r
        }

        fun appliquerTransform(p: Sommet, m: DoubleArray): Sommet = Sommet(
            p.x * m[0] + p.y * m[4] + p.z * m[8] + m[12],
            p.x * m[1] + p.y * m[5] + p.z * m[9] + m[13],
            p.x * m[2] + p.y * m[6] + p.z * m[10] + m[14]
        )

        val sommetsGlobaux = mutableListOf<Sommet>()
        val trianglesGlobaux = mutableListOf<Triangle>()
        val profondeurMax = 8 // garde-fou anti-boucle (composants qui se referencent entre eux)

        fun resoudreObjet(id: String, transformCumule: DoubleArray, profondeur: Int, documentActuel: DocumentAnalyse) {
            if (profondeur > profondeurMax) return
            val maillage = documentActuel.maillages[id]
            if (maillage != null) {
                val decalage = sommetsGlobaux.size
                for (s in maillage.first) sommetsGlobaux.add(appliquerTransform(s, transformCumule))
                for (t in maillage.second) {
                    trianglesGlobaux.add(Triangle(t.v1 + decalage, t.v2 + decalage, t.v3 + decalage))
                }
                return
            }
            val composants = documentActuel.composants[id] ?: return
            for (comp in composants) {
                val transformComposant = analyserTransform(comp.transform)
                val cumul = multiplierTransform(transformComposant, transformCumule)
                if (comp.chemin != null) {
                    // Reference vers un AUTRE fichier XML du zip (extension de Production) :
                    // l'objectid se resout dans CE document externe, pas dans le document actuel.
                    val documentCible = obtenirDocument(comp.chemin)
                    resoudreObjet(comp.objectId, cumul, profondeur + 1, documentCible)
                } else {
                    resoudreObjet(comp.objectId, cumul, profondeur + 1, documentActuel)
                }
            }
            // id inconnu (reference cassee) : ignore silencieusement, pas bloquant pour le reste.
        }

        val itemsBuild = xmlRacine.getElementsByTagNameNS("*", "item")
        if (itemsBuild.length > 0) {
            for (i in 0 until itemsBuild.length) {
                val item = itemsBuild.item(i) as Element
                val t = analyserTransform(item.getAttribute("transform").ifEmpty { null })
                resoudreObjet(item.getAttribute("objectid"), t, 0, documentRacine)
            }
        } else {
            // Pas de section <build> (ou vide) : rare, mais plutot que d'echouer completement, on
            // reprend tous les objets a maillage direct tels quels (sans transform).
            for (id in documentRacine.maillages.keys) resoudreObjet(id, IDENTITE, 0, documentRacine)
        }

        if (trianglesGlobaux.isEmpty()) {
            throw Erreur3MF("aucun maillage exploitable trouve dans ce .3mf (section <build> vide et aucun objet a maillage direct)")
        }

        val octetsStl = ecrireStlBinaire(nomFichier, sommetsGlobaux, trianglesGlobaux)

        // Nombre d'objets a maillage direct, tous documents confondus (racine + parties externes
        // chargees via l'extension de Production) - juste indicatif pour le journal.
        val nbObjetsTotal = documentsCharges.values.sumOf { it.maillages.size }
        return Resultat3MF(octetsStl, trianglesGlobaux.size, nbObjetsTotal)
    }

    /**
     * Ecriture en .stl binaire : 80 octets d'entete + nb de triangles (uint32 LE) + par triangle,
     * normale (3 floats, calculee par produit vectoriel) + 3 sommets (3 floats chacun) + 2 octets
     * d'attribut (toujours 0). Little-endian explicite (DataOutputStream du JDK ecrit en
     * big-endian par defaut) - format standard, le meme que Bambu Studio et Meshy savent lire.
     */
    private fun ecrireStlBinaire(nomFichier: String, sommets: List<Sommet>, triangles: List<Triangle>): ByteArray {
        val sortie = ByteArrayOutputStream()
        val entete = ByteArray(80)
        val texteEntete = "Converti depuis $nomFichier par Coloriser-STL".toByteArray(Charsets.US_ASCII)
        System.arraycopy(texteEntete, 0, entete, 0, minOf(texteEntete.size, 80))
        sortie.write(entete)
        sortie.write(uint32LE(triangles.size))
        for (tri in triangles) {
            val p1 = sommets[tri.v1]; val p2 = sommets[tri.v2]; val p3 = sommets[tri.v3]
            val ux = p2.x - p1.x; val uy = p2.y - p1.y; val uz = p2.z - p1.z
            val vx = p3.x - p1.x; val vy = p3.y - p1.y; val vz = p3.z - p1.z
            var nx = uy * vz - uz * vy
            var ny = uz * vx - ux * vz
            var nz = ux * vy - uy * vx
            val norme = Math.sqrt(nx * nx + ny * ny + nz * nz)
            if (norme > 0) { nx /= norme; ny /= norme; nz /= norme }
            sortie.write(floatLE(nx.toFloat()))
            sortie.write(floatLE(ny.toFloat()))
            sortie.write(floatLE(nz.toFloat()))
            for (p in listOf(p1, p2, p3)) {
                sortie.write(floatLE(p.x.toFloat()))
                sortie.write(floatLE(p.y.toFloat()))
                sortie.write(floatLE(p.z.toFloat()))
            }
            sortie.write(byteArrayOf(0, 0))
        }
        return sortie.toByteArray()
    }

    private fun uint32LE(v: Int): ByteArray = byteArrayOf(
        (v and 0xFF).toByte(),
        ((v shr 8) and 0xFF).toByte(),
        ((v shr 16) and 0xFF).toByte(),
        ((v shr 24) and 0xFF).toByte()
    )

    private fun floatLE(f: Float): ByteArray = uint32LE(java.lang.Float.floatToIntBits(f))

    /** Lit toutes les entrees (non-dossiers) d'un ZIP en memoire : chemin interne -> octets. */
    private fun litEntreesZip(octets: ByteArray): Map<String, ByteArray> {
        val entrees = mutableMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(octets)).use { zis ->
            var entree = zis.nextEntry
            while (entree != null) {
                if (!entree.isDirectory) {
                    entrees[entree.name] = zis.readBytes()
                }
                zis.closeEntry()
                entree = zis.nextEntry
            }
        }
        return entrees
    }
}
