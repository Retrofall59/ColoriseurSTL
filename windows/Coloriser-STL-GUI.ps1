<#
.SYNOPSIS
    Interface graphique pour coloriser un dossier de STL en lot via l'API Meshy, avec galerie
    de vraies miniatures (rendu STL fait maison + apercu fourni par Meshy pour les resultats).

.DESCRIPTION
    PAS TESTE PAR CLAUDE (ni la logique API, ni l'interface graphique, ni le rendu 3D) : aucun
    environnement Windows/PowerShell disponible pour executer ce script. Le rendu STL (lecture
    du format binaire/ASCII, projection, ombrage) est la partie la plus a risque de tout ce
    projet - relu tres attentivement, mais sans aucune verification par execution reelle.

    Premiere version de cette appli : s'appuyait sur le systeme de miniatures de Windows
    (Visionneuse 3D). Abandonne : cette appli a ete retiree du Microsoft Store par Microsoft en
    2026 et n'etait de toute facon pas preinstallee sur Windows 11 - aucune miniature 3D n'etait
    disponible sur la machine de test. Le rendu est donc fait directement par ce script, qui ne
    depend plus d'aucune application tierce.

    Lancer de preference via Lancer-Coloriser-STL.vbs (aucune fenetre de console).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Necessaire pour extraire le ZIP que Tripo renvoie desormais (voir Coloriser-UnFichierTripo) -
# System.IO.Compression.FileSystem fournit [System.IO.Compression.ZipFile], pas charge par defaut.
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Date de cette version locale, a comparer avec la date du dernier commit sur GitHub (voir
# Verifier-MiseAJourDisponible plus bas) - 16/10/2026, idee d'amelioration validee "tu peux toutes
# les faire". A METTRE A JOUR MANUELLEMENT a chaque nouvelle session de modifications (c'est le
# seul moyen simple de savoir si "cette copie-ci" est a jour sans dependre du SHA exact du commit,
# qu'on ne connait pas encore au moment d'ecrire le script).
$script:VERSION_BUILD_COLORISER = [DateTime]::new(2026, 10, 22, 9, 45, 0)

# --- Rendu STL maison : lit le fichier (binaire ou ASCII), projette en vue isometrique fixe,
# ombrage simple par triangle, algorithme du peintre pour l'occultation. Pas de vraie camera 3D
# interactive, juste une miniature statique - suffisant pour un apercu en liste. ---
$codeRendu = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;

public static class RenduSTL
{
    private struct Triangle { public float[] A, B, C; }

    public static Bitmap RendreMiniature(string cheminFichier, int taillePixels)
    {
        List<Triangle> triangles = Charger(cheminFichier);
        if (triangles == null || triangles.Count == 0) return null;

        // Boite englobante calculee AVANT toute reduction (necessaire pour la grille spatiale
        // ci-dessous, et de toute facon utile pour le centrage/l'echelle qui suivent).
        float minX = float.MaxValue, minY = float.MaxValue, minZ = float.MaxValue;
        float maxX = float.MinValue, maxY = float.MinValue, maxZ = float.MinValue;
        foreach (Triangle t in triangles)
        {
            float[][] sommets = new float[][] { t.A, t.B, t.C };
            foreach (float[] p in sommets)
            {
                if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0];
                if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1];
                if (p[2] < minZ) minZ = p[2]; if (p[2] > maxZ) maxZ = p[2];
            }
        }
        float centreX = (minX + maxX) / 2f, centreY = (minY + maxY) / 2f, centreZ = (minZ + maxZ) / 2f;
        float etendue = Math.Max(maxX - minX, Math.Max(maxY - minY, maxZ - minZ));
        if (etendue <= 0) etendue = 1f;

        // Plafond releve tres haut (teste en conditions reelles : un maillage de pres de 2
        // millions de triangles s'est rendu en entier en 14,6 secondes, parfaitement plein) - au-
        // dela, grille spatiale plutot que l'ancienne methode "un triangle sur N dans l'ordre du
        // fichier", qui laissait des trous partout (aspect nuage de points) car des triangles
        // voisins sur la surface ne sont pas forcement voisins dans le fichier.
        const int MaxTriangles = 5000000;
        if (triangles.Count > MaxTriangles)
        {
            const int tailleGrille = 24;
            float etendueX = Math.Max(maxX - minX, 0.0001f);
            float etendueY = Math.Max(maxY - minY, 0.0001f);
            float etendueZ = Math.Max(maxZ - minZ, 0.0001f);

            Dictionary<int, List<Triangle>> cases = new Dictionary<int, List<Triangle>>();
            foreach (Triangle t in triangles)
            {
                float cx = (t.A[0] + t.B[0] + t.C[0]) / 3f;
                float cy = (t.A[1] + t.B[1] + t.C[1]) / 3f;
                float cz = (t.A[2] + t.B[2] + t.C[2]) / 3f;
                int gx = (int)(((cx - minX) / etendueX) * (tailleGrille - 1));
                int gy = (int)(((cy - minY) / etendueY) * (tailleGrille - 1));
                int gz = (int)(((cz - minZ) / etendueZ) * (tailleGrille - 1));
                int cle = gx + gy * tailleGrille + gz * tailleGrille * tailleGrille;
                List<Triangle> liste;
                if (!cases.TryGetValue(cle, out liste)) { liste = new List<Triangle>(); cases[cle] = liste; }
                liste.Add(t);
            }

            List<List<Triangle>> groupes = new List<List<Triangle>>(cases.Values);
            List<Triangle> reduit = new List<Triangle>(MaxTriangles);
            int[] indexParGroupe = new int[groupes.Count];
            bool resteDesTriangles = true;
            while (reduit.Count < MaxTriangles && resteDesTriangles)
            {
                resteDesTriangles = false;
                for (int g = 0; g < groupes.Count && reduit.Count < MaxTriangles; g++)
                {
                    if (indexParGroupe[g] < groupes[g].Count)
                    {
                        reduit.Add(groupes[g][indexParGroupe[g]]);
                        indexParGroupe[g]++;
                        if (indexParGroupe[g] < groupes[g].Count) resteDesTriangles = true;
                    }
                }
            }
            triangles = reduit;
        }

        double angleX = 35.264 * Math.PI / 180.0;
        double angleY = 45.0 * Math.PI / 180.0;
        double cosX = Math.Cos(angleX), sinX = Math.Sin(angleX);
        double cosY = Math.Cos(angleY), sinY = Math.Sin(angleY);

        Func<float[], double[]> transformer = delegate(float[] p)
        {
            double x = p[0] - centreX, y = p[1] - centreY, z = p[2] - centreZ;
            double x1 = x * cosY + z * sinY;
            double z1 = -x * sinY + z * cosY;
            double y2 = y * cosX - z1 * sinX;
            double z2 = y * sinX + z1 * cosX;
            return new double[] { x1, y2, z2 };
        };

        double echelle = (taillePixels * 0.85) / etendue;
        double[] lumiere = Normaliser(new double[] { 0.4, 0.6, 0.7 });

        List<PointF[]> polygones = new List<PointF[]>();
        List<double> profondeurs = new List<double>();
        List<double> intensites = new List<double>();

        foreach (Triangle t in triangles)
        {
            double[] pa = transformer(t.A);
            double[] pb = transformer(t.B);
            double[] pc = transformer(t.C);

            double[] u = new double[] { pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2] };
            double[] v = new double[] { pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2] };
            double[] normale = Normaliser(new double[] {
                u[1]*v[2] - u[2]*v[1],
                u[2]*v[0] - u[0]*v[2],
                u[0]*v[1] - u[1]*v[0]
            });

            double intensite = Math.Max(0.15, Math.Abs(
                normale[0]*lumiere[0] + normale[1]*lumiere[1] + normale[2]*lumiere[2]));

            PointF p1 = new PointF((float)(taillePixels/2.0 + pa[0]*echelle), (float)(taillePixels/2.0 - pa[1]*echelle));
            PointF p2 = new PointF((float)(taillePixels/2.0 + pb[0]*echelle), (float)(taillePixels/2.0 - pb[1]*echelle));
            PointF p3 = new PointF((float)(taillePixels/2.0 + pc[0]*echelle), (float)(taillePixels/2.0 - pc[1]*echelle));

            polygones.Add(new PointF[] { p1, p2, p3 });
            profondeurs.Add((pa[2] + pb[2] + pc[2]) / 3.0);
            intensites.Add(intensite);
        }

        int[] ordre = new int[polygones.Count];
        for (int i = 0; i < ordre.Length; i++) ordre[i] = i;
        Array.Sort(ordre, delegate(int a, int b) { return profondeurs[a].CompareTo(profondeurs[b]); });

        Bitmap bmp = new Bitmap(taillePixels, taillePixels);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.White);
            foreach (int i in ordre)
            {
                int niveau = (int)(90 + intensites[i] * 140);
                niveau = Math.Min(235, Math.Max(40, niveau));
                Color couleur = Color.FromArgb((int)(niveau * 0.55), (int)(niveau * 0.65), niveau);
                using (SolidBrush brosse = new SolidBrush(couleur))
                {
                    g.FillPolygon(brosse, polygones[i]);
                }
            }
        }
        return bmp;
    }

    private static double[] Normaliser(double[] v)
    {
        double longueur = Math.Sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
        if (longueur < 1e-9) return new double[] { 0, 0, 1 };
        return new double[] { v[0]/longueur, v[1]/longueur, v[2]/longueur };
    }

    // Dispatch explicite par extension plutot que de deviner : .fbx/.glb/.gltf renvoient null
    // immediatement (pas de tentative de parsing - formats trop complexes pour un rendu maison
    // fiable, l'appelant affiche alors l'image de remplacement). Le fichier est quand meme
    // envoye a Meshy normalement, seul l'apercu local avant traitement est absent dans ce cas.
    private static List<Triangle> Charger(string chemin)
    {
        string extension = Path.GetExtension(chemin).ToLowerInvariant();
        if (extension == ".obj") return ChargerObj(chemin);
        if (extension != ".stl") return null;

        byte[] octets = File.ReadAllBytes(chemin);
        if (octets.Length >= 84)
        {
            int nbTriangles = BitConverter.ToInt32(octets, 80);
            long tailleAttendue = 84L + (long)nbTriangles * 50L;
            if (nbTriangles > 0 && tailleAttendue == octets.Length)
            {
                return ChargerBinaire(octets, nbTriangles);
            }
        }
        return ChargerAscii(chemin);
    }

    // Format OBJ : texte simple, sommets ("v x y z") et faces ("f a b c", eventuellement
    // "a/b/c" avec indices texture/normale ignores, ou plus de 3 sommets - triangulation en
    // eventail). Indices 1-bases ; un indice negatif signifie "depuis la fin" (rare mais prevu
    // par le format).
    private static List<Triangle> ChargerObj(string chemin)
    {
        List<float[]> sommets = new List<float[]>();
        List<Triangle> triangles = new List<Triangle>();

        foreach (string ligneBrute in File.ReadLines(chemin))
        {
            string ligne = ligneBrute.Trim();
            if (ligne.StartsWith("v ") || ligne.StartsWith("v\t"))
            {
                string[] parties = ligne.Substring(1).Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                if (parties.Length >= 3)
                {
                    float x = float.Parse(parties[0], CultureInfo.InvariantCulture);
                    float y = float.Parse(parties[1], CultureInfo.InvariantCulture);
                    float z = float.Parse(parties[2], CultureInfo.InvariantCulture);
                    sommets.Add(new float[] { x, y, z });
                }
            }
            else if (ligne.StartsWith("f ") || ligne.StartsWith("f\t"))
            {
                string[] jetons = ligne.Substring(1).Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                List<float[]> sommetsFace = new List<float[]>();
                foreach (string jeton in jetons)
                {
                    string indiceTexte = jeton.Split('/')[0];
                    int indice;
                    if (!int.TryParse(indiceTexte, out indice)) continue;
                    int indiceReel = indice > 0 ? indice - 1 : sommets.Count + indice;
                    if (indiceReel >= 0 && indiceReel < sommets.Count) sommetsFace.Add(sommets[indiceReel]);
                }
                // Triangulation en eventail pour les faces a plus de 3 sommets (quads, etc.)
                for (int i = 1; i + 1 < sommetsFace.Count; i++)
                {
                    triangles.Add(new Triangle { A = sommetsFace[0], B = sommetsFace[i], C = sommetsFace[i + 1] });
                }
            }
        }
        return triangles;
    }

    private static List<Triangle> ChargerBinaire(byte[] octets, int nbTriangles)
    {
        List<Triangle> liste = new List<Triangle>(nbTriangles);
        int position = 84;
        for (int i = 0; i < nbTriangles; i++)
        {
            position += 12; // normale stockee dans le fichier, ignoree (recalculee depuis les sommets)
            float[] a = LireVecteur(octets, position); position += 12;
            float[] b = LireVecteur(octets, position); position += 12;
            float[] c = LireVecteur(octets, position); position += 12;
            position += 2; // attribut
            liste.Add(new Triangle { A = a, B = b, C = c });
        }
        return liste;
    }

    private static float[] LireVecteur(byte[] octets, int position)
    {
        return new float[] {
            BitConverter.ToSingle(octets, position),
            BitConverter.ToSingle(octets, position + 4),
            BitConverter.ToSingle(octets, position + 8)
        };
    }

    private static List<Triangle> ChargerAscii(string chemin)
    {
        List<Triangle> liste = new List<Triangle>();
        List<float[]> sommetsCourants = new List<float[]>();
        foreach (string ligneBrute in File.ReadLines(chemin))
        {
            string ligne = ligneBrute.Trim();
            if (ligne.StartsWith("vertex", StringComparison.OrdinalIgnoreCase))
            {
                string[] parties = ligne.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                if (parties.Length >= 4)
                {
                    float x = float.Parse(parties[1], CultureInfo.InvariantCulture);
                    float y = float.Parse(parties[2], CultureInfo.InvariantCulture);
                    float z = float.Parse(parties[3], CultureInfo.InvariantCulture);
                    sommetsCourants.Add(new float[] { x, y, z });
                }
            }
            else if (ligne.StartsWith("endfacet", StringComparison.OrdinalIgnoreCase))
            {
                if (sommetsCourants.Count == 3)
                {
                    liste.Add(new Triangle { A = sommetsCourants[0], B = sommetsCourants[1], C = sommetsCourants[2] });
                }
                sommetsCourants.Clear();
            }
        }
        return liste;
    }
}
'@
Add-Type -TypeDefinition $codeRendu -ReferencedAssemblies System.Drawing

function Obtenir-Miniature($cheminFichier, $taillePixels) {
    try {
        # Image -> STL (08/10/2026) : une image de depart est deja une image, pas la peine de
        # passer par le rendu STL maison (qui echouerait silencieusement dessus de toute facon) -
        # on l'affiche directement comme vignette.
        if ([System.IO.Path]::GetExtension($cheminFichier).ToLower() -in $EXTENSIONS_IMAGES) {
            return [System.Drawing.Image]::FromFile($cheminFichier)
        }
        return [RenduSTL]::RendreMiniature($cheminFichier, $taillePixels)
    } catch {
        return $null  # rendu impossible (fichier corrompu, format inattendu...) : image de remplacement
    }
}

# Nombre de triangles d'un .stl BINAIRE, lu directement dans son en-tete (octets 80-83, entier
# non signe sur 4 octets) - standard du format, pas besoin de parser toute la geometrie comme le
# fait RenduSTL pour l'apercu (15/10/2026, pour decider si une simplification automatique est
# utile avant envoi, voir $SEUIL_TRIANGLES_REMESH_AUTO plus haut). Verification croisee : la
# taille de fichier attendue pour ce nombre de triangles (84 + N*50 octets, format binaire STL)
# doit correspondre exactement a la taille reelle - sinon c'est tres probablement de l'ASCII (qui
# peut aussi commencer par n'importe quoi dans ses 80 premiers octets, donc ne pas se fier au
# header seul) ou un fichier corrompu, et on renvoie $null plutot que de risquer un faux resultat.
function Obtenir-NombreTrianglesSTL($cheminFichier) {
    try {
        if ([System.IO.Path]::GetExtension($cheminFichier).ToLower() -ne ".stl") { return $null }
        $octets = [System.IO.File]::ReadAllBytes($cheminFichier)
        if ($octets.Length -lt 84) { return $null }
        $nbTriangles = [BitConverter]::ToUInt32($octets, 80)
        $tailleAttendue = 84 + ([int64]$nbTriangles * 50)
        if ($tailleAttendue -eq $octets.Length) { return [int]$nbTriangles }
        return $null
    } catch {
        return $null
    }
}

# Nombre de triangles d'un .obj - contrairement au .stl binaire, l'en-tete .obj ne contient
# aucun compteur : il faut compter les lignes de face ("f ...") (16/10/2026, meme besoin que
# Obtenir-NombreTrianglesSTL ci-dessus mais pour le format accepte par Tripo/l'export "experimental
# .obj" de Meshy, non couvert jusqu'ici par la simplification automatique). Un .obj peut melanger
# des faces triangulaires et des polygones a plus de 3 sommets (quads, etc.) - chaque face a N
# sommets correspond a N-2 triangles une fois triangulee (triangulation en eventail, la plus
# courante), donc le compte final est une estimation du nombre de triangles APRES triangulation,
# pas un simple compte de lignes "f". Lecture ligne par ligne (pas ReadAllLines/ReadAllText) pour
# rester leger en memoire meme sur un gros fichier, puisque c'est justement les gros fichiers que
# ce compteur sert a detecter.
function Obtenir-NombreTrianglesOBJ($cheminFichier) {
    try {
        if ([System.IO.Path]::GetExtension($cheminFichier).ToLower() -ne ".obj") { return $null }
        $total = [int64]0
        $lecteur = [System.IO.File]::OpenText($cheminFichier)
        try {
            while (($ligne = $lecteur.ReadLine()) -ne $null) {
                $ligne = $ligne.TrimStart()
                if ($ligne.Length -lt 3 -or $ligne[0] -ne 'f' -or ($ligne[1] -ne ' ' -and $ligne[1] -ne "`t")) { continue }
                $sommets = @($ligne.Substring(1).Trim() -split '\s+' | Where-Object { $_ })
                if ($sommets.Count -ge 3) { $total += ($sommets.Count - 2) }
            }
        } finally {
            $lecteur.Close()
        }
        if ($total -le 0) { return $null }
        if ($total -gt [int]::MaxValue) { return [int]::MaxValue }
        return [int]$total
    } catch {
        return $null
    }
}

# Point d'entree unique pour la detection auto-remesh (16/10/2026) - choisit le bon compteur selon
# l'extension (.stl binaire ou .obj) sans que l'appelant ait besoin de savoir lequel utiliser.
# Renvoie $null pour toute autre extension (ASCII .stl, .3mf, images...) - pas de simplification
# automatique pour ces cas, exactement comme avant pour tout ce qui n'etait pas du .stl binaire.
function Obtenir-NombreTriangles($cheminFichier) {
    switch ([System.IO.Path]::GetExtension($cheminFichier).ToLower()) {
        ".stl" { return Obtenir-NombreTrianglesSTL $cheminFichier }
        ".obj" { return Obtenir-NombreTrianglesOBJ $cheminFichier }
        default { return $null }
    }
}

# 20/10/2026, Tomyn : "j'ai plusieurs 3MF non colorises que je voudrais coloriser" - l'API Meshy
# n'accepte en entree que .glb/.gltf/.obj/.fbx/.stl (verifie dans la doc officielle le 20/10/2026,
# le .3mf n'y figure que comme format de SORTIE sur certains endpoints, jamais comme entree). Donc
# plutot que de compter sur un changement cote Meshy, extraction du maillage directement depuis le
# .3mf (qui est un ZIP contenant un XML au format "3D Manufacturing Format") et reexport en .stl
# binaire - fichier ensuite traite exactement comme n'importe quel autre .stl par le reste de
# l'appli (Lancer-Traitement convertit AVANT d'appeler Coloriser-UnFichier, voir plus bas).
#
# Portee volontairement limitee a un .3mf "simple" (le cas de Tomyn : un modele non colorise,
# jamais passe par cet outil) : un seul niveau de <components> est resolu recursivement (le format
# permet d'imbriquer indefiniment, mais les .3mf qu'on rencontre ici ne le font pas), et SEUL le
# maillage geometrique est repris - aucune couleur/texture n'est lue depuis le .3mf meme s'il y en
# avait (hors sujet : le but de l'appli est justement de (re)generer des couleurs avec l'IA, pas de
# preserver celles d'un .3mf deja colorise differemment).
function Convertir-3MFVersSTL($Fichier3mf) {
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Fichier3mf.FullName)
        $entreeModele = $archive.Entries | Where-Object { $_.FullName -match '3dmodel\.model$' } | Select-Object -First 1
        if (-not $entreeModele) {
            throw "aucun '3dmodel.model' trouve dans ce .3mf (fichier corrompu ou pas un vrai .3mf ?)"
        }

        # XPath avec local-name() plutot qu'un XmlNamespaceManager : evite de devoir connaitre a
        # l'avance l'URI exacte du namespace 3MF utilisee par le logiciel qui a genere le fichier
        # (elle a change de version en version du standard, et certains exporteurs sont approximatifs
        # dessus) - local-name() ignore completement le namespace, se base juste sur le nom de balise.
        $ci = [System.Globalization.CultureInfo]::InvariantCulture

        # Corrige le 20/10/2026 (cas reel signale par Tomyn : "aucun maillage exploitable trouve")
        # - Extension de Production 3MF (namespace .../production/2015/06, declaree via
        # requiredextensions="p" sur <model>) : un <component> peut pointer, via un attribut "path"
        # (prefixe variable, p:path en general), vers un AUTRE fichier XML interne au zip qui
        # contient le vrai <object>. C'est le layout standard produit par Bambu Studio (et
        # vraisemblablement Orca Slicer/PrusaSlicer) pour les .3mf a gros maillage : le
        # 3dmodel.model racine ne contient qu'un <component path="..."> vide de maillage, le vrai
        # maillage vit dans un fichier a part comme 3D/Objects/object_1.model. Chaque document XML
        # charge est mis en cache et garde ses propres dictionnaires Maillage/Composants (les id
        # d'objet ne sont uniques qu'au sein d'un meme document, pas globalement dans le zip).
        $documentsCharges = @{}  # chemin zip normalise -> @{ Maillage = @{}; Composants = @{} }

        function Analyser-Document3MF($xmlDoc) {
            $objetsMaillage = @{}    # id -> @{ Sommets = [double[3]][]; Triangles = [int[3]][] }
            $objetsComposants = @{}  # id -> liste de @{ ObjectId; Transform; Chemin }
            foreach ($noeudObjet in $xmlDoc.SelectNodes("//*[local-name()='object']")) {
                $id = $noeudObjet.GetAttribute("id")
                if (-not $id) { continue }
                $noeudMesh = $noeudObjet.SelectSingleNode("*[local-name()='mesh']")
                if ($noeudMesh) {
                    $sommets = New-Object System.Collections.Generic.List[double[]]
                    foreach ($v in $noeudMesh.SelectNodes(".//*[local-name()='vertex']")) {
                        $sommets.Add(@(
                            [double]::Parse($v.GetAttribute("x"), $ci),
                            [double]::Parse($v.GetAttribute("y"), $ci),
                            [double]::Parse($v.GetAttribute("z"), $ci)
                        ))
                    }
                    $triangles = New-Object System.Collections.Generic.List[int[]]
                    foreach ($t in $noeudMesh.SelectNodes(".//*[local-name()='triangle']")) {
                        $triangles.Add(@(
                            [int]$t.GetAttribute("v1"),
                            [int]$t.GetAttribute("v2"),
                            [int]$t.GetAttribute("v3")
                        ))
                    }
                    $objetsMaillage[$id] = @{ Sommets = $sommets; Triangles = $triangles }
                    continue
                }
                $noeudComposants = $noeudObjet.SelectSingleNode("*[local-name()='components']")
                if ($noeudComposants) {
                    $liste = New-Object System.Collections.Generic.List[object]
                    foreach ($c in $noeudComposants.SelectNodes("*[local-name()='component']")) {
                        # Attribut "path" de l'extension de Production : prefixe variable (p:path le
                        # plus souvent) donc recherche par LocalName plutot que par nom fixe, pour
                        # rester agnostique au prefixe/namespace exact utilise par l'exporteur.
                        $attributPath = $c.Attributes | Where-Object { $_.LocalName -eq 'path' } | Select-Object -First 1
                        $liste.Add(@{
                            ObjectId  = $c.GetAttribute("objectid")
                            Transform = $c.GetAttribute("transform")
                            Chemin    = if ($attributPath) { $attributPath.Value } else { $null }
                        })
                    }
                    $objetsComposants[$id] = $liste
                }
            }
            return @{ Maillage = $objetsMaillage; Composants = $objetsComposants }
        }

        function Obtenir-Document3MF([string]$cheminZip) {
            $cheminNormalise = $cheminZip.TrimStart('/')
            if ($documentsCharges.ContainsKey($cheminNormalise)) { return $documentsCharges[$cheminNormalise] }
            $entree = $archive.Entries | Where-Object { $_.FullName -eq $cheminNormalise } | Select-Object -First 1
            if (-not $entree) {
                # Tolerance : comparaison insensible a la casse si la correspondance exacte echoue
                # (certains exporteurs sont approximatifs sur la casse des chemins internes au zip).
                $entree = $archive.Entries | Where-Object { $_.FullName -ieq $cheminNormalise } | Select-Object -First 1
            }
            if (-not $entree) {
                $vide = @{ Maillage = @{}; Composants = @{} }
                $documentsCharges[$cheminNormalise] = $vide
                return $vide
            }
            $xmlExterne = New-Object System.Xml.XmlDocument
            $fluxExterne = $entree.Open()
            try { $xmlExterne.Load($fluxExterne) } finally { $fluxExterne.Close() }
            $document = Analyser-Document3MF $xmlExterne
            $documentsCharges[$cheminNormalise] = $document
            return $document
        }

        $xml = New-Object System.Xml.XmlDocument
        $flux = $entreeModele.Open()
        try { $xml.Load($flux) } finally { $flux.Close() }
        $documentRacine = Analyser-Document3MF $xml
        $documentsCharges[$entreeModele.FullName.TrimStart('/')] = $documentRacine

        # Transform 3MF : 12 nombres (3x3 de rotation/echelle + 3 de translation), applique a un
        # point en vecteur-ligne (v' = v * M). Represente ici en 4x4 ligne-major (identite par
        # defaut) pour pouvoir composer les transforms imbriquees par simple multiplication de
        # matrices plutot que de gerer un cas particulier pour chaque niveau de profondeur.
        function Analyser-Transform3MF([string]$texte) {
            if ([string]::IsNullOrWhiteSpace($texte)) { return @(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1) }
            $n = @($texte.Trim() -split '\s+' | ForEach-Object { [double]::Parse($_, $ci) })
            if ($n.Count -ne 12) { return @(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1) }
            return @($n[0],$n[1],$n[2],0, $n[3],$n[4],$n[5],0, $n[6],$n[7],$n[8],0, $n[9],$n[10],$n[11],1)
        }
        function Multiplier-Transform3MF([double[]]$A, [double[]]$B) {
            $r = New-Object double[] 16
            for ($ligne = 0; $ligne -lt 4; $ligne++) {
                for ($col = 0; $col -lt 4; $col++) {
                    $somme = 0.0
                    for ($k = 0; $k -lt 4; $k++) { $somme += $A[$ligne * 4 + $k] * $B[$k * 4 + $col] }
                    $r[$ligne * 4 + $col] = $somme
                }
            }
            return $r
        }
        function Appliquer-Transform3MF([double[]]$p, [double[]]$M) {
            # Chaque element entre parentheses explicites : en PowerShell, l'operateur virgule
            # (construction de tableau) a une PRIORITE PLUS HAUTE que + / * en dehors de parentheses
            # - sans elles, "a+b, c+d" est en fait interprete comme "a + (b,c) + d" et non comme deux
            # sommes separees (verifie reellement en PowerShell 7.4, pas une simple supposition -
            # piege classique mais discret du langage). Les parentheses forcent chaque somme a etre
            # evaluee en scalaire AVANT d'etre placee dans le tableau @(...).
            return @(
                ($p[0]*$M[0] + $p[1]*$M[4] + $p[2]*$M[8]  + $M[12]),
                ($p[0]*$M[1] + $p[1]*$M[5] + $p[2]*$M[9]  + $M[13]),
                ($p[0]*$M[2] + $p[1]*$M[6] + $p[2]*$M[10] + $M[14])
            )
        }

        $sommetsGlobaux = New-Object System.Collections.Generic.List[double[]]
        $trianglesGlobaux = New-Object System.Collections.Generic.List[int[]]
        $profondeurMax = 8  # garde-fou anti-boucle (composants qui se referencent entre eux)

        function Resoudre-Objet3MF([string]$id, [double[]]$transformCumule, [int]$profondeur, $documentActuel) {
            if ($profondeur -gt $profondeurMax) { return }
            if ($documentActuel.Maillage.ContainsKey($id)) {
                $decalage = $sommetsGlobaux.Count
                foreach ($s in $documentActuel.Maillage[$id].Sommets) { $sommetsGlobaux.Add((Appliquer-Transform3MF $s $transformCumule)) }
                foreach ($t in $documentActuel.Maillage[$id].Triangles) {
                    # Memes parentheses explicites et pour la meme raison que dans
                    # Appliquer-Transform3MF ci-dessus (priorite de la virgule > + en PowerShell).
                    $trianglesGlobaux.Add(@(($t[0] + $decalage), ($t[1] + $decalage), ($t[2] + $decalage)))
                }
            } elseif ($documentActuel.Composants.ContainsKey($id)) {
                foreach ($comp in $documentActuel.Composants[$id]) {
                    $transformComposant = Analyser-Transform3MF $comp.Transform
                    $cumul = Multiplier-Transform3MF $transformComposant $transformCumule
                    if ($comp.Chemin) {
                        # Reference vers un AUTRE fichier XML du zip (extension de Production) :
                        # l'objectid se resout dans CE document externe, pas dans le document actuel.
                        $documentCible = Obtenir-Document3MF $comp.Chemin
                        Resoudre-Objet3MF $comp.ObjectId $cumul ($profondeur + 1) $documentCible
                    } else {
                        Resoudre-Objet3MF $comp.ObjectId $cumul ($profondeur + 1) $documentActuel
                    }
                }
            }
            # id inconnu (reference cassee) : ignore silencieusement, pas bloquant pour le reste.
        }

        $identite = @(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
        $noeudsItem = $xml.SelectNodes("//*[local-name()='build']/*[local-name()='item']")
        if ($noeudsItem.Count -gt 0) {
            foreach ($item in $noeudsItem) {
                $t = Analyser-Transform3MF $item.GetAttribute("transform")
                Resoudre-Objet3MF $item.GetAttribute("objectid") $t 0 $documentRacine
            }
        } else {
            # Pas de section <build> (ou vide) : rare, mais plutot que d'echouer completement, on
            # reprend tous les objets a maillage direct tels quels (sans transform), au cas ou le
            # fichier soit quand meme exploitable.
            foreach ($id in $documentRacine.Maillage.Keys) { Resoudre-Objet3MF $id $identite 0 $documentRacine }
        }

        if ($trianglesGlobaux.Count -eq 0) {
            throw "aucun maillage exploitable trouve dans ce .3mf (section <build> vide et aucun objet a maillage direct)"
        }

        # --- Ecriture en .stl binaire : 80 octets d'entete + nb de triangles (uint32) + par
        # triangle, normale (3 floats, calculee ici par produit vectoriel) + 3 sommets (3 floats
        # chacun) + 2 octets d'attribut (toujours 0). Format standard, le meme que Bambu Studio et
        # Meshy savent lire sans ambiguite.
        $dossierTemp = Join-Path $env:TEMP ("ColoriserSTL_3mf_" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
        New-Item -ItemType Directory -Force -Path $dossierTemp | Out-Null
        $cheminStl = Join-Path $dossierTemp ($Fichier3mf.BaseName + ".stl")

        $flux = [System.IO.File]::Create($cheminStl)
        try {
            $ecrivain = New-Object System.IO.BinaryWriter($flux)
            $entete = New-Object byte[] 80
            $texteEntete = [System.Text.Encoding]::ASCII.GetBytes("Converti depuis $($Fichier3mf.Name) par Coloriser-STL")
            [Array]::Copy($texteEntete, $entete, [Math]::Min($texteEntete.Length, 80))
            $ecrivain.Write($entete)
            $ecrivain.Write([uint32]$trianglesGlobaux.Count)
            foreach ($tri in $trianglesGlobaux) {
                $p1 = $sommetsGlobaux[$tri[0]]; $p2 = $sommetsGlobaux[$tri[1]]; $p3 = $sommetsGlobaux[$tri[2]]
                $ux = $p2[0]-$p1[0]; $uy = $p2[1]-$p1[1]; $uz = $p2[2]-$p1[2]
                $vx = $p3[0]-$p1[0]; $vy = $p3[1]-$p1[1]; $vz = $p3[2]-$p1[2]
                $nx = $uy*$vz - $uz*$vy; $ny = $uz*$vx - $ux*$vz; $nz = $ux*$vy - $uy*$vx
                $norme = [Math]::Sqrt($nx*$nx + $ny*$ny + $nz*$nz)
                if ($norme -gt 0) { $nx /= $norme; $ny /= $norme; $nz /= $norme }
                $ecrivain.Write([float]$nx); $ecrivain.Write([float]$ny); $ecrivain.Write([float]$nz)
                foreach ($p in @($p1, $p2, $p3)) {
                    $ecrivain.Write([float]$p[0]); $ecrivain.Write([float]$p[1]); $ecrivain.Write([float]$p[2])
                }
                $ecrivain.Write([uint16]0)
            }
        } finally {
            $flux.Close()
        }

        # Nombre d'objets a maillage direct, tous documents confondus (racine + parties externes
        # chargees via l'extension de Production) - juste indicatif pour le journal.
        $nbObjetsTotal = ($documentsCharges.Values | ForEach-Object { $_.Maillage.Count } | Measure-Object -Sum).Sum
        return @{ Fichier = (Get-Item $cheminStl); NbTriangles = $trianglesGlobaux.Count; NbObjets = $nbObjetsTotal }
    } finally {
        if ($archive) { $archive.Dispose() }
    }
}

function Obtenir-ImageDepuisUrl($url) {
    try {
        $octets = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
        $flux = New-Object System.IO.MemoryStream(,$octets)
        return [System.Drawing.Image]::FromStream($flux)
    } catch {
        return $null
    }
}

# Ajoute le 08/10/2026 (demande de Tomyn) : la boite de dialogue de melange automatique de Bambu
# Studio (celle qui s'affiche a l'ouverture d'un .obj texture) peut eclaircir ou assombrir le
# rendu final selon les filaments choisis (du blanc dans le melange pastellise, du bleu assombrit
# - voir le README/l'infobulle de la case Meshy .obj). Ce reglage permet de precompenser cot
# texture, AVANT l'ouverture dans Bambu Studio, en assombrissant l'image de base_color recue de
# Meshy d'un pourcentage reglable au dixieme pres (0.0 a 100.0). Pas de reglage universel possible
# (ca depend du jeu de filaments utilise ensuite dans Bambu), donc laisse a l'utilisateur plutot
# qu'automatise.
function Assombrir-FichierImage($CheminFichier, [double]$PourcentageAssombrissement) {
    if ($PourcentageAssombrissement -le 0) { return }

    $facteur = 1.0 - ($PourcentageAssombrissement / 100.0)
    if ($facteur -lt 0) { $facteur = 0 }

    # Charge en memoire puis libere le fichier avant de le reecrire (Bitmap garde le flux source
    # ouvert sinon, ce qui empecherait d'ecraser le meme chemin).
    $octetsOriginaux = [System.IO.File]::ReadAllBytes($CheminFichier)
    $fluxLecture = New-Object System.IO.MemoryStream(,$octetsOriginaux)
    $imageSource = [System.Drawing.Bitmap]::new([System.Drawing.Image]::FromStream($fluxLecture))
    $fluxLecture.Dispose()

    # ColorMatrix + DrawImage plutot que GetPixel/SetPixel pixel par pixel : sur une texture 4K
    # (16M+ pixels), la boucle pixel par pixel prendrait facilement plusieurs dizaines de secondes
    # par fichier - la matrice fait la meme operation (multiplier R/G/B par $facteur) via le pipeline
    # GDI+, quasi instantane quelle que soit la resolution.
    $matrice = New-Object System.Drawing.Imaging.ColorMatrix
    $matrice.Matrix00 = $facteur  # R
    $matrice.Matrix11 = $facteur  # G
    $matrice.Matrix22 = $facteur  # B
    $matrice.Matrix33 = 1.0       # alpha inchange
    $matrice.Matrix44 = 1.0
    $attributs = New-Object System.Drawing.Imaging.ImageAttributes
    $attributs.SetColorMatrix($matrice)

    $bmpAssombri = New-Object System.Drawing.Bitmap($imageSource.Width, $imageSource.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmpAssombri)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $imageSource.Width, $imageSource.Height)
    $g.DrawImage($imageSource, $rect, 0, 0, $imageSource.Width, $imageSource.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributs)
    $g.Dispose()
    $imageSource.Dispose()

    $extension = [System.IO.Path]::GetExtension($CheminFichier).ToLowerInvariant()
    $formatImage = if ($extension -eq ".png") { [System.Drawing.Imaging.ImageFormat]::Png } else { [System.Drawing.Imaging.ImageFormat]::Jpeg }
    $bmpAssombri.Save($CheminFichier, $formatImage)
    $bmpAssombri.Dispose()
}

# Voir le commentaire pres de $CheminHistoriqueFichiers plus haut pour le pourquoi de ce fichier
# distinct de l'historique par LOT ($CheminHistorique). Jamais bloquant (try/catch large, meme
# logique que l'historique de lot existant) : un souci d'ecriture ici ne doit jamais faire
# echouer le traitement reel.
function Enregistrer-HistoriqueFichier($NomFichier, $Fournisseur, $Credits, $CheminSortie) {
    try {
        if (-not (Test-Path $CheminHistoriqueFichiers)) {
            Add-Content -Path $CheminHistoriqueFichiers -Value "Date;Fichier;Fournisseur;Credits;CheminSortie"
        }
        $ligne = "$(Get-Date -Format 'dd/MM/yyyy HH:mm');$NomFichier;$Fournisseur;$Credits;$CheminSortie"
        Add-Content -Path $CheminHistoriqueFichiers -Value $ligne
    } catch { }
}

function Creer-ImageRemplacement($taillePixels) {
    $bmp = New-Object System.Drawing.Bitmap($taillePixels, $taillePixels)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Gainsboro)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = "Center"
    $format.LineAlignment = "Center"
    $g.DrawString("pas d'apercu", (New-Object System.Drawing.Font("Segoe UI", 8)),
        [System.Drawing.Brushes]::DimGray, (New-Object System.Drawing.RectangleF(0, 0, $taillePixels, $taillePixels)), $format)
    $g.Dispose()
    return $bmp
}
# Reduite de 220 a 170 le 14/10/2026 (Tomyn : "preview toujours coupe" apres 2 passes de rognage
# de l'espacement du haut) - ces passes-la ont un plafond, le haut de l'ecran ne peut pas
# descendre sous une certaine hauteur sans casser des champs. Une carte de galerie plus petite
# libere plus de place d'un coup, 50px de moins en hauteur ET en largeur par carte, donc aussi
# plus de vignettes par ligne, sans toucher au haut de l'ecran deja fragile.
$TailleMiniature = 170
$ImageRemplacement = Creer-ImageRemplacement $TailleMiniature

# Force TLS 1.2 explicitement : sur certaines configurations de Windows PowerShell 5.1, le
# protocole par defaut n'inclut pas TLS 1.2, ce qu'Amazon S3 (utilise par Tripo pour l'upload de
# fichiers) exige - la connexion peut alors rester bloquee silencieusement plutot que d'echouer
# proprement, meme avec un -TimeoutSec defini. Applique une fois, globalement, en tete de script.
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch { }

$BaseUrl = "https://api.meshy.ai/openapi/v1"
$IntervallePollSecondes = 5
$TimeoutTacheSecondes = 1200
$CheminCleChiffree = Join-Path $PSScriptRoot "cle_api.enc"
$CheminCleTripoChiffree = Join-Path $PSScriptRoot "cle_api_tripo.enc"
# Pas sensible (contrairement a la cle API), donc pas besoin de chiffrement - juste un petit
# fichier texte par categorie a cote du script pour retrouver le dernier prompt libre ("Autre")
# d'un lancement a l'autre (voir Obtenir-CheminDernierPromptLibre plus bas).
$CheminHistorique = Join-Path $PSScriptRoot "historique_lots.csv"
# Historique PAR FICHIER (ajoute le 08/10/2026, demande de Damdam2959) : contrairement a
# $CheminHistorique ci-dessus (une ligne par LOT, un total), celui-ci garde une ligne par fichier
# reussi - nom, fournisseur, credits consommes, chemin de sortie. Utile meme si le fichier de
# sortie lui-meme disparait un jour (disque, suppression accidentelle...) : au moins la trace de
# ce qui a ete genere et ce que ca a coute reste quelque part, independamment du dossier de
# sortie. Les resultats Meshy/Tripo ne sont PAS recuperables depuis leur API passe 3 jours
# (confirme sur leur doc officielle le 08/10/2026 - "models generated through the API are kept
# for a maximum of 3 days"), donc ceci ne remplace pas une sauvegarde du dossier de sortie
# lui-meme, juste un journal local complementaire.
$CheminHistoriqueFichiers = Join-Path $PSScriptRoot "historique_fichiers.csv"
# Emplacement de l'installation de Melange-Couleurs sur cette machine (16/10/2026, passerelle
# "Analyser les couleurs" sur un resultat .3mf - voir Ajouter-Vignette et Lancer-MelangeCouleurs
# plus bas) - les deux outils sont des projets separes, chacun dans son propre dossier, sans lien
# garanti entre les deux (pas forcement des dossiers freres), donc pas de chemin relatif fiable a
# deviner. Un petit JSON a cote de CE script retient le chemin une fois que Tomyn l'a indique, pour
# ne plus jamais avoir a redemander ensuite.
$CheminConfigMelangeCouleurs = Join-Path $PSScriptRoot "chemin_melange_couleurs.json"
# Rectifie le 07/10/2026 : premiere lecture du tableau de bord Meshy par Tomyn mal interpretee
# (25+15+16 = 56), le vrai detail confirme juste apres est Retexture = 10 credits et Multi-Color
# Print = 10 credits, soit 20 au total - l'estimation d'origine etait donc la bonne.
$CREDITS_ESTIMES_PAR_FICHIER = 20
# 21/10/2026, idee en passant validee par Tomyn ("2-4") : jusqu'ici le solde n'etait verifie
# qu'UNE FOIS, juste avant de lancer tout le lot - sur un dossier de 250 fichiers payes par son
# collegue dessinateur, un derapage du cout reel (options changees en cours de route, generation
# plus chere que l'estimation) ne se voyait qu'en echouant fichier par fichier une fois le solde
# epuise, sans prevenir avant. Tous les N fichiers, on reverifie le solde REEL contre le cout
# estime des fichiers RESTANTS (pas tout le lot a nouveau) - voir la verification dans la boucle
# de Lancer-Traitement plus bas. 20 fichiers : assez espace pour ne pas gaspiller un appel API a
# chaque fichier, assez frequent pour reagir avant d'avoir trop depense sur un gros lot.
$INTERVALLE_VERIF_SOLDE_LOT = 20
# Cout de la seule etape Retexture (sans Multi-Color Print) - utilise pour l'estimation quand la
# case "exporter en .obj" est cochee, qui saute Multi-Color Print.
$CREDITS_ESTIMES_RETEXTURE_SEULE = 10
# Confirme par Tomyn le 07/10/2026 : import 5 credits + texturation 10 credits = 15 credits "de
# base" cote Tripo, PLUS l'etape de conversion (variable, ~5 credits observes une fois) - donc
# ~20 credits au total, mais seuls les deux premiers chiffres sont vraiment confirmes. Echelle
# differente de celle de Meshy (pas garanti que ce soit le meme "credit" d'un fournisseur a
# l'autre), d'ou une constante separee plutot que de reutiliser celle de Meshy.
$CREDITS_ESTIMES_PAR_FICHIER_TRIPO = 20
# Formats acceptes par l'API Meshy en entree (confirme dans la doc officielle - le .3mf n'y
# figure PAS : Meshy ne l'accepte qu'en SORTIE, jamais comme source a coloriser).
$EXTENSIONS_MODELES_3D = @(".stl", ".obj", ".fbx", ".glb", ".gltf")
# Image -> STL, ajoute le 08/10/2026 (idee de Tomyn) : plutot que de faire le modele 3D a la main
# sur le site Meshy puis de le re-deposer ici, on accepte directement une image dans le meme
# dossier/lot - detectee par son extension, sans case ni onglet separe. Meshy uniquement pour le
# moment (pas encore verifie cote Tripo).
# .webp ajoute le 20/10/2026 (Tomyn, suite au changelog Meshy) : documente comme format d'entree
# accepte par Meshy depuis le 10/10/2026 (Image to 3D, Retexture, Image to Image) - manquait ici,
# un .webp envoye par le collegue de Tomyn aurait ete rejete avant meme d'atteindre l'API.
$EXTENSIONS_IMAGES = @(".jpg", ".jpeg", ".png", ".webp")
# .3mf non colorise, ajoute le 20/10/2026 (Tomyn : "j'ai plusieurs 3MF non colorises que je
# voudrais coloriser") - toujours pas accepte directement par Meshy en entree (voir le commentaire
# sur $EXTENSIONS_MODELES_3D plus haut), donc categorie a part : Lancer-Traitement le convertit en
# .stl via Convertir-3MFVersSTL AVANT d'appeler Coloriser-UnFichier/-UnFichierTripo, qui ne voient
# donc jamais passer de .3mf directement.
$EXTENSIONS_3MF_SOURCE = @(".3mf")
$EXTENSIONS_SUPPORTEES = $EXTENSIONS_MODELES_3D + $EXTENSIONS_IMAGES + $EXTENSIONS_3MF_SOURCE
# Cout de l'etape Image to 3D en maillage seul (should_texture=false, modele par defaut
# meshy-7.1/meshy-6) - confirme sur la doc tarifaire officielle Meshy le 08/10/2026. S'ajoute
# AVANT les credits de colorisation habituels (Retexture +/- Multi-Color Print) quand la source
# est une image plutot qu'un modele 3D deja existant.
$CREDITS_ESTIMES_IMAGE_VERS_3D = 20

# Simplification automatique des gros maillages avant Retexture (15/10/2026, idee de Tomyn,
# suite a son souci de maillage a 1M+ triangles qui perdait ses couleurs en le simplifiant APRES
# coup dans Bambu Studio). Seuil au-dela duquel un .stl binaire est passe par l'API Remesh de
# Meshy (voir Lancer-Remesh et Obtenir-NombreTrianglesSTL plus bas) avant d'etre envoye a
# Retexture, plutot que tel quel - evite d'envoyer un maillage inutilement lourd (credits, temps)
# et evite le probleme de depart (ici la simplification se fait AVANT la colorisation, donc pas de
# couleurs a perdre). Limite aux .stl BINAIRES pour l'instant (comptage fiable et rapide via
# l'en-tete du fichier, voir Obtenir-NombreTrianglesSTL) - pas encore etendu a l'ASCII ni a l'OBJ.
$SEUIL_TRIANGLES_REMESH_AUTO = 500000

# ============================== THEME "ATELIER" ==============================
# Ajoute le 10/10/2026 (demande de Tomyn : l'appli "faisait trop fenetre Windows", trop grise et
# austere). Palette violette reprise de l'appli Android ColoriserSTL (meme outil, deux
# plateformes) pour une identite visuelle coherente entre les deux.
#
# 16/10/2026 (Tomyn : "vas-y" sur la refonte visuelle mise en attente plus tot) - deuxieme passe,
# volontairement bornee plutot qu'une refonte totale : la base violette "atelier" posee le
# 10/10/2026 reste (coherence avec l'appli Android, demandee explicitement), on l'affine plutot
# que la jeter. Trois changements, centralises dans $THEME/Rendre-BoutonPlat/Definir-RegionArrondie
# pour se propager a TOUTE l'appli sans retoucher chaque bouton/fenetre a la main :
#   1. Fond et bordure legerement retintes vers le violet de marque (au lieu d'un gris-bleu
#      neutre) - renforce l'identite au lieu de la diluer sur un fond generique.
#      AccentDoux ajoute (le lilas tres clair deja utilise en survol de bouton, promu en token
#      nomme pour servir aussi de fond de bloc/encadre discret).
#   2. Coins arrondis sur TOUS les boutons (meme rayon que les cartes de la galerie, deja
#      arrondies depuis le 10/10) - jusqu'ici les boutons restaient des rectangles nets au milieu
#      d'une appli autrement toute en courbes, un des signes les plus "fenetre Windows par
#      defaut" qui restaient.
#   3. Les fenetres custom (boites de dialogue Afficher-Boite, overlay de progression) arrondies
#      elles aussi, memes coins que les cartes et les boutons - coherence visuelle de bout en bout.
# PAS TESTE PAR CLAUDE (meme limite que le reste du fichier, voir l'en-tete) : aucun
# Windows/PowerShell disponible ici pour verifier le rendu reel - a verifier par Tomyn comme
# toujours, mais c'est une technique standard et bien documentee (Control.Region via
# GraphicsPath), deja utilisee ici meme pour les cartes de galerie depuis le 10/10/2026 sans
# souci rapporte.

$THEME = @{
    FondApp            = [System.Drawing.Color]::FromArgb(0xEB, 0xE9, 0xF4)   # lilas tres pale (plan de travail) - avant : gris-bleu neutre EEF1F3, retinte vers la marque
    FondBanniere       = [System.Drawing.Color]::FromArgb(0x45, 0x27, 0xA0)   # violet fonce (accent_violet_fonce, cote Android)
    Surface            = [System.Drawing.Color]::White
    AccentPrincipal    = [System.Drawing.Color]::FromArgb(0x7C, 0x4D, 0xFF)   # violet (accent_violet, cote Android)
    AccentPrincipalTxt = [System.Drawing.Color]::White
    AccentDanger       = [System.Drawing.Color]::FromArgb(0xD3, 0x2F, 0x2F)
    AccentChaud        = [System.Drawing.Color]::FromArgb(0xFF, 0x5A, 0x1F)   # orange nozzle - relance/alerte douce
    AccentDoux         = [System.Drawing.Color]::FromArgb(0xF1, 0xEC, 0xFF)   # lilas tres clair - deja la couleur de survol des boutons "secondaire", promu en token nomme
    Texte              = [System.Drawing.Color]::FromArgb(0x1A, 0x1A, 0x1A)
    TexteSecondaire    = [System.Drawing.Color]::FromArgb(0x5C, 0x5C, 0x5C)
    Bordure            = [System.Drawing.Color]::FromArgb(0xDC, 0xD6, 0xEC)   # avant : gris neutre D8DADD, retinte vers le violet plutot qu'un gris pur
    RayonArrondi       = 7                                                     # rayon de coin partage par boutons/fenetres custom/cartes (point d'ajustement unique)
    HauteurBanniere    = 56
}

# Mode sombre (16/10/2026, idee d'amelioration validee "tu peux toutes les faire") - "basique"
# assume : les fonds, textes et cases passent en sombre, mais la couleur de survol/bordure exacte
# de chaque bouton (FlatAppearance.MouseOverBackColor, jamais relue ni modifiee ici) reste celle
# calculee au moment ou Rendre-BoutonPlat a ete appele la premiere fois - non verifiable visuellement
# sans Windows, donc scope volontairement reduit a ce qui compte vraiment (lisibilite) plutot que
# de risquer une refonte complete a l'aveugle.
# $THEME_ORIGINAL : copie figee de la palette claire ci-dessus, JAMAIS modifiee - sert de reference
# "point de depart" pour construire la correspondance couleur->couleur a chaque bascule, que $THEME
# (lui, modifie EN PLACE a chaque bascule - voir Basculer-ModeSombre) soit actuellement clair ou
# sombre.
$THEME_ORIGINAL = @{}
foreach ($cle in $THEME.Keys) { $THEME_ORIGINAL[$cle] = $THEME[$cle] }

$THEME_SOMBRE = @{
    FondApp            = [System.Drawing.Color]::FromArgb(0x1E, 0x1E, 0x24)
    FondBanniere        = [System.Drawing.Color]::FromArgb(0x2E, 0x1C, 0x66)
    Surface            = [System.Drawing.Color]::FromArgb(0x2A, 0x2A, 0x32)
    AccentPrincipal    = [System.Drawing.Color]::FromArgb(0x9B, 0x7A, 0xFF)
    AccentPrincipalTxt = [System.Drawing.Color]::White
    AccentDanger       = [System.Drawing.Color]::FromArgb(0xFF, 0x6B, 0x6B)
    AccentChaud        = [System.Drawing.Color]::FromArgb(0xFF, 0x7A, 0x45)
    AccentDoux         = [System.Drawing.Color]::FromArgb(0x3D, 0x35, 0x55)
    Texte              = [System.Drawing.Color]::FromArgb(0xEC, 0xEC, 0xF2)
    TexteSecondaire    = [System.Drawing.Color]::FromArgb(0xB0, 0xB0, 0xBC)
    Bordure            = [System.Drawing.Color]::FromArgb(0x44, 0x44, 0x50)
    RayonArrondi       = 7
    HauteurBanniere    = 56
}

$script:modeSombreActif = $false

function Obtenir-CheminPreferenceModeSombre {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "mode-sombre.json" } else { Join-Path (Get-Location) "mode-sombre.json" }
}

function Recolorer-ControlesRecursif($controle, [hashtable]$mapping) {
    foreach ($enfant in @($controle.Controls)) {
        try {
            if ($mapping.ContainsKey($enfant.BackColor.ToArgb())) { $enfant.BackColor = $mapping[$enfant.BackColor.ToArgb()] }
        } catch { }
        try {
            if ($mapping.ContainsKey($enfant.ForeColor.ToArgb())) { $enfant.ForeColor = $mapping[$enfant.ForeColor.ToArgb()] }
        } catch { }
        try {
            if ($enfant -is [System.Windows.Forms.Button] -and $enfant.FlatAppearance -and $mapping.ContainsKey($enfant.FlatAppearance.BorderColor.ToArgb())) {
                $enfant.FlatAppearance.BorderColor = $mapping[$enfant.FlatAppearance.BorderColor.ToArgb()]
            }
        } catch { }
        if ($enfant.Controls -and $enfant.Controls.Count -gt 0) { Recolorer-ControlesRecursif $enfant $mapping }
    }
}

# Bascule clair<->sombre. $THEME est modifie EN PLACE (jamais reassigne) pour que tout ce qui est
# cree APRES la bascule (prochaine boite de dialogue, prochaine carte de galerie, prochain overlay)
# parte directement avec les bonnes couleurs - seuls les controles DEJA CREES (fenetre principale +
# overlay de progression, deja existants au demarrage) ont besoin d'etre recolories explicitement ici.
function Basculer-ModeSombre([bool]$silencieux = $false) {
    $versSombre = -not $script:modeSombreActif
    $source = if ($versSombre) { $THEME_ORIGINAL } else { $THEME_SOMBRE }
    $cible  = if ($versSombre) { $THEME_SOMBRE } else { $THEME_ORIGINAL }
    $mapping = @{}
    foreach ($cle in $THEME_ORIGINAL.Keys) {
        if ($THEME_ORIGINAL[$cle] -is [System.Drawing.Color]) { $mapping[$source[$cle].ToArgb()] = $cible[$cle] }
    }
    try {
        if ($mapping.ContainsKey($form.BackColor.ToArgb())) { $form.BackColor = $mapping[$form.BackColor.ToArgb()] }
    } catch { }
    Recolorer-ControlesRecursif $form $mapping
    try {
        if ($mapping.ContainsKey($overlayProgression.BackColor.ToArgb())) { $overlayProgression.BackColor = $mapping[$overlayProgression.BackColor.ToArgb()] }
        Recolorer-ControlesRecursif $overlayProgression $mapping
    } catch { }
    foreach ($cle in @($cible.Keys)) { if ($cible[$cle] -is [System.Drawing.Color]) { $THEME[$cle] = $cible[$cle] } }
    $script:modeSombreActif = $versSombre
    if (-not $silencieux) {
        try { (@{ ModeSombre = $script:modeSombreActif } | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminPreferenceModeSombre) -Encoding UTF8 -ErrorAction Stop } catch { }
    }
    if ($btnModeSombre) { $btnModeSombre.Text = if ($script:modeSombreActif) { "Mode clair" } else { "Mode sombre" } }
}

# Arrondit les coins d'un controle ou d'une fenetre (Region via GraphicsPath) - factorise ici
# (16/10/2026) a partir du code deja utilise pour les cartes de la galerie depuis le 10/10/2026,
# pour l'appliquer maintenant aussi aux boutons et aux fenetres custom (Afficher-Boite, overlay)
# sans dupliquer le meme trace de chemin a chaque fois. Un $rayon de 0 ou une taille nulle/negative
# ne touche a rien (evite une Region vide/invalide si appelee trop tot, avant que Windows ait
# attribue une vraie taille au controle).
function Definir-RegionArrondie($controle, [int]$rayon = 0) {
    if ($rayon -le 0 -or $controle.Width -le 0 -or $controle.Height -le 0) { return }
    $diametre = $rayon * 2
    if ($diametre -ge $controle.Width) { $diametre = [Math]::Max(2, $controle.Width - 2) }
    if ($diametre -ge $controle.Height) { $diametre = [Math]::Max(2, [Math]::Min($diametre, $controle.Height - 2)) }
    $chemin = New-Object System.Drawing.Drawing2D.GraphicsPath
    $largeur = $controle.Width
    $hauteur = $controle.Height
    $chemin.AddArc(0, 0, $diametre, $diametre, 180, 90)
    $chemin.AddArc(($largeur - $diametre - 1), 0, $diametre, $diametre, 270, 90)
    $chemin.AddArc(($largeur - $diametre - 1), ($hauteur - $diametre - 1), $diametre, $diametre, 0, 90)
    $chemin.AddArc(0, ($hauteur - $diametre - 1), $diametre, $diametre, 90, 90)
    $chemin.CloseFigure()
    $controle.Region = New-Object System.Drawing.Region($chemin)
}

# SendMessage (PBM_SETBARCOLOR / PBM_SETBKCOLOR) pour recolorer la ProgressBar - l'API WinForms
# native ne donne aucun acces a sa couleur (toujours celle du theme Windows de la machine).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NativeMethodsTheme {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue

# 17/10/2026, Tomyn : "la barre de progression ne fonctionne plus" - en fait elle n'a jamais
# vraiment fonctionne : PBM_SETBARCOLOR (la partie remplie) ET PBM_SETBKCOLOR (le fond/piste vide)
# recevaient tous les deux le MEME $couleur (violet accent), alors que le commentaire d'origine
# disait vouloir un fond CLAIR distinct ("fond sombre -> clair, sinon la barre garde un fond
# vert/bleu derriere l'accent"). Avec les deux identiques, la barre entiere - remplie ou pas -
# s'affiche dans la meme teinte violette unie, donc on dirait toujours "pleine" quelle que soit la
# Value reelle (particulierement visible sur un lot d'un seul fichier : Value reste a 0 tout le
# temps du traitement, donc la barre devrait paraitre vide, pas pleine). $couleurFond separe
# maintenant la couleur de fond de celle de la barre - $THEME.Surface (blanc en mode clair) par
# defaut, pour un vrai contraste rempli/vide.
function Definir-CouleurBarreProgression($barre, [System.Drawing.Color]$couleur, [System.Drawing.Color]$couleurFond = $THEME.Surface) {
    try {
        $bgrBarre = [IntPtr]($couleur.B -shl 16 -bor $couleur.G -shl 8 -bor $couleur.R)
        $bgrFond = [IntPtr]($couleurFond.B -shl 16 -bor $couleurFond.G -shl 8 -bor $couleurFond.R)
        [void][NativeMethodsTheme]::SendMessage($barre.Handle, 0x409, [IntPtr]0, $bgrBarre)  # PBM_SETBARCOLOR
        [void][NativeMethodsTheme]::SendMessage($barre.Handle, 0x2001, [IntPtr]0, $bgrFond)  # PBM_SETBKCOLOR
    } catch { }
}

# Restylage plat d'un bouton (FlatStyle natif, pas de degrade/relief Windows 95) selon son role :
#  "principal"  = CTA plein (fond violet, texte blanc, gras) - une seule occurrence par ecran
#  "chaud"      = action de reprise/alerte douce (fond orange) - ex. Relancer les echecs
#  "danger"     = action d'interruption (fond rouge attenue) - ex. Annuler
#  "secondaire" = contour violet, fond blanc - la masse des boutons d'action normale
#  "discret"    = texte seul, pas de fond ni de bordure - actions annexes (Historique, journal...)
function Rendre-BoutonPlat($bouton, [string]$role = "secondaire") {
    $bouton.FlatStyle = "Flat"
    $bouton.Cursor = "Hand"
    $bouton.FlatAppearance.BorderSize = 1
    switch ($role) {
        "principal" {
            $bouton.BackColor = $THEME.AccentPrincipal
            $bouton.ForeColor = $THEME.AccentPrincipalTxt
            $bouton.FlatAppearance.BorderColor = $THEME.AccentPrincipal
            $bouton.FlatAppearance.MouseOverBackColor = $THEME.FondBanniere
            $bouton.Font = New-Object System.Drawing.Font($bouton.Font.FontFamily, $bouton.Font.Size, [System.Drawing.FontStyle]::Bold)
        }
        "chaud" {
            $bouton.BackColor = $THEME.AccentChaud
            $bouton.ForeColor = [System.Drawing.Color]::White
            $bouton.FlatAppearance.BorderColor = $THEME.AccentChaud
            $bouton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xCC, 0x48, 0x18)
        }
        "danger" {
            $bouton.BackColor = $THEME.Surface
            $bouton.ForeColor = $THEME.AccentDanger
            $bouton.FlatAppearance.BorderColor = $THEME.AccentDanger
            $bouton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xFD, 0xEC, 0xEC)
        }
        "discret" {
            $bouton.BackColor = $THEME.FondApp
            $bouton.ForeColor = $THEME.TexteSecondaire
            $bouton.FlatAppearance.BorderSize = 0
            $bouton.FlatAppearance.MouseOverBackColor = $THEME.Bordure
        }
        default {
            $bouton.BackColor = $THEME.Surface
            $bouton.ForeColor = $THEME.AccentPrincipal
            $bouton.FlatAppearance.BorderColor = $THEME.AccentPrincipal
            $bouton.FlatAppearance.MouseOverBackColor = $THEME.AccentDoux
        }
    }
    # 16/10/2026 : coins arrondis sur tous les boutons (voir Definir-RegionArrondie et le
    # commentaire du THEME plus haut) - fixe tout de suite (le bouton a deja sa taille reelle a
    # cet instant, voir plus haut, tous les appels existants font Size puis Rendre-BoutonPlat) et
    # recalcule a chaque redimensionnement reel du controle (barre de titre maximisee/restauree,
    # DPI...), pas seulement a la creation.
    Definir-RegionArrondie $bouton $THEME.RayonArrondi
    $bouton.Add_Resize({ param($sender, $e) Definir-RegionArrondie $sender $THEME.RayonArrondi })
}

# Rendu "plat" d'une ComboBox (10/10/2026, niveau 1 du relookage - avec le NumericUpDown et le
# TabControl, c'etait le widget le plus "fenetre Windows" de l'appli : liste deroulante grise,
# surbrillance bleu systeme). DrawMode=OwnerDrawFixed permet de repeindre nous-memes la zone
# d'affichage (e.Index -lt 0) ET chaque ligne de la liste deroulante, dans les couleurs du theme -
# seule la petite fleche du bouton deroulant reste dessinee par Windows (non accessible sans
# sous-classer le controle, hors scope de ce niveau 1).
function Rendre-ComboBoxPlate($combo) {
    $combo.BackColor = $THEME.Surface
    $combo.ForeColor = $THEME.Texte
    $combo.DrawMode = "OwnerDrawFixed"
    $combo.ItemHeight = 20
    $combo.Add_DrawItem({
        param($sender, $e)
        $estZoneAffichage = $e.Index -lt 0
        $texte = if ($estZoneAffichage) { $sender.Text } else { $sender.Items[$e.Index].ToString() }
        $survol = (-not $estZoneAffichage) -and (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
        $fond = if ($survol) { $THEME.AccentPrincipal } else { $THEME.Surface }
        $couleurTexte = if ($survol) { [System.Drawing.Color]::White } else { $THEME.Texte }
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($fond)), $e.Bounds)
        $zoneTexte = New-Object System.Drawing.Rectangle(($e.Bounds.X + 4), $e.Bounds.Y, ($e.Bounds.Width - 4), $e.Bounds.Height)
        $drapeaux = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $texte, $sender.Font, $zoneTexte, $couleurTexte, $drapeaux)
        if (-not $estZoneAffichage) { $e.DrawFocusRectangle() }
    }.GetNewClosure())
}

# Rendu "plat" des onglets du TabControl (10/10/2026, niveau 1) : remplace les onglets gris a
# relief Windows par des onglets pleins dans les couleurs du theme (accent pour l'onglet actif,
# fond neutre pour les autres) - DrawMode=OwnerDrawFixed + ItemSize impose a l'avance (sinon .NET
# garde la taille/relief natifs tant qu'aucun onglet n'a encore ete peint).
# Remplace le NumericUpDown natif (fleches haut/bas grises, impossibles a repeindre - seule limite
# du niveau 1 du relookage) par un "stepper" maison : zone de texte + deux boutons plats +/-, dans
# les couleurs du theme (10/10/2026, Tomyn a demande d'aller plus loin). Expose Minimum / Maximum /
# DecimalPlaces / Increment / Value comme un vrai NumericUpDown (via Add-Member) pour rester un
# remplacement direct partout ailleurs dans le script (Location, Size, Enabled, ToolTip fonctionnent
# nativement puisque c'est un Panel comme un autre).
function Creer-SelecteurNumerique([int]$largeur = 70, [int]$hauteur = 24) {
    $conteneur = New-Object System.Windows.Forms.Panel
    $conteneur.Size = New-Object System.Drawing.Size($largeur, $hauteur)
    $conteneur.BorderStyle = "FixedSingle"
    $conteneur.BackColor = $THEME.Surface

    $conteneur | Add-Member -MemberType NoteProperty -Name Minimum -Value 0.0
    $conteneur | Add-Member -MemberType NoteProperty -Name Maximum -Value 100.0
    $conteneur | Add-Member -MemberType NoteProperty -Name DecimalPlaces -Value 0
    $conteneur | Add-Member -MemberType NoteProperty -Name Increment -Value 1.0
    $conteneur | Add-Member -MemberType NoteProperty -Name ValeurInterne -Value 0.0

    $largeurBoutons = 18
    $zoneTexte = New-Object System.Windows.Forms.TextBox
    $zoneTexte.BorderStyle = "None"
    # Modifiable au clavier directement (10/10/2026, signale par Tomyn : devoir cliquer sur les
    # petites fleches pour un grand nombre, c'est penible) - avant, ReadOnly=true forcait a passer
    # uniquement par les boutons +/-. Filtre au clavier (KeyPress) + validation a la sortie du
    # champ (Leave) ou sur Entree, pour ne jamais laisser une valeur hors bornes ou non numerique
    # s'installer silencieusement - en cas de saisie invalide (champ vide, "-", texte colle non
    # numerique), on revient simplement a la derniere valeur valide plutot que planter.
    $zoneTexte.ReadOnly = $false
    $zoneTexte.TextAlign = "Center"
    $zoneTexte.BackColor = $THEME.Surface
    $zoneTexte.ForeColor = $THEME.Texte
    $zoneTexte.Width = $largeur - $largeurBoutons - 6
    $zoneTexte.Location = New-Object System.Drawing.Point(3, [int](($hauteur - $zoneTexte.PreferredHeight) / 2))
    $conteneur.Controls.Add($zoneTexte)

    $btnHaut = New-Object System.Windows.Forms.Button
    $btnHaut.Text = "+"
    $btnHaut.FlatStyle = "Flat"
    $btnHaut.FlatAppearance.BorderSize = 0
    $btnHaut.Font = New-Object System.Drawing.Font("Segoe UI", 7)
    $btnHaut.BackColor = $THEME.Surface
    $btnHaut.ForeColor = $THEME.AccentPrincipal
    $btnHaut.Cursor = "Hand"
    $btnHaut.Size = New-Object System.Drawing.Size($largeurBoutons, [int]($hauteur / 2))
    $btnHaut.Location = New-Object System.Drawing.Point(($largeur - $largeurBoutons - 1), 0)
    $conteneur.Controls.Add($btnHaut)

    $btnBas = New-Object System.Windows.Forms.Button
    $btnBas.Text = "-"
    $btnBas.FlatStyle = "Flat"
    $btnBas.FlatAppearance.BorderSize = 0
    $btnBas.Font = New-Object System.Drawing.Font("Segoe UI", 7)
    $btnBas.BackColor = $THEME.Surface
    $btnBas.ForeColor = $THEME.AccentPrincipal
    $btnBas.Cursor = "Hand"
    $btnBas.Size = New-Object System.Drawing.Size($largeurBoutons, [int]($hauteur - [int]($hauteur / 2)))
    $btnBas.Location = New-Object System.Drawing.Point(($largeur - $largeurBoutons - 1), [int]($hauteur / 2))
    $conteneur.Controls.Add($btnBas)

    $conteneur | Add-Member -MemberType ScriptProperty -Name Value -Value {
        [Math]::Round([double]$this.ValeurInterne, [int]$this.DecimalPlaces)
    } -SecondValue {
        param($nouvelleValeur)
        $v = [double]$nouvelleValeur
        if ($v -lt [double]$this.Minimum) { $v = [double]$this.Minimum }
        if ($v -gt [double]$this.Maximum) { $v = [double]$this.Maximum }
        $this.ValeurInterne = $v
        $this.Controls[0].Text = [Math]::Round($v, [int]$this.DecimalPlaces).ToString("F" + [int]$this.DecimalPlaces)
    }

    $btnHaut.Add_Click({ $conteneur.Value = [double]$conteneur.Value + [double]$conteneur.Increment }.GetNewClosure())
    $btnBas.Add_Click({ $conteneur.Value = [double]$conteneur.Value - [double]$conteneur.Increment }.GetNewClosure())

    # Filtre les caracteres au clavier : chiffres, Backspace/Suppr/fleches (touches de controle),
    # un seul separateur decimal si DecimalPlaces > 0, un signe moins en tout debut si Minimum < 0.
    # Tout le reste est bloque a la saisie plutot que d'etre accepte puis rejete a la validation.
    $zoneTexte.Add_KeyPress({
        param($sender, $e)
        if ([char]::IsControl($e.KeyChar)) { return }
        if ([char]::IsDigit($e.KeyChar)) { return }
        $sepDecimal = [System.Globalization.CultureInfo]::CurrentCulture.NumberFormat.NumberDecimalSeparator
        if ([int]$conteneur.DecimalPlaces -gt 0 -and $e.KeyChar.ToString() -eq $sepDecimal -and $sender.Text -notmatch [regex]::Escape($sepDecimal)) { return }
        if ($e.KeyChar -eq '-' -and [double]$conteneur.Minimum -lt 0 -and $sender.SelectionStart -eq 0 -and $sender.Text -notmatch '-') { return }
        $e.Handled = $true
    }.GetNewClosure())

    # Valide/applique la saisie (bornes Min/Max via le setter Value deja en place plus haut) - en
    # cas de texte vide ou invalide (reste improbable vu le filtre au clavier, mais possible via un
    # copier-coller), revient simplement a la derniere valeur valide au lieu de planter.
    $validerSaisieTexte = {
        $texteSaisi = $zoneTexte.Text.Trim()
        if ($texteSaisi -eq "" -or $texteSaisi -eq "-") {
            $conteneur.Value = $conteneur.Value
            return
        }
        try {
            $conteneur.Value = [double]$texteSaisi
        } catch {
            $conteneur.Value = $conteneur.Value
        }
    }.GetNewClosure()

    $zoneTexte.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            & $validerSaisieTexte
            $e.SuppressKeyPress = $true
        }
    }.GetNewClosure())
    $zoneTexte.Add_Leave({ & $validerSaisieTexte }.GetNewClosure())
    # Selectionne tout le texte en prenant le focus, pour pouvoir retaper direct un nouveau nombre
    # sans avoir a effacer l'ancien a la main.
    $zoneTexte.Add_Enter({ $zoneTexte.SelectAll() }.GetNewClosure())

    $conteneur.Value = 0
    return $conteneur
}

# Remplace la CheckBox native (case carree grise, impossible a repeindre sans Add-Type - meme
# limite que le NumericUpDown ci-dessus) par une case maison : un petit Panel repeint a la main
# (case + coche violette) + un Label pour le texte, exposes comme un seul controle avec
# Checked/Text/ForeColor/Add_CheckedChanged pour rester un remplacement direct partout ailleurs
# dans le script (14/10/2026, Tomyn a demande d'aller plus loin sur la coherence visuelle - seul
# widget encore 100% natif Windows apres le niveau 1 du 10/10/2026). Contrairement a
# Creer-SelecteurNumerique, la taille finale (largeur/hauteur) est un parametre du constructeur
# plutot qu'une Size posee apres coup : un Panel composite ne peut pas redimensionner son Label
# interne tout seul si on change juste sa taille globale ensuite. BoiteInterne/LabelInterne sont
# exposes pour pouvoir y attacher une ToolTip (SetToolTip sur le conteneur seul ne se declenche
# pas quand la souris survole un controle enfant).
function Creer-CaseACocher([string]$texte, [int]$largeur, [int]$hauteur = 20, $fond = $THEME.Surface) {
    $tailleCase = 16
    $conteneur = New-Object System.Windows.Forms.Panel
    $conteneur.Size = New-Object System.Drawing.Size($largeur, $hauteur)
    # Fond pose en dur plutot que transparent (rendu Panel peu fiable en transparence) : $fond
    # doit correspondre a ce sur quoi la case est posee - carte blanche de la galerie par defaut,
    # ou $THEME.FondApp explicitement pour les 3 cases posees a meme le fond gris du formulaire
    # (voir plus bas, depuis le retrait des panneaux de section le 14/10/2026).
    $conteneur.BackColor = $fond
    $conteneur.Cursor = "Hand"

    $conteneur | Add-Member -MemberType NoteProperty -Name EstCoche -Value $false
    $conteneur | Add-Member -MemberType NoteProperty -Name GestionnairesChangement -Value (New-Object System.Collections.ArrayList)

    $boiteCase = New-Object System.Windows.Forms.Panel
    $boiteCase.Size = New-Object System.Drawing.Size($tailleCase, $tailleCase)
    $boiteCase.Location = New-Object System.Drawing.Point(0, [int](($hauteur - $tailleCase) / 2))
    $boiteCase.BackColor = $fond
    $boiteCase.Cursor = "Hand"
    $conteneur.Controls.Add($boiteCase)
    $conteneur | Add-Member -MemberType NoteProperty -Name BoiteInterne -Value $boiteCase

    $labelTexte = New-Object System.Windows.Forms.Label
    $labelTexte.Text = $texte
    $labelTexte.AutoSize = $false
    $labelTexte.Size = New-Object System.Drawing.Size(($largeur - $tailleCase - 8), $hauteur)
    $labelTexte.Location = New-Object System.Drawing.Point(($tailleCase + 8), 0)
    $labelTexte.TextAlign = "MiddleLeft"
    $labelTexte.Cursor = "Hand"
    $conteneur.Controls.Add($labelTexte)
    $conteneur | Add-Member -MemberType NoteProperty -Name LabelInterne -Value $labelTexte

    $boiteCase.Add_Paint({
        param($expediteur, $evenement)
        $g = $evenement.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $fond = if ($conteneur.EstCoche) { $THEME.AccentPrincipal } else { $THEME.Surface }
        $bordure = if ($conteneur.EstCoche) { $THEME.AccentPrincipal } else { $THEME.Bordure }
        $g.FillRectangle((New-Object System.Drawing.SolidBrush($fond)), 0, 0, ($tailleCase - 1), ($tailleCase - 1))
        $g.DrawRectangle((New-Object System.Drawing.Pen($bordure, 1.5)), 0, 0, ($tailleCase - 1), ($tailleCase - 1))
        if ($conteneur.EstCoche) {
            $stylo = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
            $g.DrawLines($stylo, @(
                (New-Object System.Drawing.Point(3, 8)),
                (New-Object System.Drawing.Point(6, 12)),
                (New-Object System.Drawing.Point(13, 3))
            ))
        }
    }.GetNewClosure())

    $basculer = {
        $conteneur.EstCoche = -not $conteneur.EstCoche
        $boiteCase.Invalidate()
        foreach ($gestionnaire in $conteneur.GestionnairesChangement) { & $gestionnaire }
    }.GetNewClosure()
    $boiteCase.Add_Click($basculer)
    $labelTexte.Add_Click($basculer)

    $conteneur | Add-Member -Force -MemberType ScriptProperty -Name Checked -Value {
        $this.EstCoche
    } -SecondValue {
        param($valeur)
        $this.EstCoche = [bool]$valeur
        $this.BoiteInterne.Invalidate()
    }
    $conteneur | Add-Member -Force -MemberType ScriptProperty -Name Text -Value {
        $this.LabelInterne.Text
    } -SecondValue {
        param($valeur)
        $this.LabelInterne.Text = $valeur
    }
    $conteneur | Add-Member -Force -MemberType ScriptProperty -Name ForeColor -Value {
        $this.LabelInterne.ForeColor
    } -SecondValue {
        param($valeur)
        $this.LabelInterne.ForeColor = $valeur
    }
    $conteneur | Add-Member -MemberType ScriptMethod -Name Add_CheckedChanged -Value {
        param($gestionnaire)
        [void]$this.GestionnairesChangement.Add($gestionnaire)
    }

    return $conteneur
}

# Trouve le bas reel du contenu d'une section (14/10/2026, corrige une 1re version de ce panneau
# qui coupait le champ "Triangles vises" - celui-ci deborde de son propre calage $yActuel, un
# calcul a la main avait rate ce depassement). Parcourt les controles deja ajoutes directement a
# $form dont le Y de depart tombe entre yHaut (inclus) et yBasLimite (exclu), et renvoie le plus grand bord bas
# (Y + Hauteur) trouve parmi eux - fiable meme si la hauteur d'un champ change plus tard, pas
# besoin de recalculer a la main.
function Obtenir-BasReelSection([int]$yHaut, [int]$yBasLimite) {
    $basMax = $yHaut
    foreach ($ctrl in $form.Controls) {
        $y = $ctrl.Location.Y
        if ($y -ge $yHaut -and $y -lt $yBasLimite) {
            $bas = $y + $ctrl.Height
            if ($bas -gt $basMax) { $basMax = $bas }
        }
    }
    return $basMax
}

# Panneau de fond "carte" derriere chaque section (14/10/2026, 2e volet de la demande "il manque
# des choses" de Tomyn ; coins arrondis ajoutes ensuite suite a "ces rectangles blancs sont tres
# moches" - meme traitement que les cartes de la galerie, voir Ajouter-Vignette plus bas, avec le
# meme bemol : coins arrondis via Region, PAS TESTE PAR CLAUDE visuellement). yBasContenu doit
# etre le bas REEL du contenu (voir Obtenir-BasReelSection ci-dessus), pas la position du
# prochain en-tete - sinon le panneau peut couper le dernier champ de la section s'il deborde de
# son propre calage $yActuel (c'est exactement ce qui s'est passe la 1re fois). yHautSuivant (Y de
# l'en-tete de la section suivante, ou une grande valeur pour la derniere section) sert de garde-
# fou : le bas souhaite est plafonne pour ne jamais chevaucher le panneau suivant, meme si une
# section a peu de marge naturelle avant la suivante (dans ce cas les deux panneaux se touchent
# bord a bord plutot que de se chevaucher). Pousse derriere tous les autres controles (SendToBack)
# au moment de sa creation : comme les controles reels ont tous deja ete ajoutes avant (voir
# l'appel plus bas, une fois tout le haut de l'ecran construit), ils se retrouvent automatiquement
# par-dessus (ordre d'empilement WinForms), sans avoir besoin de reordonner quoi que ce soit
# ailleurs dans le fichier.
function Ajouter-PanneauSection([int]$yHaut, [int]$yBasContenu, [int]$yHautSuivant) {
    $marge = 10
    $top = $yHaut - $marge
    $basSouhaite = $yBasContenu + $marge
    $basMax = $yHautSuivant - $marge
    if ($basSouhaite -gt $basMax) { $basSouhaite = $basMax }
    if ($basSouhaite -lt ($top + 20)) { $basSouhaite = $top + 20 }
    $panneau = New-Object System.Windows.Forms.Panel
    $panneau.Location = New-Object System.Drawing.Point(8, $top)
    $panneau.Size = New-Object System.Drawing.Size(964, ($basSouhaite - $top))
    $panneau.BackColor = $THEME.Surface

    # 16/10/2026 : utilise desormais Definir-RegionArrondie (voir le commentaire du THEME plus
    # haut) au lieu de reconstruire le meme GraphicsPath a la main ici - comportement identique
    # (meme rayon de 10 qu'avant), juste factorise.
    Definir-RegionArrondie $panneau 10

    $panneau.Add_Paint({
        param($expediteur, $evenement)
        $stylo = New-Object System.Drawing.Pen($THEME.Bordure)
        $evenement.Graphics.DrawRectangle($stylo, 0, 0, ($expediteur.Width - 1), ($expediteur.Height - 1))
    })
    $form.Controls.Add($panneau)
    $panneau.SendToBack()
}

function Rendre-OngletsPlats($tabControl) {
    $tabControl.DrawMode = "OwnerDrawFixed"
    $tabControl.SizeMode = "Fixed"
    $tabControl.ItemSize = New-Object System.Drawing.Size(150, 32)
    $tabControl.Add_DrawItem({
        param($sender, $e)
        $page = $sender.TabPages[$e.Index]
        $estActif = ($sender.SelectedIndex -eq $e.Index)
        $fond = if ($estActif) { $THEME.AccentPrincipal } else { $THEME.FondApp }
        $couleurTexte = if ($estActif) { [System.Drawing.Color]::White } else { $THEME.TexteSecondaire }
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($fond)), $e.Bounds)
        $police = if ($estActif) { New-Object System.Drawing.Font($sender.Font, [System.Drawing.FontStyle]::Bold) } else { $sender.Font }
        $drapeaux = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $page.Text, $police, $e.Bounds, $couleurTexte, $drapeaux)
    }.GetNewClosure())
}

# Remplace [System.Windows.Forms.MessageBox]::Show - la derniere boite de dialogue native Windows
# restante dans toute l'appli (icone systeme, bouton OK gris, police Segoe UI par defaut), repeinte
# dans les couleurs du theme (10/10/2026, Tomyn a demande d'aller encore plus loin niveau
# graphique). Memes parametres et memes valeurs de retour que MessageBox::Show ("OK"/"Yes"/"No",
# comparables avec -eq/-ne comme avant) pour remplacer tous les appels existants sans changer leur
# logique - seul le $form.ShowDialog() -> notre propre Form.ShowDialog() change.
# $icone pilote la couleur du bandeau : "Error" = rouge, "Warning" = orange, "Info" (par defaut) =
# violet. $boutons : "OK" (par defaut, un seul bouton) ou "YesNo" (bouton secondaire "Annuler" +
# bouton principal "Continuer quand meme", mappes sur DialogResult Yes/No comme MessageBox).
function Afficher-Boite([string]$message, [string]$titre = "", [string]$boutons = "OK", [string]$icone = "Info") {
    $fenetre = New-Object System.Windows.Forms.Form
    $fenetre.FormBorderStyle = "None"
    $fenetre.StartPosition = "CenterParent"
    $fenetre.BackColor = $THEME.Surface
    $fenetre.Width = 420
    $fenetre.KeyPreview = $true

    $couleurBandeau = switch ($icone) {
        "Error" { $THEME.AccentDanger }
        "Warning" { $THEME.AccentChaud }
        default { $THEME.AccentPrincipal }
    }

    $bandeau = New-Object System.Windows.Forms.Panel
    $bandeau.Dock = "Top"
    $bandeau.Height = 40
    $bandeau.BackColor = $couleurBandeau
    $fenetre.Controls.Add($bandeau)

    $labelTitre = New-Object System.Windows.Forms.Label
    $labelTitre.Text = $titre
    $labelTitre.ForeColor = [System.Drawing.Color]::White
    $labelTitre.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $labelTitre.Dock = "Fill"
    $labelTitre.TextAlign = "MiddleLeft"
    $labelTitre.Padding = New-Object System.Windows.Forms.Padding(15, 0, 0, 0)
    $bandeau.Controls.Add($labelTitre)

    $labelMessage = New-Object System.Windows.Forms.Label
    $labelMessage.Text = $message
    $labelMessage.ForeColor = $THEME.Texte
    $labelMessage.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $labelMessage.Location = New-Object System.Drawing.Point(18, 55)
    $labelMessage.MaximumSize = New-Object System.Drawing.Size(384, 0)
    $labelMessage.AutoSize = $true
    $fenetre.Controls.Add($labelMessage)

    $yBoutons = $labelMessage.Bottom + 22
    $largeurBouton = 160
    $hauteurBouton = 34

    if ($boutons -eq "YesNo") {
        $btnNon = New-Object System.Windows.Forms.Button
        $btnNon.Text = "Annuler"
        $btnNon.Size = New-Object System.Drawing.Size($largeurBouton, $hauteurBouton)
        $btnNon.Location = New-Object System.Drawing.Point((420 - 2 * $largeurBouton - 30), $yBoutons)
        $btnNon.DialogResult = "No"
        Rendre-BoutonPlat $btnNon "secondaire"
        $fenetre.Controls.Add($btnNon)

        $btnOui = New-Object System.Windows.Forms.Button
        $btnOui.Text = "Continuer quand meme"
        $btnOui.Size = New-Object System.Drawing.Size($largeurBouton, $hauteurBouton)
        $btnOui.Location = New-Object System.Drawing.Point((420 - $largeurBouton - 18), $yBoutons)
        $btnOui.DialogResult = "Yes"
        # Role du bouton calcule a part plutot qu'en argument inline : passer directement
        # "(if (...) {...} else {...})" comme argument de fonction declenchait une vraie erreur a
        # l'execution ("Le terme 'if' n'est pas reconnu comme nom d'applet de commande...") -
        # PowerShell n'accepte pas un if/else directement entre parentheses simples en position
        # d'argument (il faudrait $(...), pas (...), pour ca). Trouve le 10/10/2026 suite au
        # signalement de Tomyn (capture d'ecran montrant l'erreur dans le journal juste apres le
        # bilan d'un lot).
        $roleBoutonOui = if ($icone -eq "Error") { "danger" } else { "chaud" }
        Rendre-BoutonPlat $btnOui $roleBoutonOui
        $fenetre.Controls.Add($btnOui)

        $fenetre.AcceptButton = $btnNon
        $fenetre.CancelButton = $btnNon
    } elseif ($boutons -eq "ReprendreTouteAnnuler") {
        # 13/10/2026, Tomyn : utilisee pour la reprise d'un lot interrompu (voir Lancer-Traitement,
        # verification des sorties deja presentes) - "Annuler" (DialogResult Cancel), "Tout refaire"
        # (DialogResult No, orange "chaud" car ca re-depense des credits sur des fichiers deja
        # faits), "Reprendre le lot" (DialogResult Yes, "principal" car c'est le choix recommande
        # qui evite de gaspiller des credits).
        $largeurBouton3 = 150
        $margeCote = 18
        $espaceEntreBoutons = 10

        $btnAnnuler3 = New-Object System.Windows.Forms.Button
        $btnAnnuler3.Text = "Annuler"
        $btnAnnuler3.Size = New-Object System.Drawing.Size($largeurBouton3, $hauteurBouton)
        $btnAnnuler3.Location = New-Object System.Drawing.Point($margeCote, $yBoutons)
        $btnAnnuler3.DialogResult = "Cancel"
        Rendre-BoutonPlat $btnAnnuler3 "secondaire"
        $fenetre.Controls.Add($btnAnnuler3)

        $btnToutRefaire = New-Object System.Windows.Forms.Button
        $btnToutRefaire.Text = "Tout refaire"
        $btnToutRefaire.Size = New-Object System.Drawing.Size($largeurBouton3, $hauteurBouton)
        $btnToutRefaire.Location = New-Object System.Drawing.Point(($margeCote + $largeurBouton3 + $espaceEntreBoutons), $yBoutons)
        $btnToutRefaire.DialogResult = "No"
        Rendre-BoutonPlat $btnToutRefaire "chaud"
        $fenetre.Controls.Add($btnToutRefaire)

        $btnReprendre = New-Object System.Windows.Forms.Button
        $btnReprendre.Text = "Reprendre le lot"
        $btnReprendre.Size = New-Object System.Drawing.Size($largeurBouton3, $hauteurBouton)
        $btnReprendre.Location = New-Object System.Drawing.Point(($margeCote + 2 * ($largeurBouton3 + $espaceEntreBoutons)), $yBoutons)
        $btnReprendre.DialogResult = "Yes"
        Rendre-BoutonPlat $btnReprendre "principal"
        $fenetre.Controls.Add($btnReprendre)

        $fenetre.Width = $margeCote * 2 + 3 * $largeurBouton3 + 2 * $espaceEntreBoutons
        $fenetre.AcceptButton = $btnReprendre
        $fenetre.CancelButton = $btnAnnuler3
    } else {
        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = "OK"
        $btnOk.Size = New-Object System.Drawing.Size($largeurBouton, $hauteurBouton)
        $btnOk.Location = New-Object System.Drawing.Point((420 - $largeurBouton - 18), $yBoutons)
        $btnOk.DialogResult = "OK"
        # Meme correctif que pour $btnOui plus haut (role calcule a part, pas en argument inline).
        $roleBoutonOk = if ($icone -eq "Error") { "danger" } else { "principal" }
        Rendre-BoutonPlat $btnOk $roleBoutonOk
        $fenetre.Controls.Add($btnOk)

        $fenetre.AcceptButton = $btnOk
        $fenetre.CancelButton = $btnOk
    }

    $fenetre.Height = $yBoutons + $hauteurBouton + 28
    # 16/10/2026 : coins arrondis sur la fenetre elle-meme (voir le commentaire du THEME plus
    # haut) - a cet instant Width/Height sont definitifs (toutes les branches ci-dessus les ont
    # deja fixes), donc la Region calculee correspond bien a la taille reelle affichee. Arrondit
    # au passage le bandeau colore du haut (Dock="Top"), qui est un simple Panel rectangulaire :
    # tout ce qui depasse la Region de la fenetre est automatiquement decoupe, meme principe que
    # les cartes de la galerie.
    Definir-RegionArrondie $fenetre ($THEME.RayonArrondi + 3)
    return $fenetre.ShowDialog($form)
}

# Verification de mise a jour (16/10/2026, idee d'amelioration validee "tu peux toutes les
# faire") : compare $VERSION_BUILD_COLORISER a la date du dernier commit GitHub touchant ce
# fichier precis. Pas de comparaison de SHA exact (on ne connait pas encore celui du commit au
# moment d'ecrire le script) - juste "une version plus recente a ete publiee depuis que cette
# copie-ci a ete construite". Declenche uniquement via un bouton (pas automatiquement au
# demarrage) pour ne jamais faire attendre Tomyn apres un appel reseau au lancement de l'appli.
function Verifier-MiseAJourDisponible {
    try {
        $reponse = Invoke-RestMethod -Uri "https://api.github.com/repos/Retrofall59/ColoriseurSTL/commits?path=windows/Coloriser-STL-GUI.ps1&per_page=1" -Headers @{ "User-Agent" = "Coloriser-STL" } -TimeoutSec 8
    } catch {
        Afficher-Boite "Impossible de contacter GitHub pour verifier (pas de connexion, ou GitHub inaccessible pour l'instant).`r`n`r`nDetail : $($_.Exception.Message)" "Verification impossible" "OK" "Warning" | Out-Null
        return
    }
    if (-not $reponse -or $reponse.Count -eq 0) {
        Afficher-Boite "GitHub n'a renvoye aucune information sur ce fichier - verification impossible pour l'instant." "Verification impossible" "OK" "Warning" | Out-Null
        return
    }
    $dateDistante = [DateTime]::Parse($reponse[0].commit.committer.date).ToLocalTime().Date
    if ($dateDistante -gt $script:VERSION_BUILD_COLORISER) {
        Afficher-Boite "Une version plus recente de Coloriser-STL est disponible sur GitHub.`r`n`r`nCette copie date du $($script:VERSION_BUILD_COLORISER.ToString('dd/MM/yyyy')).`r`nLa derniere mise a jour publiee date du $($dateDistante.ToString('dd/MM/yyyy')).`r`n`r`nRecupere la derniere version depuis la session Claude ou le repo GitHub." "Mise a jour disponible" "OK" "Warning" | Out-Null
    } else {
        Afficher-Boite "Cette copie est a jour (version du $($script:VERSION_BUILD_COLORISER.ToString('dd/MM/yyyy')))." "A jour" "OK" "Info" | Out-Null
    }
}

# Petit logo "bobine de filament" dessine a la volee (cercle accent + trou central couleur fond +
# quelques brins) - evite de devoir fournir un fichier .ico externe. Utilise a la fois comme icone
# de fenetre (format Icon) et comme logo dans la banniere (format Image, plus grand).
function Creer-ImageSpool([int]$taille, [System.Drawing.Color]$couleurFond) {
    $bmp = New-Object System.Drawing.Bitmap($taille, $taille)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $pinceauAccent = New-Object System.Drawing.SolidBrush($THEME.AccentPrincipal)
    $pinceauFond = New-Object System.Drawing.SolidBrush($couleurFond)
    $stylo = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, [System.Drawing.Color]::White), [Math]::Max(1, $taille * 0.03))
    $marge = [int]($taille * 0.06)
    $g.FillEllipse($pinceauAccent, $marge, $marge, $taille - 2 * $marge, $taille - 2 * $marge)
    # brins de filament enroule (quelques arcs clairs, pas un cercle parfait pour suggerer l'enroulement)
    for ($i = 0; $i -lt 3; $i++) {
        $r = [int]($taille * (0.30 + $i * 0.11))
        $d = ($taille - $r) / 2.0
        $g.DrawArc($stylo, $d, $d, $r, $r, 20, 220)
    }
    $trou = [int]($taille * 0.30)
    $d2 = ($taille - $trou) / 2.0
    $g.FillEllipse($pinceauFond, $d2, $d2, $trou, $trou)
    $g.Dispose()
    return $bmp
}

# ============================== ECRAN DE LANCEMENT ==============================
# Splash screen (10/10/2026, demande de Tomyn) : fenetre sans bordure, meme violet que la
# banniere, logo "bobine" + nom de l'appli, avec une fine barre qui se remplit pendant que le
# reste du script construit le formulaire principal plus bas - une vraie "entree" dans l'appli
# plutot que de l'ouvrir directement sur le formulaire. Le formulaire principal n'est pas encore
# lance a ce stade (pas de boucle de messages active avant le ShowDialog tout en bas du script),
# donc on pompe nous-memes les messages via [Application]::DoEvents() pendant l'animation - seule
# facon de faire avancer la barre et de laisser la fenetre se peindre (meme technique de DoEvents
# que celle deja utilisee par Ajouter-LigneJournal plus bas).
$splash = New-Object System.Windows.Forms.Form
$splash.FormBorderStyle = "None"
$splash.StartPosition = "CenterScreen"
$splash.Size = New-Object System.Drawing.Size(380, 230)
$splash.BackColor = $THEME.FondBanniere
$splash.ShowInTaskbar = $false
$splash.TopMost = $true

try {
    $bmpSplash = Creer-ImageSpool 90 $THEME.FondBanniere
    $logoSplash = New-Object System.Windows.Forms.PictureBox
    $logoSplash.Image = $bmpSplash
    $logoSplash.SizeMode = "AutoSize"
    $logoSplash.Location = New-Object System.Drawing.Point((($splash.Width - 90) / 2), 28)
    $splash.Controls.Add($logoSplash)
} catch { }

$titreSplash = New-Object System.Windows.Forms.Label
$titreSplash.Text = "ColoriserSTL"
$titreSplash.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
$titreSplash.ForeColor = [System.Drawing.Color]::White
$titreSplash.BackColor = [System.Drawing.Color]::Transparent
$titreSplash.AutoSize = $true
$splash.Controls.Add($titreSplash)
$titreSplash.Location = New-Object System.Drawing.Point((($splash.Width - $titreSplash.PreferredWidth) / 2), 128)

$sousTitreSplash = New-Object System.Windows.Forms.Label
$sousTitreSplash.Text = "Colorisation de modeles 3D"
$sousTitreSplash.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$sousTitreSplash.ForeColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$sousTitreSplash.BackColor = [System.Drawing.Color]::Transparent
$sousTitreSplash.AutoSize = $true
$splash.Controls.Add($sousTitreSplash)
$sousTitreSplash.Location = New-Object System.Drawing.Point((($splash.Width - $sousTitreSplash.PreferredWidth) / 2), 160)

# Fine barre de progression maison plutot qu'une ProgressBar native (pas besoin du bricolage
# SendMessage utilise ailleurs dans le script juste pour la recolorer) : une piste violette plus
# sombre et un remplissage orange (meme accent que "Relancer les echecs"), qui grandit pendant
# l'animation ci-dessous.
$pisteBarreSplash = New-Object System.Windows.Forms.Panel
$pisteBarreSplash.Size = New-Object System.Drawing.Size(260, 4)
$pisteBarreSplash.Location = New-Object System.Drawing.Point((($splash.Width - 260) / 2), 195)
$pisteBarreSplash.BackColor = [System.Drawing.Color]::FromArgb(0x36, 0x1D, 0x78)
$splash.Controls.Add($pisteBarreSplash)

$remplissageBarreSplash = New-Object System.Windows.Forms.Panel
$remplissageBarreSplash.Size = New-Object System.Drawing.Size(0, 4)
$remplissageBarreSplash.Location = New-Object System.Drawing.Point(0, 0)
$remplissageBarreSplash.BackColor = $THEME.AccentChaud
$pisteBarreSplash.Controls.Add($remplissageBarreSplash)

$splash.Show()
$splash.Refresh()

$etapesSplash = 24
for ($i = 1; $i -le $etapesSplash; $i++) {
    $remplissageBarreSplash.Width = [int]($pisteBarreSplash.Width * $i / $etapesSplash)
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 28
}

# ============================== FENETRE ==============================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Colorisation de modeles 3D en lot (Meshy)"
# +HauteurBanniere par rapport a l'original (970 -> plus bas, voir bannerie ci-dessous) : tout le
# reste du formulaire garde ses coordonnees d'origine inchangees, seul le point de depart
# ($yActuel plus bas) est translate vers le bas d'autant.
#
# Important : on garde ici la taille de CONCEPTION complete (1080+banniere) sans la plafonner tout
# de suite a l'ecran. L'ajustement a l'ecran reel se fait tout en bas du script, juste avant
# ShowDialog() - voir le commentaire la-bas pour pourquoi (resume : $onglets.Anchor, plus bas,
# calcule sa marge par rapport au bord bas de la fenetre au moment ou on lui donne son ancrage ; si
# on retrecit la fenetre AVANT que les onglets existent, cette marge part en negatif et l'onglet
# deborde quand meme hors ecran au lieu de retrecir avec elle - d'ou le "toujours pareil" de Tomyn
# sur le essai precedent. En retrecissant seulement a la toute fin, une fois l'ancrage etabli sur
# la taille complete, le retrecissement fait vraiment reduire la hauteur de $onglets comme prevu).
# Largeur passee de 1000 a 2000 le 17/10/2026 (Tomyn, captures annotees d'une fleche, confirme
# ensuite "deplacer tout le bloc fichier 3D resultats et avancement la ou je t'ai mis la fleche") :
# $onglets (le bloc entier des 3 onglets - Fichiers 3D, Resultats colorises, Avancement - inchange
# a l'interieur) est deplace plus bas dans ce fichier pour se placer a cote de "Connexion aux
# fournisseurs" (voir $onglets.Location : x=1000, calcule a partir du VRAI record de largeur de
# tous les controles du formulaire - 985px, "Ajouter a la file"/"Hist. fichiers" - cf. le
# commentaire juste au-dessus de $onglets) - 2000px de large pour lui faire de la place a cet
# endroit (x=1000 + 955 de large + marge) sans rien chevaucher.
$form.Size = New-Object System.Drawing.Size(2000, (1080 + $THEME.HauteurBanniere))
# Fenetre redimensionnable (agrandir/reduire, bouton Agrandir dans la barre de titre) - la zone des
# onglets (galeries, journal) est ancree pour suivre le redimensionnement (voir $onglets.Anchor
# plus bas) : le reste au-dessus (champs, boutons) garde sa position fixe, d'ou une taille minimale
# qui laisse quand meme la place aux champs du haut plus un peu de zone d'onglets visible.
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true
$form.MinimumSize = New-Object System.Drawing.Size(1000, 650)
$form.StartPosition = "CenterScreen"
$form.AllowDrop = $true
$form.BackColor = $THEME.FondApp
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Icone de fenetre + de la zone de notification : le petit logo "bobine" plutot que l'icone
# generique Windows (Creer-ImageSpool defini dans le bloc THEME plus haut).
try {
    $bmpIcone = Creer-ImageSpool 64 $THEME.FondApp
    $form.Icon = [System.Drawing.Icon]::FromHandle($bmpIcone.GetHicon())
} catch { }

# Icone dans la zone de notification Windows, pour prevenir a la fin d'un lot sans avoir a
# garder l'oeil sur la fenetre (utile pour un lot de 15-20 min lance puis laisse de cote).
$script:notifIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifIcon.Icon = if ($form.Icon) { $form.Icon } else { [System.Drawing.SystemIcons]::Information }
$script:notifIcon.Text = "ColoriserSTL"
$script:notifIcon.Visible = $true
$form.Add_FormClosing({ $script:notifIcon.Visible = $false; $script:notifIcon.Dispose() }.GetNewClosure())

# --- Banniere de titre (nouveau le 10/10/2026) : bande violette en haut de fenetre avec le logo
# et le nom de l'appli - premier reflexe pour casser le gris uniforme d'une fenetre WinForms par
# defaut. Dock="Top" : prend sa place sans toucher aux coordonnees de tout ce qui suit, qui se
# contente de partir plus bas (voir $yActuel). ---
$banniere = New-Object System.Windows.Forms.Panel
$banniere.Dock = "Top"
$banniere.Height = $THEME.HauteurBanniere
$banniere.BackColor = $THEME.FondBanniere
$form.Controls.Add($banniere)

try {
    $bmpLogoBanniere = Creer-ImageSpool 36 $THEME.FondBanniere
    $logoBanniere = New-Object System.Windows.Forms.PictureBox
    $logoBanniere.Image = $bmpLogoBanniere
    $logoBanniere.Size = New-Object System.Drawing.Size(36, 36)
    $logoBanniere.Location = New-Object System.Drawing.Point(14, (($THEME.HauteurBanniere - 36) / 2))
    $logoBanniere.SizeMode = "AutoSize"
    $banniere.Controls.Add($logoBanniere)
} catch { }

$titreBanniere = New-Object System.Windows.Forms.Label
$titreBanniere.Text = "ColoriserSTL"
$titreBanniere.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$titreBanniere.ForeColor = [System.Drawing.Color]::White
$titreBanniere.BackColor = [System.Drawing.Color]::Transparent
$titreBanniere.AutoSize = $true
$titreBanniere.Location = New-Object System.Drawing.Point(58, 9)
$banniere.Controls.Add($titreBanniere)

$sousTitreBanniere = New-Object System.Windows.Forms.Label
$sousTitreBanniere.Text = "Colorisation de modeles 3D en lot, via Meshy ou Tripo"
$sousTitreBanniere.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$sousTitreBanniere.ForeColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$sousTitreBanniere.BackColor = [System.Drawing.Color]::Transparent
$sousTitreBanniere.AutoSize = $true
$sousTitreBanniere.Location = New-Object System.Drawing.Point(59, 32)
$banniere.Controls.Add($sousTitreBanniere)

# Bascule mode sombre (16/10/2026) - dans la banniere plutot qu'ailleurs : toujours visible, meme
# en haut d'une appli qui scrolle, et c'est l'endroit le plus logique pour un reglage d'apparence.
$btnModeSombre = New-Object System.Windows.Forms.Button
$btnModeSombre.Text = "Mode sombre"
$btnModeSombre.Size = New-Object System.Drawing.Size(110, 28)
$btnModeSombre.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 125), (($THEME.HauteurBanniere - 28) / 2))
$btnModeSombre.Anchor = "Top, Right"
$btnModeSombre.FlatStyle = "Flat"
$btnModeSombre.ForeColor = [System.Drawing.Color]::White
$btnModeSombre.BackColor = $THEME.FondBanniere
$btnModeSombre.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$btnModeSombre.Cursor = "Hand"
$btnModeSombre.Add_Click({ Basculer-ModeSombre })
$banniere.Controls.Add($btnModeSombre)

$yActuel = 15 + $THEME.HauteurBanniere

function Ajouter-Label($texte, $x, $y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $texte
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.AutoSize = $true
    # Gras + couleur du theme (10/10/2026) plutot que le label gris par defaut : ce sont les
    # intitules de champs (cle API, dossier, etc.), donc une info structurelle, pas une
    # decoration - les distinguer du texte secondaire les rend plus faciles a scanner.
    $label.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
    $label.ForeColor = $THEME.Texte
    $form.Controls.Add($label)
}

# 13/10/2026, Tomyn : refonte visuelle - l'ecran de configuration etait un long mur de champs a
# plat, sans hierarchie. Ajoute un en-tete pour chaque grande section (une fine bande accent +
# un titre en majuscules) SANS deplacer ni toucher a la logique d'aucun controle existant : juste
# insere entre eux, aux memes emplacements $yActuel qu'avant. Meme principe qu'Ajouter-Label :
# ne touche pas $yActuel elle-meme, c'est l'appelant qui l'avance ensuite.
function Ajouter-EnteteSection($texte, $y) {
    $barreAccent = New-Object System.Windows.Forms.Panel
    $barreAccent.Location = New-Object System.Drawing.Point(15, $y)
    $barreAccent.Size = New-Object System.Drawing.Size(930, 2)
    $barreAccent.BackColor = $THEME.AccentPrincipal
    $form.Controls.Add($barreAccent)

    # 14/10/2026, Tomyn : capture d'ecran montrant la galerie de fichiers coupee en bas de fenetre
    # suite a l'ajout de ces en-tetes (la zone de config du haut a grossi d'environ 150-190px sans
    # laisser plus de place en dessous) - offset et police legerement reduits ici, plus
    # l'espacement $yActuel += 28 (au lieu de 34) aux 4 points d'appel, pour recuperer un peu de
    # hauteur sans supprimer la hierarchie visuelle elle-meme.
    $labelSection = New-Object System.Windows.Forms.Label
    $labelSection.Text = $texte.ToUpper()
    $labelSection.Location = New-Object System.Drawing.Point(15, ($y + 6))
    $labelSection.AutoSize = $true
    $labelSection.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $labelSection.ForeColor = $THEME.AccentPrincipal
    $form.Controls.Add($labelSection)
}

# --- Cles API : deux fournisseurs possibles, chacun optionnel individuellement (voir plus bas
# pour la validation "au moins une des deux" et le menu de choix du fournisseur) ---
function Charger-CleDepuisFichier($chemin) {
    if (-not (Test-Path $chemin)) { return "" }
    try {
        $secure = Get-Content $chemin | ConvertTo-SecureString
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    } catch { return "" }
}

$yBlocConnexion = $yActuel
Ajouter-EnteteSection "Connexion aux fournisseurs" $yActuel
$yActuel += 28
Ajouter-Label "Cle API Meshy (meshy.ai/settings/api) :" 15 $yActuel
$yActuel += 20
$txtCleApi = New-Object System.Windows.Forms.TextBox
$txtCleApi.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtCleApi.Size = New-Object System.Drawing.Size(780, 24)
$txtCleApi.UseSystemPasswordChar = $true
$txtCleApi.Text = Charger-CleDepuisFichier $CheminCleChiffree
$form.Controls.Add($txtCleApi)

$btnVoirCle = New-Object System.Windows.Forms.Button
$btnVoirCle.Text = "Afficher"
$btnVoirCle.Location = New-Object System.Drawing.Point(805, ($yActuel - 1))
$btnVoirCle.Size = New-Object System.Drawing.Size(85, 26)
$btnVoirCle.Add_Click({
    $txtCleApi.UseSystemPasswordChar = -not $txtCleApi.UseSystemPasswordChar
    $btnVoirCle.Text = if ($txtCleApi.UseSystemPasswordChar) { "Afficher" } else { "Masquer" }
})
$form.Controls.Add($btnVoirCle)
$yActuel += 30

Ajouter-Label "Cle API Tripo (optionnelle, fournisseur de secours) :" 15 $yActuel
$yActuel += 20
$txtCleApiTripo = New-Object System.Windows.Forms.TextBox
$txtCleApiTripo.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtCleApiTripo.Size = New-Object System.Drawing.Size(780, 24)
$txtCleApiTripo.UseSystemPasswordChar = $true
$txtCleApiTripo.Text = Charger-CleDepuisFichier $CheminCleTripoChiffree
$form.Controls.Add($txtCleApiTripo)

$btnVoirCleTripo = New-Object System.Windows.Forms.Button
$btnVoirCleTripo.Text = "Afficher"
$btnVoirCleTripo.Location = New-Object System.Drawing.Point(805, ($yActuel - 1))
$btnVoirCleTripo.Size = New-Object System.Drawing.Size(85, 26)
$btnVoirCleTripo.Add_Click({
    $txtCleApiTripo.UseSystemPasswordChar = -not $txtCleApiTripo.UseSystemPasswordChar
    $btnVoirCleTripo.Text = if ($txtCleApiTripo.UseSystemPasswordChar) { "Afficher" } else { "Masquer" }
})
$form.Controls.Add($btnVoirCleTripo)
$yActuel += 30

# --- Choix du fournisseur : ne propose que ceux dont une cle est renseignee, se met a jour en
# direct pendant la frappe plutot que d'exiger un fournisseur precis a tout prix. ---
Ajouter-Label "Fournisseur a utiliser :" 15 $yActuel
$menuFournisseur = New-Object System.Windows.Forms.ComboBox
$menuFournisseur.Location = New-Object System.Drawing.Point(180, ($yActuel - 2))
$menuFournisseur.Size = New-Object System.Drawing.Size(200, 24)
$menuFournisseur.DropDownStyle = "DropDownList"
$form.Controls.Add($menuFournisseur)
$menuFournisseur.Add_SelectedIndexChanged({ Mettre-A-Jour-Estimation })
$yActuel += 28

# --- Mode comparaison : lance Meshy ET Tripo sur chaque fichier, affiche les deux resultats cote
# a cote (galeries separees, voir plus bas) pour choisir celui qui convient le mieux. Desactive le
# choix de fournisseur ci-dessus (plus pertinent dans ce mode) et exige les deux cles API. ---
# Hauteur 34 (pas 20) : le texte est assez long pour parfois passer sur deux lignes selon la
# police reellement installee - une case trop basse coupe la 2e ligne au lieu de l'afficher, et
# chevauche le controle suivant (corrige le 2026-10-07, signale par Tomyn).
$caseComparerFournisseurs = Creer-CaseACocher "Comparer Meshy et Tripo (lance les deux sur chaque fichier, necessite les deux cles API, double le cout en credits)" 930 34 $THEME.FondApp
$caseComparerFournisseurs.Location = New-Object System.Drawing.Point(15, $yActuel)
$caseComparerFournisseurs.Checked = $false
$form.Controls.Add($caseComparerFournisseurs)
$caseComparerFournisseurs.Add_CheckedChanged({
    $menuFournisseur.Enabled = -not $caseComparerFournisseurs.Checked
    Mettre-A-Jour-Estimation
})
$yActuel += 38

# --- Option .obj pour Meshy (ajoutee le 2026-10-07, CONFIRMEE fonctionnelle en conditions
# reelles le meme jour par Tomyn) : pour Meshy, sauter l'etape "Multi-Color Print" (celle qui
# cree la palette a N couleurs facturee en plus) et recuperer directement le .obj + texture de
# l'etape Retexture - meme principe que Tripo (texture puis conversion), moins cher (une seule
# etape facturee au lieu de deux). Cote texture, c'est une image PBR projetee en UV, pas une
# couleur par sommet comme chez Tripo - mais confirme a l'usage : Bambu Studio propose bien sa
# boite de dialogue de correspondance automatique avec ce .obj-la aussi (peut demander de
# "reparer" le maillage avant, normal pour un import OBJ), et le resultat colore est meme plus
# fidele au modele que l'equivalent Tripo (moins "pastelise"). Ignoree en mode comparaison (reste
# sur le Multi-Color Print habituel pour Meshy dans ce mode, pour ne pas complexifier le bilan a
# deux fournisseurs avec une troisieme variante).
# Texte plus court qu'avant (le detail complet est dans l'infobulle juste en dessous) - tient sur
# une seule ligne dans la plupart des cas, mais la hauteur reste a 34 par securite si une police
# plus large force un retour a la ligne.
$caseMeshyObjExperimental = Creer-CaseACocher "Pour Meshy : exporter en .obj texture plutot qu'en .3mf (sans Multi-Color Print, moins cher, couleurs plus fideles - voir l'infobulle)" 930 34 $THEME.FondApp
$caseMeshyObjExperimental.Location = New-Object System.Drawing.Point(15, $yActuel)
$caseMeshyObjExperimental.Checked = $false
$form.Controls.Add($caseMeshyObjExperimental)
$caseMeshyObjExperimental.Add_CheckedChanged({ Mettre-A-Jour-Estimation })

# Infobulle : le detail complet (pourquoi c'est moins cher, pourquoi c'est parfois plus fidele,
# le coup du "reparer le maillage") sans alourdir le texte de la case elle-meme - demande de
# Tomyn de rendre ce choix plus visible dans l'appli, pas seulement dans le README.
$astuceMeshyObj = New-Object System.Windows.Forms.ToolTip
$astuceMeshyObj.AutoPopDelay = 20000
$astuceMeshyObj.InitialDelay = 400
$texteInfobulleMeshyObj = (
    "Au lieu du .3mf habituel (palette a N couleurs figee par Meshy), tu recuperes un .obj texture + son .mtl + son image de texture dans un sous-dossier dedie.`n`n" +
    "A l'ouverture dans Bambu Studio, une boite de dialogue de correspondance automatique des couleurs s'affiche (comme avec un .obj Tripo) - pratique quand tu n'as pas exactement les filaments que Meshy avait choisis. Bambu peut proposer de `"reparer`" le maillage avant : normal pour un import OBJ, pas un signe de probleme.`n`n" +
    "Une seule etape facturee (Retexture) au lieu de deux : moins cher. Confirme a l'usage le 07/10/2026 : couleurs plus fideles au modele que l'equivalent Tripo (moins delavees).`n`n" +
    "A savoir (precise le 08/10/2026) : ni le .obj ni le .3mf ne t'evitent le travail de A a Z. Le .obj te fait gagner le bouton auto de Bambu (pratique, parfois pas fidele). Le .3mf te garantit la bonne palette des le depart, mais sans ce bouton : c'est toi qui assignes les couleurs/slots AMS a la main dans Bambu Studio.`n`n" +
    "Astuce de Tomyn pour un .obj plus fidele : dans la boite de dialogue de correspondance de Bambu Studio, mets le nombre de teintes nettement plus haut que ton nombre reel de filaments (ex. 18-19) avant de lancer le melange automatique avec tes filaments choisis (RYBW ou CMYW par exemple). Ce nombre ne correspond PAS a des filaments en plus - tu gardes les memes 4 filaments physiques dans l'AMS, ca indique juste a Bambu sur combien de paliers repartir le degrade entre eux : plus fin, donc plus fidele qu'un simple plaquage de 4 couleurs plates.`n`n" +
    "Revers de la medaille (note par Tomyn le 08/10/2026) : le filament inclus tire le rendu dans un sens ou dans l'autre, logique comme en peinture - du blanc dans la liste pastellise (eclaircit tout), du bleu assombrit. A garder en tete en choisissant les filaments, pas juste le nombre de teintes demande.`n`n" +
    "Ne pas depasser 18-19 teintes (constate par Tomyn le 08/10/2026) : au-dela, certains filaments ne sont plus melanges du tout par Bambu Studio, ce qui annule le benefice de l'astuce au lieu de l'ameliorer."
)
$astuceMeshyObj.SetToolTip($caseMeshyObjExperimental, $texteInfobulleMeshyObj)
# La case etant maintenant un Panel composite (voir Creer-CaseACocher), SetToolTip sur le
# conteneur seul ne se declenche pas si la souris survole directement la case ou le texte -
# il faut l'attacher aussi aux deux controles enfants (14/10/2026).
$astuceMeshyObj.SetToolTip($caseMeshyObjExperimental.BoiteInterne, $texteInfobulleMeshyObj)
$astuceMeshyObj.SetToolTip($caseMeshyObjExperimental.LabelInterne, $texteInfobulleMeshyObj)
$yActuel += 38

# --- Reglage d'assombrissement de la texture .obj Meshy (ajoute le 08/10/2026, demande de Tomyn)
# : precompense cote texture l'eclaircissement du melange automatique Bambu Studio quand le jeu de
# filaments utilise comprend du blanc (voir l'infobulle ci-dessus). Au dixieme de % pres, de 0 a
# 100 - pas de valeur universelle (ca depend des filaments choisis dans Bambu), donc laisse au
# jugement de l'utilisateur plutot que devine automatiquement. Actif uniquement si la case .obj
# Meshy est cochee (desactive sinon, pour eviter toute confusion sur un reglage sans effet).
$libelleAssombrir = New-Object System.Windows.Forms.Label
$libelleAssombrir.Text = "Assombrir la texture .obj (compense le melange Bambu) :"
$libelleAssombrir.Location = New-Object System.Drawing.Point(35, $yActuel)
$libelleAssombrir.Size = New-Object System.Drawing.Size(330, 24)
$libelleAssombrir.Enabled = $false
$form.Controls.Add($libelleAssombrir)

$assombrirTexture = Creer-SelecteurNumerique 70 24
$assombrirTexture.Location = New-Object System.Drawing.Point(370, $yActuel)
$assombrirTexture.Minimum = 0
$assombrirTexture.Maximum = 100
$assombrirTexture.DecimalPlaces = 1
$assombrirTexture.Increment = 0.1
$assombrirTexture.Value = 0
$assombrirTexture.Enabled = $false
$form.Controls.Add($assombrirTexture)

$libellePourcent = New-Object System.Windows.Forms.Label
$libellePourcent.Text = "%"
$libellePourcent.Location = New-Object System.Drawing.Point(445, $yActuel)
$libellePourcent.Size = New-Object System.Drawing.Size(20, 24)
$libellePourcent.Enabled = $false
$form.Controls.Add($libellePourcent)

$astuceAssombrir = New-Object System.Windows.Forms.ToolTip
$astuceAssombrir.AutoPopDelay = 20000
$astuceAssombrir.InitialDelay = 400
$astuceAssombrir.SetToolTip($assombrirTexture,
    "0% = texture inchangee. Augmente si ton melange de filaments Bambu Studio (notamment avec du blanc dedans) rend le resultat trop clair/pastel par rapport au modele. Pas de valeur universelle : a toi de trouver la bonne pour ton jeu de filaments habituel, au dixieme de % pres.")

$caseMeshyObjExperimental.Add_CheckedChanged({
    $libelleAssombrir.Enabled = $caseMeshyObjExperimental.Checked
    $assombrirTexture.Enabled = $caseMeshyObjExperimental.Checked
    $libellePourcent.Enabled = $caseMeshyObjExperimental.Checked
    Mettre-A-Jour-Estimation
})
$yActuel += 28

function Mettre-A-Jour-MenuFournisseur {
    $selectionActuelle = $menuFournisseur.SelectedItem
    $menuFournisseur.Items.Clear()
    if ($txtCleApi.Text) { $menuFournisseur.Items.Add("Meshy") | Out-Null }
    if ($txtCleApiTripo.Text) { $menuFournisseur.Items.Add("Tripo") | Out-Null }
    if ($menuFournisseur.Items.Count -eq 0) {
        $menuFournisseur.Items.Add("(aucune cle renseignee)") | Out-Null
    }
    if ($selectionActuelle -and $menuFournisseur.Items.Contains($selectionActuelle)) {
        $menuFournisseur.SelectedItem = $selectionActuelle
    } else {
        $menuFournisseur.SelectedIndex = 0
    }
}
$txtCleApi.Add_TextChanged({ Mettre-A-Jour-MenuFournisseur })
$txtCleApiTripo.Add_TextChanged({ Mettre-A-Jour-MenuFournisseur })
Mettre-A-Jour-MenuFournisseur

# --- Dossier ou fichier(s) 3D ---
$yBlocSource = $yActuel
Ajouter-EnteteSection "Source" $yActuel
$yActuel += 28
Ajouter-Label "Dossier ou fichier(s) 3D (.stl, .obj, .fbx, .glb, .gltf) ou image (.jpg, .png) :" 15 $yActuel
$yActuel += 20
$txtDossier = New-Object System.Windows.Forms.TextBox
$txtDossier.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtDossier.Size = New-Object System.Drawing.Size(480, 24)
$form.Controls.Add($txtDossier)

$btnParcourir = New-Object System.Windows.Forms.Button
$btnParcourir.Text = "Dossier..."
$btnParcourir.Location = New-Object System.Drawing.Point(500, ($yActuel - 1))
$btnParcourir.Size = New-Object System.Drawing.Size(105, 26)
$form.Controls.Add($btnParcourir)

$btnChoisirFichiers = New-Object System.Windows.Forms.Button
$btnChoisirFichiers.Text = "Fichier(s)..."
$btnChoisirFichiers.Location = New-Object System.Drawing.Point(610, ($yActuel - 1))
$btnChoisirFichiers.Size = New-Object System.Drawing.Size(140, 26)
$form.Controls.Add($btnChoisirFichiers)

$btnActualiser = New-Object System.Windows.Forms.Button
$btnActualiser.Text = "Actualiser la liste"
$btnActualiser.Location = New-Object System.Drawing.Point(755, ($yActuel - 1))
$btnActualiser.Size = New-Object System.Drawing.Size(135, 26)
$form.Controls.Add($btnActualiser)
$yActuel += 30

# --- Dossier de sortie ---
Ajouter-Label "Dossier de sortie (.3mf pour Meshy, dossier .obj pour Tripo) :" 15 $yActuel
$yActuel += 20
$txtDossierSortie = New-Object System.Windows.Forms.TextBox
$txtDossierSortie.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtDossierSortie.Size = New-Object System.Drawing.Size(780, 24)
$form.Controls.Add($txtDossierSortie)

$txtDossierSortie.Size = New-Object System.Drawing.Size(685, 24)

$btnParcourirSortie = New-Object System.Windows.Forms.Button
$btnParcourirSortie.Text = "Parcourir..."
$btnParcourirSortie.Location = New-Object System.Drawing.Point(705, ($yActuel - 1))
$btnParcourirSortie.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnParcourirSortie)
$btnParcourirSortie.Add_Click({
    $dialogue = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialogue.Description = "Choisir ou enregistrer les fichiers colorises"
    if ($dialogue.ShowDialog() -eq "OK") { $txtDossierSortie.Text = $dialogue.SelectedPath }
})

$btnOuvrirSortie = New-Object System.Windows.Forms.Button
$btnOuvrirSortie.Text = "Ouvrir"
$btnOuvrirSortie.Location = New-Object System.Drawing.Point(795, ($yActuel - 1))
$btnOuvrirSortie.Size = New-Object System.Drawing.Size(95, 26)
$form.Controls.Add($btnOuvrirSortie)
$btnOuvrirSortie.Add_Click({
    if (-not $txtDossierSortie.Text -or -not (Test-Path $txtDossierSortie.Text)) {
        Afficher-Boite "Ce dossier n'existe pas encore (il sera cree au premier lancement)." "Dossier introuvable" | Out-Null
        return
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList "`"$($txtDossierSortie.Text)`""
})
$yActuel += 30

# --- Categorie de sujet + prompt predefini (par categorie) + prompt libre ---
# Structure a deux niveaux : la categorie filtre la liste de prompts proposee. Chaque categorie
# a sa propre entree "Autre" (texte libre), et sa propre memoire de dernier texte libre saisi
# (fichier separe par categorie) pour ne pas melanger par exemple le texte libre tape pour un
# personnage avec celui tape pour une piece mecanique.
$script:promptsParCategorie = [ordered]@{
    "Personnage" = [ordered]@{
        "Realiste multicolore"              = "couleurs realistes et coherentes, nettement differenciees selon les elements du personnage (peau, cheveux, vetements, accessoires), sans teinte unique sur l'ensemble"
        "Stylise vif / cartoon"              = "couleurs vives, saturees et stylisees, inspirees des jeux video ou du dessin anime, contrastes marques entre les elements"
        "Armure fantasy"                     = "armure et equipement avec metal, cuir et tissu nettement distincts, reflets metalliques sur les parties en metal, legere patine"
        "Figurine peinte a la main"          = "rendu type figurine de collection peinte a la main, couleurs mates et nuancees, ombrages doux entre les zones"
        "Super-heros / comics"               = "couleurs franches et contrastees type bande dessinee, zones de couleur bien delimitees, pas de degrade"
        "Costume d'epoque"                   = "tissus et matieres d'epoque realistes, couleurs sobres et historiquement coherentes, broderies et details distincts si presents"
        "Science-fiction"                    = "combinaison technique avec des zones distinctes pour le tissu, les plaques rigides, le plastron et la visiere, finition high-tech"
        "Creature / monstre"                 = "ecailles, fourrure ou peau avec des variations de teinte naturelles, cornes, griffes ou dents dans une couleur distincte du corps"
        "Style jouet / chibi"                = "couleurs pastel et douces, rendu mignon type jouet pour enfant, zones de couleur simples et bien separees"
        "Buste / portrait realiste"          = "couleurs de peau realistes et nuancees, details du visage et des cheveux soignes, rendu photorealiste"
        "Autre (texte libre ci-dessous)"     = $null
    }
    "Animal de compagnie" = [ordered]@{
        "Realiste pelage/poil"               = "pelage ou poil avec des couleurs realistes et naturelles, variations de teinte fideles a la robe de l'animal, truffe et coussinets dans une couleur distincte"
        "Portrait souvenir fidele"            = "couleurs aussi fideles que possible a la photo d'origine de l'animal, robe, yeux et marques particulieres bien reconnaissables"
        "Stylise mignon / chibi"              = "couleurs douces et pastel, rendu mignon et simplifie, zones de couleur bien separees sans trop de nuances"
        "Figurine peinte a la main"           = "rendu type figurine de collection peinte a la main, couleurs mates et nuancees, ombrages doux entre les zones du pelage"
        "Chat"                                = "pelage avec des couleurs et motifs realistes (uni, tigre, ecaille ou tachete selon le cas), yeux et truffe bien distincts du pelage"
        "Chien"                               = "pelage avec des couleurs et motifs realistes selon la race, truffe, yeux, coussinets et collier eventuel bien distincts"
        "Oiseau"                              = "plumage avec des couleurs vives et nettement differenciees entre les zones (tete, ailes, poitrine, queue), bec et pattes dans une teinte distincte"
        "Animal de ferme / exotique"          = "pelage, plumage ou peau avec des couleurs realistes et naturelles propres a l'espece, details (cornes, bec, ecailles) bien distincts"
        "Race a poil long"                    = "pelage long et fourni avec des variations de teinte naturelles, meches et degrades doux, sans aplat uniforme"
        "Memorial / hommage"                  = "couleurs fideles et apaisees a la robe reelle de l'animal, rendu doux et soigne, adapte a une piece souvenir"
        "Autre (texte libre ci-dessous)"      = $null
    }
    "Buste / statuette commemorative" = [ordered]@{
        "Portrait fidele et sobre"            = "couleurs de peau et de cheveux realistes et fideles a la photo d'origine, rendu digne et sobre, sans effet stylise"
        "Noir et blanc / sepia"                = "rendu en camaieu de gris ou de sepia, sans couleur vive, effet photo ancienne ou buste classique"
        "Bronze / statue classique"            = "finition type bronze patine ou pierre claire, teinte uniforme et sobre avec de legeres variations de patine"
        "Uniforme / tenue specifique"          = "peau et cheveux realistes, uniforme ou tenue avec des couleurs fideles et nettement distinctes de la peau"
        "Portrait de couple / famille"         = "couleurs realistes et coherentes pour chaque personne representee, bien differenciees entre les sujets"
        "Marbre clair"                         = "teinte uniforme type marbre ou platre clair, tres peu de variation de couleur, rendu epure et intemporel"
        "Medaille / bas-relief"                = "couleur unique ou presque, type metal patine (bronze, laiton ou argent selon le cas), reliefs mis en valeur par l'ombrage naturel"
        "Trophee / recompense"                 = "finition metallique noble (or, argent ou bronze selon le cas), rendu brillant et soigne"
        "Souvenir de ceremonie"                = "couleurs sobres et elegantes, tenue de ceremonie bien distincte de la peau et des cheveux, rendu soigne et discret"
        "Realiste multicolore detaille"        = "couleurs realistes et nettement differenciees pour chaque element (peau, cheveux, vetements, accessoires), rendu detaille et vivant malgre le format buste"
        "Autre (texte libre ci-dessous)"       = $null
    }
    "Decor" = [ordered]@{
        "Materiaux naturels"                 = "pierre, bois, vegetation et eau avec des couleurs naturelles et bien differenciees selon le materiau"
        "Architecture / batiment"            = "pierre, toiture, bois et metal avec des couleurs distinctes et realistes selon chaque materiau de construction"
        "Decor stylise jeu video"            = "couleurs vives et stylisees type jeu video, ambiance coloree et lisible, contrastes marques entre les elements du decor"
        "Paysage miniature"                  = "terrain, vegetation et eau avec des couleurs naturelles variees, rendu type diorama ou maquette"
        "Ruines / antique"                   = "pierre usee et patinee, mousse et vegetation envahissante, couleurs sobres et vieillies"
        "Interieur meuble"                   = "bois, tissu et metal des meubles avec des couleurs distinctes et realistes, ambiance chaleureuse"
        "Diorama fantastique"                = "couleurs riches et legerement surnaturelles, elements magiques mis en valeur par des teintes distinctes"
        "Urbain / moderne"                   = "beton, metal et verre avec des couleurs sobres et realistes, contrastes nets entre les materiaux"
        "Vegetation dense / foret"           = "multiples nuances de vert et de brun, feuillage, troncs et sol bien differencies"
        "Socle de jeu / wargaming"           = "terrain et relief avec des couleurs naturelles variees, textures du sol bien marquees (herbe, roche, sable selon le cas)"
        "Autre (texte libre ci-dessous)"     = $null
    }
    "Terrain / plateau de jeu" = [ordered]@{
        "Hexagones / cases lisibles"          = "cases ou hexagones avec des couleurs nettement differenciees selon le type de terrain (herbe, eau, roche, sable, foret), contrastes marques pour rester lisible a distance"
        "Relief naturel varie"                = "terrain avec des couleurs naturelles variees selon l'altitude et le type de sol, degrades doux entre les zones"
        "Plateau stylise jeu de societe"      = "couleurs vives et franches type jeu de societe moderne, zones bien delimitees et faciles a distinguer d'un coup d'oeil"
        "Carte fantasy"                       = "couleurs riches et legerement stylisees pour les terrains fantastiques (lave, cristal, marais magique selon le cas), contrastes nets entre les zones"
        "Terrain militaire / wargame"         = "couleurs sobres et realistes type terrain militaire (boue, beton, vegetation), marquages de zone bien visibles si presents"
        "Desert / aride"                     = "camaieu de sable, roche et terre avec des variations de teinte naturelles, peu de vegetation"
        "Hivernal / enneige"                  = "camaieu de blanc, gris et bleu clair pour la neige et la glace, elements rocheux ou vegetaux bien distincts en dessous"
        "Urbain / plateau de rue"             = "beton, bitume et batiments avec des couleurs sobres et realistes, marquages au sol bien visibles"
        "Grille / damier technique"           = "couleurs contrastees et constantes entre les cases pour un reperage facile, rendu simple et fonctionnel"
        "Ile / archipel"                      = "camaieu de bleu pour l'eau, vert pour la vegetation et sable clair pour les plages, transitions nettes entre les zones"
        "Autre (texte libre ci-dessous)"      = $null
    }
    "Personnage et decor" = [ordered]@{
        "Scene complete equilibree"          = "personnage et decor avec des couleurs realistes et bien differenciees, equilibre entre le sujet principal et son environnement"
        "Scene d'action"                     = "personnage mis en valeur par des couleurs plus vives que le decor, qui reste dans des teintes plus sobres en arriere-plan"
        "Diorama narratif"                   = "couleurs realistes et variees racontant une scene, chaque element (personnages, decor, accessoires) nettement differencie"
        "Scene historique"                   = "couleurs sobres et historiquement coherentes pour le personnage et le decor, materiaux d'epoque bien distincts"
        "Scene fantastique"                  = "couleurs riches et legerement surnaturelles pour le personnage et son environnement magique"
        "Scene sci-fi"                       = "couleurs technologiques et froides, materiaux metalliques et synthetiques bien differencies entre personnage et decor"
        "Scene quotidienne / realiste"       = "couleurs naturelles et realistes pour l'ensemble de la scene, sans effet stylise"
        "Figurine et socle decore"           = "personnage avec des couleurs bien differenciees, socle avec un decor distinct en couleurs plus sobres"
        "Scene nature"                       = "personnage et environnement naturel avec des couleurs variees et realistes, vegetation et terrain bien distincts"
        "Scene urbaine"                      = "personnage et decor urbain avec des couleurs realistes, materiaux de la ville (beton, metal, verre) bien differencies du personnage"
        "Autre (texte libre ci-dessous)"     = $null
    }
    "Vehicule" = [ordered]@{
        "Carrosserie realiste"                = "carrosserie, vitres, pneus et chrome avec des couleurs realistes et nettement distinctes selon le materiau, reflets metalliques sur la carrosserie"
        "Voiture de course / livree"          = "couleurs vives et contrastees type livree de course, zones de sponsoring ou de numerotation bien delimitees"
        "Vehicule militaire"                  = "camouflage ou teinte unie type vehicule militaire, couleurs mates et sobres, usure legere"
        "Avion / aeronautique"                = "fuselage, ailes, cockpit et reacteurs avec des couleurs realistes et bien differenciees, marquages distincts si presents"
        "Vaisseau spatial / sci-fi"           = "coque technique avec des couleurs froides et metalliques, panneaux et hublots nettement distincts, legers reflets high-tech"
        "Vehicule d'epoque / vintage"         = "carrosserie et interieur avec des couleurs d'epoque realistes, chrome et cuir bien distincts, patine legere"
        "Moto"                                = "carenage, selle, chrome et pneus avec des couleurs realistes et contrastees, finitions nettes entre les parties"
        "Vehicule utilitaire / chantier"      = "carrosserie et elements fonctionnels avec des couleurs sobres et realistes type engin de chantier, marquages de securite distincts si presents"
        "Train / ferroviaire"                 = "wagons et locomotive avec des couleurs realistes et coherentes, marquages et numeros bien distincts de la carrosserie"
        "Bateau"                              = "coque, pont et superstructure avec des couleurs realistes et nettement differenciees, ligne de flottaison distincte si presente"
        "Autre (texte libre ci-dessous)"      = $null
    }
    "Piece / Autre" = [ordered]@{
        "Piece mecanique realiste"           = "couleurs realistes de metal, plastique et caoutchouc, usure et reflets metalliques bien rendus"
        "Objet du quotidien"                 = "couleurs realistes et naturelles correspondant au materiau reel de l'objet"
        "Neutre fonctionnel / prototype"     = "couleurs sobres et distinctes entre les differentes parties, rendu simple adapte a un prototype fonctionnel"
        "Piece auto / moteur"                = "metal, caoutchouc et plastique technique avec des couleurs realistes et des finitions distinctes selon le materiau"
        "Electronique / boitier"             = "plastique, metal et elements techniques avec des couleurs nettes et bien separees entre les parties"
        "Outil / quincaillerie"              = "metal et poignee avec des couleurs realistes et contrastees, finition fonctionnelle"
        "Piece industrielle usee"            = "rouille, peinture ecaillee et metal use, couleurs vieillies et contrastees"
        "Objet design / deco"                = "materiaux nobles (bois, metal, pierre ou verre selon le cas) avec des couleurs raffinees et bien differenciees"
        "Jouet / accessoire"                 = "couleurs vives et franches type plastique de jouet, zones de couleur bien separees"
        "Bijou / objet precieux"             = "finitions metalliques nobles (or, argent ou bronze selon le cas) et pierres ou details avec des couleurs distinctes et un rendu brillant"
        "Autre (texte libre ci-dessous)"     = $null
    }
    "Food / nourriture factice" = [ordered]@{
        "Gateau / patisserie"                 = "glacage, creme, fruits et decorations avec des couleurs appetissantes et nettement differenciees, rendu gourmand et realiste"
        "Plat realiste"                       = "aliments avec des couleurs naturelles et realistes propres a chaque ingredient, nettement differencies les uns des autres"
        "Fruits et legumes"                   = "couleurs vives et naturelles propres a chaque fruit ou legume, peau, chair et feuilles bien distinctes"
        "Glace / dessert froid"               = "couleurs pastel et appetissantes, nappage, toppings et cornet ou pot bien distincts"
        "Boisson / cocktail"                  = "liquide, glacons et garniture avec des couleurs distinctes et un rendu translucide si pertinent"
        "Fast-food / street food"             = "couleurs vives et franches type restauration rapide, emballage et aliment bien differencies"
        "Boulangerie / pain"                  = "croute doree et mie claire bien distinctes, variations de cuisson naturelles"
        "Confiserie / bonbons"                = "couleurs vives et saturees type confiserie, zones de couleur bien separees et nettes"
        "Plateau de fromages / charcuterie"   = "couleurs naturelles et realistes propres a chaque aliment, nettement differenciees entre les pieces du plateau"
        "Maquette miniature gourmande"        = "couleurs appetissantes et realistes adaptees a une miniature decorative, finitions soignees malgre la petite echelle"
        "Autre (texte libre ci-dessous)"      = $null
    }
    "Bijou / vetement fonctionnel" = [ordered]@{
        "Bijou porte au quotidien"             = "finitions metalliques nobles (or, argent ou bronze selon le cas) adaptees a un usage reel, couleurs resistantes et uniformes, sans effet fragile"
        "Accessoire textile souple"            = "couleurs uniformes et resistantes adaptees a une matiere flexible qui va plier et bouger, sans degrade fragile"
        "Pendentif / collier"                  = "chaine et pendentif avec des couleurs nettement distinctes, finition brillante ou mate selon le style voulu"
        "Bague / anneau"                       = "finition metallique uniforme et reguliere sur toute la surface, sans variation parasite due a la petite taille de la piece"
        "Bracelet articule"                    = "couleurs coherentes et uniformes sur l'ensemble des maillons ou segments, adaptees a une piece qui bouge"
        "Broche / epingle"                     = "couleurs nettes et bien delimitees, finition soignee adaptee a un petit accessoire visible de pres"
        "Accessoire de mode colore"            = "couleurs vives et franches type accessoire de mode, zones de couleur bien separees"
        "Style minimaliste / epure"            = "une ou deux couleurs sobres et uniformes, sans degrade ni detail superflu, rendu epure"
        "Boucle d'oreille"                     = "couleurs nettes et symetriques, finition soignee adaptee a une petite piece portee de pres"
        "Accessoire enfant"                    = "couleurs vives, douces et ludiques, zones de couleur simples et bien separees, sans detail fragile"
        "Autre (texte libre ci-dessous)"       = $null
    }
}

$yBlocStyle = $yActuel
Ajouter-EnteteSection "Style et couleurs" $yActuel
$yActuel += 28
Ajouter-Label "Categorie :" 15 $yActuel
$menuCategorie = New-Object System.Windows.Forms.ComboBox
$menuCategorie.Location = New-Object System.Drawing.Point(110, ($yActuel - 2))
$menuCategorie.Size = New-Object System.Drawing.Size(390, 24)
$menuCategorie.DropDownStyle = "DropDownList"
foreach ($nomCategorie in $script:promptsParCategorie.Keys) { $menuCategorie.Items.Add($nomCategorie) | Out-Null }
$menuCategorie.SelectedIndex = 0
$form.Controls.Add($menuCategorie)
$yActuel += 28

Ajouter-Label "Style voulu :" 15 $yActuel
$menuPrompt = New-Object System.Windows.Forms.ComboBox
$menuPrompt.Location = New-Object System.Drawing.Point(110, ($yActuel - 2))
$menuPrompt.Size = New-Object System.Drawing.Size(390, 24)
$menuPrompt.DropDownStyle = "DropDownList"
$yActuel += 28

Ajouter-Label "Prompt envoye a Meshy (modifiable) :" 15 $yActuel
$yActuel += 20
$txtPrompt = New-Object System.Windows.Forms.TextBox
$txtPrompt.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtPrompt.Size = New-Object System.Drawing.Size(875, 24)
$form.Controls.Add($txtPrompt)
$yActuel += 30

function Obtenir-CheminDernierPromptLibre {
    # Un fichier de memoire separe par categorie (slug simple derive du nom de la categorie).
    $slug = ($menuCategorie.SelectedItem.ToString() -replace '[^a-zA-Z0-9]+', '_').Trim('_').ToLower()
    return Join-Path $PSScriptRoot "dernier_prompt_$slug.txt"
}

function Remplir-MenuPrompt {
    # (Re)peuple le menu "Style voulu" avec les entrees de la categorie actuellement selectionnee,
    # et selectionne la premiere entree (qui met a jour le champ de texte via l'evenement ci-dessous).
    $menuPrompt.Items.Clear()
    $categorieActuelle = $script:promptsParCategorie[$menuCategorie.SelectedItem.ToString()]
    foreach ($libelle in $categorieActuelle.Keys) { $menuPrompt.Items.Add($libelle) | Out-Null }
    $menuPrompt.SelectedIndex = 0
}

$menuCategorie.Add_SelectedIndexChanged({ Remplir-MenuPrompt })
Remplir-MenuPrompt
$form.Controls.Add($menuPrompt)

$menuPrompt.Add_SelectedIndexChanged({
    $categorieActuelle = $script:promptsParCategorie[$menuCategorie.SelectedItem.ToString()]
    $texte = $categorieActuelle[$menuPrompt.SelectedItem.ToString()]
    if ($texte -ne $null) {
        $txtPrompt.Text = $texte
    } else {
        # "Autre" : si le champ contient encore un preset (pas une saisie perso en cours), on
        # recharge le dernier prompt libre enregistre pour cette categorie plutot que de vider -
        # evite d'avoir a le retaper a chaque lancement de l'appli.
        if ($categorieActuelle.Values -contains $txtPrompt.Text) {
            $cheminMemoire = Obtenir-CheminDernierPromptLibre
            $txtPrompt.Text = if (Test-Path $cheminMemoire) { Get-Content $cheminMemoire -Raw } else { "" }
        }
        $txtPrompt.Focus() | Out-Null
    }
})

$txtPrompt.Add_TextChanged({
    # N'enregistre que le texte libre ("Autre", valeur null dans le dictionnaire des presets),
    # jamais un preset - pas interessant a retrouver au prochain lancement puisque le menu les
    # propose deja directement. Enregistre dans le fichier de memoire propre a la categorie actuelle.
    $categorieActuelle = $script:promptsParCategorie[$menuCategorie.SelectedItem.ToString()]
    $estModeAutre = $categorieActuelle[$menuPrompt.SelectedItem.ToString()] -eq $null
    if ($estModeAutre) {
        try { Set-Content -Path (Obtenir-CheminDernierPromptLibre) -Value $txtPrompt.Text -NoNewline } catch { }
    }
})

# --- Prompts favoris (16/10/2026, idee d'amelioration validee "Ok pour tout") ---
# Meme principe que les trios favoris de Melange-Couleurs : un favori est un texte de prompt
# explicitement sauve par Tomyn sous un nom, retrouvable ensuite dans une categorie speciale
# "Mes favoris" placee en tete de la liste des categories (voir le peuplement de $menuCategorie
# juste au-dessus). Persiste dans prompts-favoris.json a cote du script, meme format que
# trios-favoris.json cote Melange-Couleurs (objet JSON plat Nom -> Texte).
function Obtenir-CheminPromptsFavoris {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "prompts-favoris.json" } else { Join-Path (Get-Location) "prompts-favoris.json" }
}

function Charger-PromptsFavoris {
    $chemin = Obtenir-CheminPromptsFavoris
    $resultat = [ordered]@{}
    if (Test-Path $chemin) {
        try {
            $donnees = Get-Content $chemin -Raw | ConvertFrom-Json
            foreach ($prop in $donnees.PSObject.Properties) { $resultat[$prop.Name] = $prop.Value }
        } catch { Ecrire-Journal "(Impossible de charger les prompts favoris : $_)" }
    }
    return $resultat
}

function Sauvegarder-PromptsFavoris {
    try {
        $objetPlat = [ordered]@{}
        foreach ($cle in $script:promptsFavoris.Keys) { $objetPlat[$cle] = $script:promptsFavoris[$cle] }
        ($objetPlat | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminPromptsFavoris) -Encoding UTF8 -ErrorAction Stop
    } catch { Ecrire-Journal "(Impossible d'enregistrer les prompts favoris : $_)" }
}

# Reconstruit la categorie "Mes favoris" dans $script:promptsParCategorie a partir de
# $script:promptsFavoris - appelee au demarrage et apres chaque ajout/suppression.
function Reconstruire-CategorieFavoris {
    $categorieFavoris = [ordered]@{}
    foreach ($nom in $script:promptsFavoris.Keys) { $categorieFavoris[$nom] = $script:promptsFavoris[$nom] }
    $categorieFavoris["Autre (texte libre ci-dessous)"] = $null
    $script:promptsParCategorie["Mes favoris"] = $categorieFavoris
}

$script:promptsFavoris = Charger-PromptsFavoris
Reconstruire-CategorieFavoris
# "Mes favoris" vient d'etre ajoutee a la fin du dictionnaire ($script:promptsParCategorie est un
# [ordered], pas de "prepend" natif) - le menu Categorie a deja ete rempli plus haut (sans
# "Mes favoris", qui n'existait pas encore a ce moment-la) : on le vide et on le repeuple ici en
# placant "Mes favoris" en tete explicitement, plutot que de reordonner le dictionnaire.
$menuCategorie.Items.Clear()
$menuCategorie.Items.Add("Mes favoris") | Out-Null
foreach ($nomCategorie in $script:promptsParCategorie.Keys) {
    if ($nomCategorie -ne "Mes favoris") { $menuCategorie.Items.Add($nomCategorie) | Out-Null }
}
$menuCategorie.SelectedIndex = 0

# Petite fenetre de saisie du nom, meme esprit que Demander-NomEtSauvegarderTrio cote
# Melange-Couleurs (fenetre fixe minimaliste, OK/Annuler).
function Demander-NomEtSauvegarderPromptFavori([string]$texteASauver) {
    if ([string]::IsNullOrWhiteSpace($texteASauver)) {
        Afficher-Boite "Le champ de prompt est vide - rien a sauver en favori." "Prompt vide" "OK" "Warning" | Out-Null
        return
    }
    $zoneNomRapide = New-Object System.Windows.Forms.Form
    $zoneNomRapide.Text = "Nom du prompt favori"
    $zoneNomRapide.StartPosition = "CenterParent"
    $zoneNomRapide.FormBorderStyle = "FixedDialog"
    $zoneNomRapide.MaximizeBox = $false
    $zoneNomRapide.MinimizeBox = $false
    $zoneNomRapide.ClientSize = New-Object System.Drawing.Size(320, 110)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nom :"
    $lbl.Location = New-Object System.Drawing.Point(10, 12)
    $lbl.AutoSize = $true
    $zoneNomRapide.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(10, 32)
    $txt.Size = New-Object System.Drawing.Size(300, 24)
    $zoneNomRapide.Controls.Add($txt)
    $btnOKNom = New-Object System.Windows.Forms.Button
    $btnOKNom.Text = "OK"
    $btnOKNom.Location = New-Object System.Drawing.Point(115, 68)
    $btnOKNom.Size = New-Object System.Drawing.Size(90, 28)
    Rendre-BoutonPlat $btnOKNom "principal"
    $btnOKNom.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $zoneNomRapide.Controls.Add($btnOKNom)
    $btnAnnulerNom = New-Object System.Windows.Forms.Button
    $btnAnnulerNom.Text = "Annuler"
    $btnAnnulerNom.Location = New-Object System.Drawing.Point(215, 68)
    $btnAnnulerNom.Size = New-Object System.Drawing.Size(90, 28)
    Rendre-BoutonPlat $btnAnnulerNom "discret"
    $btnAnnulerNom.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $zoneNomRapide.Controls.Add($btnAnnulerNom)
    $zoneNomRapide.AcceptButton = $btnOKNom
    $zoneNomRapide.CancelButton = $btnAnnulerNom
    if ($zoneNomRapide.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $nomChoisi = $txt.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($nomChoisi)) { return }
    if ($nomChoisi -eq "Autre (texte libre ci-dessous)") {
        Afficher-Boite "Ce nom est reserve - choisis-en un autre." "Nom reserve" "OK" "Warning" | Out-Null
        return
    }
    $script:promptsFavoris[$nomChoisi] = $texteASauver
    Sauvegarder-PromptsFavoris
    Reconstruire-CategorieFavoris
    if ($menuCategorie.SelectedItem -and $menuCategorie.SelectedItem.ToString() -eq "Mes favoris") { Remplir-MenuPrompt }
    Afficher-Boite "Prompt '$nomChoisi' enregistre dans tes favoris." "Favori sauvegarde" "OK" "Info" | Out-Null
}

$btnSauverPromptFavori = New-Object System.Windows.Forms.Button
$btnSauverPromptFavori.Text = "Sauver ce prompt en favori"
$btnSauverPromptFavori.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnSauverPromptFavori.Size = New-Object System.Drawing.Size(220, 26)
Rendre-BoutonPlat $btnSauverPromptFavori "secondaire"
$btnSauverPromptFavori.Add_Click({ Demander-NomEtSauvegarderPromptFavori $txtPrompt.Text })
$form.Controls.Add($btnSauverPromptFavori)

# Supprimer n'a de sens que depuis la categorie "Mes favoris", sur une entree qui n'est pas
# "Autre" - desactive sinon plutot que de disparaitre, pour que le bouton reste a sa place.
$btnSupprimerPromptFavori = New-Object System.Windows.Forms.Button
$btnSupprimerPromptFavori.Text = "Supprimer ce favori"
$btnSupprimerPromptFavori.Location = New-Object System.Drawing.Point(245, $yActuel)
$btnSupprimerPromptFavori.Size = New-Object System.Drawing.Size(180, 26)
Rendre-BoutonPlat $btnSupprimerPromptFavori "discret"
$btnSupprimerPromptFavori.Add_Click({
    $categorieActuelle = $menuCategorie.SelectedItem.ToString()
    $nomSelectionne = $menuPrompt.SelectedItem.ToString()
    if ($categorieActuelle -ne "Mes favoris" -or $nomSelectionne -eq "Autre (texte libre ci-dessous)") { return }
    if ((Afficher-Boite "Supprimer le prompt favori '$nomSelectionne' ?" "Confirmer" "YesNo" "Warning") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $script:promptsFavoris.Remove($nomSelectionne)
    Sauvegarder-PromptsFavoris
    Reconstruire-CategorieFavoris
    Remplir-MenuPrompt
})
$form.Controls.Add($btnSupprimerPromptFavori)
$yActuel += 34

# --- Nombre de couleurs + bouton Lancer ---
# 13/10/2026 : memorise la ligne de "Nombre de couleurs" AVANT d'avancer $yActuel pour la ligne
# "Triangles vises" ajoutee juste en dessous - le bouton Lancer doit rester cale sur CETTE ligne
# (comme avant l'ajout du champ triangles), pas sur $yActuel une fois decale, sinon il retombe
# exactement sur la ligne des triangles et les deux se chevauchent (signale par Tomyn).
$yLigneCouleurs = $yActuel
Ajouter-Label "Nombre de couleurs (1-16) :" 15 ($yActuel + 4)
$numCouleurs = Creer-SelecteurNumerique 60 24
$numCouleurs.Location = New-Object System.Drawing.Point(210, $yActuel)
$numCouleurs.Minimum = 1
# Plafond remonte a 16 le 11/10/2026 : l'API Meshy Multi-Color Print refuse tout
# max_colors > 16 ("Invalid values: MaxColors must be 16 or less"), confirme par un
# echec reel de Tomyn. Le plafond avait ete releve a 32 juste avant, sans savoir que
# l'API elle-meme le refusait - retour a 16 pour que le curseur ne propose jamais
# une valeur que Meshy rejettera.
$numCouleurs.Maximum = 16
$numCouleurs.Value = 4
$form.Controls.Add($numCouleurs)

# 13/10/2026, Tomyn : "je lui donne une photo et il me sort un truc tres low poly, sur le site
# Meshy tu peux lui dire combien de triangles tu veux a l'arrivee" - confirme dans la doc API
# Image to 3D : "target_polycount" existe bien (100 a 300 000), mais ne sert a rien tant que
# "should_remesh" n'est pas explicitement a true (par defaut false pour Meshy 6/7 - donc AUCUN
# remaillage ne se produisait jusqu'ici, d'ou le maillage brut, parfois clairsem, de la generation
# IA). Les deux sont maintenant envoyes ensemble a chaque appel "Image to 3D" (voir Lancer-Image3D
# plus bas) - actif uniquement quand le fichier d'entree est une image, ignore sinon. Valeur par
# defaut = 30 000, identique au defaut documente par Meshy pour un remaillage active.
# 15/10/2026 : ce champ sert maintenant aussi de cible pour la simplification automatique d'un
# .stl trop lourd avant Retexture (voir Lancer-Remesh et $SEUIL_TRIANGLES_REMESH_AUTO plus bas) -
# label mis a jour en consequence ("image uniquement" n'est plus exact).
# Texte raccourci pour rester sur une seule ligne avant le champ numerique a x=400 (meme
# contrainte de largeur que l'ancien texte "image uniquement" - le detail complet du seuil
# automatique est dans l'infobulle du champ juste en dessous plutot que dans ce label).
# 16/10/2026 : le seuil auto-remesh couvre maintenant aussi les .obj (voir
# Obtenir-NombreTrianglesOBJ et Obtenir-NombreTriangles plus haut), pas juste le .stl - label
# toujours raccourci pour la meme contrainte de largeur, detail complet dans l'infobulle.
Ajouter-Label "Triangles vises (image, gros .stl/.obj, 100-300000) :" 15 ($yActuel + 32)
$numTriangles = Creer-SelecteurNumerique 90 24
$numTriangles.Location = New-Object System.Drawing.Point(400, ($yActuel + 28))
$numTriangles.Minimum = 100
$numTriangles.Maximum = 300000
$numTriangles.Increment = 1000
$numTriangles.Value = 30000
$form.Controls.Add($numTriangles)

$astuceTriangles = New-Object System.Windows.Forms.ToolTip
$astuceTriangles.AutoPopDelay = 20000
$astuceTriangles.InitialDelay = 400
$astuceTriangles.SetToolTip($numTriangles,
    "Sert a deux choses :`n`n" +
    "- Image en entree : nombre de triangles vise pour le maillage genere par l'IA (Image to 3D).`n`n" +
    "- .stl (binaire) ou .obj en entree, et au-dela de $SEUIL_TRIANGLES_REMESH_AUTO triangles : utilise comme cible pour une simplification automatique (API Remesh de Meshy) avant la colorisation, histoire de ne pas envoyer un maillage inutilement lourd. En dessous de ce seuil (ou pour un .stl ASCII, non detecte), le fichier part tel quel, ce reglage ne sert a rien dans ce cas.")
# 20/10/2026, Tomyn (capture d'ecran) : corrige a +58 (au lieu de +30). Le label et le champ de
# cette ligne "Triangles vises" sont dessines a $yActuel+32/+28 (pas directement a $yActuel), donc
# la ligne occupe en realite jusqu'a +52 (champ de hauteur 24 demarrant a +28) - un +30 plagait
# quasiment la case Smart Topology SUR cette meme ligne au lieu d'en dessous, d'ou le texte
# tronque/chevauchant signale par Tomyn ("ology (meshy-t2.5...", le debut "Pour Meshy, image en
# entree : activer Smart Top" etait cache derriere le champ numerique.
$yActuel += 58

# 20/10/2026, Tomyn (suite a sa question sur la derniere API Meshy) : "Smart Topology", confirme
# reel dans le changelog officiel Meshy - model_type:"smart-topology" + ai_model:"meshy-t2.5",
# disponible sur Image to 3D (celle qu'on utilise). Donne une topologie plus propre/des parties
# bien separees, pensee pour les assets de jeu. Option, pas par defaut : rien ne dit que ca
# convient mieux a TOUS les usages de Tomyn (figurines depuis les croquis de son collegue), donc
# case a cocher plutot qu'un remplacement silencieux du comportement existant.
$caseSmartTopology = Creer-CaseACocher "Pour Meshy, image en entree : activer Smart Topology (meshy-t2.5, topologie plus propre, parties separees - voir l'infobulle)" 930 20 $THEME.FondApp
$caseSmartTopology.Location = New-Object System.Drawing.Point(15, $yActuel)
$caseSmartTopology.Checked = $false
$form.Controls.Add($caseSmartTopology)

$astuceSmartTopology = New-Object System.Windows.Forms.ToolTip
$astuceSmartTopology.AutoPopDelay = 20000
$astuceSmartTopology.InitialDelay = 400
$texteInfobulleSmartTopology = (
    "Modele dedie de Meshy (meshy-t2.5, ajoute le 15/10/2026), pense pour les assets de jeu : maillage plus propre, parties du modele naturellement separees, export uniquement en triangles.`n`n" +
    "Actif uniquement quand le fichier d'entree est une image (Image to 3D) - ignore pour un .stl/.obj deja existant.`n`n" +
    "Le champ `"Triangles vises`" ci-dessus reste utilise comme cible, mais Smart Topology n'accepte que 100 a 30000 (au lieu de 300000 en mode normal) : une valeur au-dessus de 30000 est automatiquement ramenee a 30000 pour cet appel, sans toucher au chiffre affiche dans le champ."
)
$astuceSmartTopology.SetToolTip($caseSmartTopology, $texteInfobulleSmartTopology)
$astuceSmartTopology.SetToolTip($caseSmartTopology.BoiteInterne, $texteInfobulleSmartTopology)
$astuceSmartTopology.SetToolTip($caseSmartTopology.LabelInterne, $texteInfobulleSmartTopology)
$yActuel += 24

# 20/10/2026, Tomyn (meme verification du changelog Meshy) : "geometry_resolution" (standard/2k/4k),
# ajoute le 18/09/2026 en remplacement de l'ancien "ultra_mode" (qu'on n'utilisait pas). Plus de
# detail geometrique fin sur le maillage genere par Image to 3D, pour 5 credits de plus en 2k ou 4k
# (le 4k necessite meshy-7.1/latest, deja notre defaut puisqu'on ne fixe pas ai_model ailleurs que
# pour Smart Topology). Liste deroulante plutot que case a cocher : 3 choix, pas 2.
Ajouter-Label "Qualite du maillage (image en entree) :" 15 $yActuel
$menuGeometrieResolution = New-Object System.Windows.Forms.ComboBox
$menuGeometrieResolution.Location = New-Object System.Drawing.Point(280, ($yActuel - 2))
$menuGeometrieResolution.Size = New-Object System.Drawing.Size(260, 24)
$menuGeometrieResolution.DropDownStyle = "DropDownList"
[void]$menuGeometrieResolution.Items.Add("Standard (par defaut)")
[void]$menuGeometrieResolution.Items.Add("2K (detail fin, +5 credits)")
[void]$menuGeometrieResolution.Items.Add("4K (detail tres fin, +5 credits)")
$menuGeometrieResolution.SelectedIndex = 0
$form.Controls.Add($menuGeometrieResolution)
$menuGeometrieResolution.Add_SelectedIndexChanged({ Mettre-A-Jour-Estimation })

$astuceGeometrieResolution = New-Object System.Windows.Forms.ToolTip
$astuceGeometrieResolution.AutoPopDelay = 20000
$astuceGeometrieResolution.InitialDelay = 400
$astuceGeometrieResolution.SetToolTip($menuGeometrieResolution,
    "Actif uniquement quand le fichier d'entree est une image (Image to 3D) - ignore pour un .stl/.obj deja existant.`n`n" +
    "Standard : comportement habituel, pas de cout supplementaire.`n" +
    "2K / 4K : plus de detail geometrique fin sur le maillage genere, +5 credits. Le 4K necessite le modele meshy-7.1 (utilise par defaut tant qu'aucun modele n'est fixe explicitement ailleurs).")
$yActuel += 28

# 20/10/2026, Tomyn (troisieme relecture du changelog Meshy) : "texture_resolution" existe sur
# l'API Retexture elle-meme (parametre separe de "geometry_resolution" ci-dessus, qui lui ne
# s'applique qu'a la generation du maillage par Image to 3D). Par defaut Meshy applique deja "2k"
# sans qu'on ait besoin de le preciser - ce menu ne change donc rien si on laisse "Standard".
# S'applique a TOUS les fichiers (image ou .stl/.obj deja existant), contrairement a la resolution
# du maillage plus haut. Meshy ne documente aucun surcout chiffre pour ce parametre (contrairement
# aux +5 credits documentes pour geometry_resolution) - pas de credits affiches ici, volontairement,
# plutot que d'inventer un chiffre non confirme.
Ajouter-Label "Resolution des textures (Retexture) :" 15 $yActuel
$menuTextureResolution = New-Object System.Windows.Forms.ComboBox
$menuTextureResolution.Location = New-Object System.Drawing.Point(280, ($yActuel - 2))
$menuTextureResolution.Size = New-Object System.Drawing.Size(260, 24)
$menuTextureResolution.DropDownStyle = "DropDownList"
[void]$menuTextureResolution.Items.Add("Standard / 2K (par defaut)")
[void]$menuTextureResolution.Items.Add("4K (plus net)")
[void]$menuTextureResolution.Items.Add("8K (le plus net)")
$menuTextureResolution.SelectedIndex = 0
$form.Controls.Add($menuTextureResolution)

$astuceTextureResolution = New-Object System.Windows.Forms.ToolTip
$astuceTextureResolution.AutoPopDelay = 20000
$astuceTextureResolution.InitialDelay = 400
$astuceTextureResolution.SetToolTip($menuTextureResolution,
    "S'applique a l'etape Retexture elle-meme, pour tous les fichiers (image ou .stl/.obj deja existant) - contrairement a `"Qualite du maillage`" ci-dessus qui ne concerne que les images.`n`n" +
    "Standard/2K : comportement habituel de Meshy (deja le defaut, meme sans toucher ce menu).`n" +
    "4K / 8K : texture plus nette/detaillee. Meshy ne documente pas de surcout chiffre pour ce choix - a confirmer a l'usage.")
$yActuel += 28

# 20/10/2026, Tomyn : seule des pistes evoquees apres la troisieme relecture du changelog Meshy
# jugee utile ("le seul qui vaut discussion c'est Printability") - "Repair Printability" de Meshy,
# epaissit les parois trop fines pour l'imprimante avant la Retexture (voir
# Lancer-ReparationImprimabilite). Affinee ensuite ("OK pour moi") avec un passage gratuit par
# "Analyze Printability" d'abord (voir Reparer-ParoisSiNecessaire) : la reparation payante (+10
# credits) n'est declenchee QUE si l'analyse detecte reellement des parois trop fines. Case a
# cocher, pas par defaut : ignoree de toute facon pour les petits fichiers qui partent directement
# en Retexture sans tache Meshy prealable a chainer (voir le commentaire dans Coloriser-UnFichier).
# FDM fixe en dur (pas de menu SLA/full_color) : c'est le seul type d'imprimante que Tomyn utilise
# (Bambu Lab, deja le choix fixe pour Multi-Color Print).
$caseReparationParois = Creer-CaseACocher "Pour Meshy : verifier/reparer l'epaisseur des parois avant impression FDM (gratuit si saines, +10 credits si reparation reellement necessaire - voir l'infobulle)" 930 20 $THEME.FondApp
$caseReparationParois.Location = New-Object System.Drawing.Point(15, $yActuel)
$caseReparationParois.Checked = $false
$form.Controls.Add($caseReparationParois)
$caseReparationParois.Add_CheckedChanged({ Mettre-A-Jour-Estimation })

$astuceReparationParois = New-Object System.Windows.Forms.ToolTip
$astuceReparationParois.AutoPopDelay = 20000
$astuceReparationParois.InitialDelay = 400
$texteInfobulleReparationParois = (
    "Verifie D'ABORD l'epaisseur des parois via l'API `"Analyze Printability`" de Meshy (imprimante FDM, epaisseur minimale 1.0 mm) - GRATUIT, ne modifie rien. Si des parois trop fines sont reellement detectees, lance ensuite `"Repair Printability`" (+10 credits) pour les epaissir, AVANT la Retexture (la texture existante serait sinon supprimee par cette etape). Si les parois sont deja saines : 0 credit supplementaire, rien n'est touche.`n`n" +
    "Donne aussi, gratuitement, un diagnostic du maillage (etanche ou pas, trous, aretes non-manifold) dans le journal.`n`n" +
    "Ignoree pour les fichiers assez petits pour partir directement en Retexture sans etape Meshy prealable (Image to 3D ou Remesh) - forcer un Remesh juste pour ca gaspillerait des credits sur des fichiers qui n'en ont pas besoin par ailleurs. Un message l'indique dans le journal le cas echeant."
)
$astuceReparationParois.SetToolTip($caseReparationParois, $texteInfobulleReparationParois)
$astuceReparationParois.SetToolTip($caseReparationParois.BoiteInterne, $texteInfobulleReparationParois)
$astuceReparationParois.SetToolTip($caseReparationParois.LabelInterne, $texteInfobulleReparationParois)
$yActuel += 24

# 20/10/2026, Tomyn ("Oui" sur l'idee suggeree juste apres) : le seuil d'epaisseur (Analyze/Repair
# ci-dessus) depend de la taille REELLE d'impression - chaine par input_task_id, Meshy suppose par
# defaut 150 mm de haut si on ne precise rien ("GLB and input_task_id: 150 mm tall", documente).
# Une piece imprimee a une taille tres differente de 150 mm pourrait donc etre jugee saine (ou
# l'inverse) a tort. Champ facultatif : 0 = on ne precise rien, comportement actuel (suppose
# 150 mm). "intended_print_longest_side_mm" choisi plutot que "..._height_mm" : fonctionne avec
# tous les formats (pas seulement GLB) et correspond a "la plus grande dimension", plus facile a
# mesurer sur une figurine que "la hauteur" qui depend de l'orientation. Plage API documentee :
# 1 a 1000 mm.
Ajouter-Label "Taille d'impression prevue (plus grand cote, mm) :" 15 $yActuel
$numTailleImpression = Creer-SelecteurNumerique 90 24
$numTailleImpression.Location = New-Object System.Drawing.Point(400, ($yActuel - 2))
$numTailleImpression.Minimum = 0
$numTailleImpression.Maximum = 1000
$numTailleImpression.Increment = 5
$numTailleImpression.Value = 0
$form.Controls.Add($numTailleImpression)

$astuceTailleImpression = New-Object System.Windows.Forms.ToolTip
$astuceTailleImpression.AutoPopDelay = 20000
$astuceTailleImpression.InitialDelay = 400
$astuceTailleImpression.SetToolTip($numTailleImpression,
    "Utilise uniquement si la case `"verifier/reparer l'epaisseur des parois`" ci-dessus est cochee.`n`n" +
    "0 (par defaut) : on ne precise rien, Meshy suppose alors 150 mm de haut pour juger si une paroi est trop fine.`n`n" +
    "Renseigne la plus grande dimension prevue de la piece imprimee (en mm) pour que le seuil d'epaisseur (1.0 mm en FDM) soit applique a la bonne echelle - sinon le diagnostic peut se tromper si tu imprimes nettement plus petit ou plus grand que 150 mm.")
$yActuel += 24

# +24 avant l'en-tete (et pas directement a $yActuel) : a ce stade $yActuel ne vaut que +30 par
# rapport a la ligne "Nombre de couleurs", alors que le champ "Triangles vises" juste au-dessus
# occupe jusqu'a +52 sur cette meme base (champ a +28, hauteur 24) - sans cette marge
# supplementaire, l'en-tete de section chevaucherait le bas de ce champ. (Etait monte a +44 le
# temps des panneaux de fond par section, retombe a +24 maintenant qu'ils sont retires - voir plus
# bas, cette marge-la ne sert plus a rien depuis leur retrait.)
$yActuel += 24
$yBlocLancement = $yActuel
Ajouter-EnteteSection "Lancement" $yActuel
$yActuel += 28
$caseHorodatage = Creer-CaseACocher "Garder un historique des essais (ajoute la date/heure au nom du fichier, jamais d'ecrasement)" 600 20 $THEME.FondApp
$caseHorodatage.Location = New-Object System.Drawing.Point(15, ($yActuel + 32))
$caseHorodatage.Checked = $false
$form.Controls.Add($caseHorodatage)

$btnLancer = New-Object System.Windows.Forms.Button
$btnLancer.Text = "Lancer la colorisation"
$btnLancer.Location = New-Object System.Drawing.Point(290, ($yLigneCouleurs - 2))
$btnLancer.Size = New-Object System.Drawing.Size(465, 30)
$btnLancer.Font = New-Object System.Drawing.Font($btnLancer.Font, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnLancer)

$btnAnnuler = New-Object System.Windows.Forms.Button
$btnAnnuler.Text = "Annuler"
$btnAnnuler.Location = New-Object System.Drawing.Point(760, ($yActuel - 2))
$btnAnnuler.Size = New-Object System.Drawing.Size(130, 30)
$btnAnnuler.Visible = $false
$form.Controls.Add($btnAnnuler)

# Meme emplacement que le bouton Annuler : les deux ne sont jamais visibles en meme temps
# (Annuler pendant le traitement, celui-ci seulement apres, et seulement s'il y a eu des echecs).
$btnRelancerEchecs = New-Object System.Windows.Forms.Button
$btnRelancerEchecs.Text = "Relancer les echecs"
$btnRelancerEchecs.Location = New-Object System.Drawing.Point(760, ($yActuel - 2))
$btnRelancerEchecs.Size = New-Object System.Drawing.Size(130, 30)
$btnRelancerEchecs.Visible = $false
$form.Controls.Add($btnRelancerEchecs)
$yActuel += 50

# Estimation du cout : empirique (confirme a l'usage, pas un chiffre
# documente par Meshy), juste un ordre de grandeur pour decider avant de lancer un gros lot.
$txtEstimationCout = New-Object System.Windows.Forms.Label
$txtEstimationCout.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtEstimationCout.Size = New-Object System.Drawing.Size(690, 18)
$txtEstimationCout.ForeColor = [System.Drawing.Color]::DimGray
$txtEstimationCout.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$txtEstimationCout.Text = ""
$form.Controls.Add($txtEstimationCout)

$btnHistorique = New-Object System.Windows.Forms.Button
$btnHistorique.Text = "Historique"
$btnHistorique.Location = New-Object System.Drawing.Point(715, ($yActuel - 2))
$btnHistorique.Size = New-Object System.Drawing.Size(85, 22)
$form.Controls.Add($btnHistorique)

$btnHistoriqueFichiers = New-Object System.Windows.Forms.Button
$btnHistoriqueFichiers.Text = "Hist. fichiers"
$btnHistoriqueFichiers.Location = New-Object System.Drawing.Point(895, ($yActuel - 2))
$btnHistoriqueFichiers.Size = New-Object System.Drawing.Size(90, 22)
$form.Controls.Add($btnHistoriqueFichiers)

$btnEnregistrerJournal = New-Object System.Windows.Forms.Button
$btnEnregistrerJournal.Text = "Enreg. journal"
$btnEnregistrerJournal.Location = New-Object System.Drawing.Point(805, ($yActuel - 2))
$btnEnregistrerJournal.Size = New-Object System.Drawing.Size(85, 22)
$form.Controls.Add($btnEnregistrerJournal)

$btnGraphiqueCredits = New-Object System.Windows.Forms.Button
$btnGraphiqueCredits.Text = "Graphique credits"
$btnGraphiqueCredits.Location = New-Object System.Drawing.Point(715, ($yActuel + 20))
$btnGraphiqueCredits.Size = New-Object System.Drawing.Size(130, 22)
Rendre-BoutonPlat $btnGraphiqueCredits "discret"
$btnGraphiqueCredits.Add_Click({ Afficher-FenetreGraphiqueCredits })
$form.Controls.Add($btnGraphiqueCredits)

$btnEnregistrerJournal.Add_Click({
    if (-not $txtJournal.Text) {
        Afficher-Boite "Le journal est vide pour l'instant." "Rien a enregistrer" | Out-Null
        return
    }
    $dialogue = New-Object System.Windows.Forms.SaveFileDialog
    $dialogue.Filter = "Fichier texte (*.txt)|*.txt"
    $dialogue.FileName = "journal_coloriser_stl_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt"
    if ($dialogue.ShowDialog() -eq "OK") {
        Set-Content -Path $dialogue.FileName -Value $txtJournal.Text
        Afficher-Boite "Journal enregistre." "Fait" | Out-Null
    }
}.GetNewClosure())
$yActuel += 46

$barreProgression = New-Object System.Windows.Forms.ProgressBar
$barreProgression.Location = New-Object System.Drawing.Point(15, $yActuel)
$barreProgression.Size = New-Object System.Drawing.Size(875, 12)
$barreProgression.Style = "Continuous"
$barreProgression.Visible = $false
$form.Controls.Add($barreProgression)
$yActuel += 17

# Sauvegarde/restauration groupee de toute la config (16/10/2026, idee d'amelioration validee
# "TOUS") - meme principe que la fonctionnalite equivalente deja presente cote Melange-Couleurs
# (sauvegarde/restauration groupee en un seul .zip) : regroupe les petits fichiers crees par cet
# outil a cote de lui-meme (prompts favoris, historiques, chemin de Melange-Couleurs) dans une
# seule archive, pratique en cas de changement de PC plutot que de devoir retrouver et recopier
# chaque fichier a la main.
# Les cles API (cle_api.enc / cle_api_tripo.enc) sont VOLONTAIREMENT exclues : chiffrees via DPAPI
# (ConvertTo-SecureString/ConvertFrom-SecureString sans -Key), donc liees au compte Windows ET a la
# machine qui les a chiffrees - les inclure donnerait l'illusion d'une sauvegarde complete alors
# qu'elles seraient illisibles une fois restaurees ailleurs. A ressaisir a la main sur la nouvelle
# machine (le champ se re-chiffre tout seul a la prochaine saisie, comme d'habitude).
function Obtenir-FichiersConfigConnus {
    $fixes = @(
        @{ Nom = "prompts-favoris.json";          Chemin = (Obtenir-CheminPromptsFavoris) }
        @{ Nom = "historique_lots.csv";           Chemin = $CheminHistorique }
        @{ Nom = "historique_fichiers.csv";       Chemin = $CheminHistoriqueFichiers }
        @{ Nom = "chemin_melange_couleurs.json";  Chemin = $CheminConfigMelangeCouleurs }
        @{ Nom = "mode-sombre.json";               Chemin = (Obtenir-CheminPreferenceModeSombre) }
    )
    # "dernier_prompt_<slug>.txt" : un fichier par categorie de style deja essayee (texte libre
    # memorise, voir Obtenir-CheminDernierPromptLibre plus haut) - noms non-fixes (derives du nom de
    # la categorie), decouverts ici au lieu d'une liste figee.
    $dynamiques = @()
    if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
        $dynamiques = @(Get-ChildItem -Path $PSScriptRoot -Filter "dernier_prompt_*.txt" -File -ErrorAction SilentlyContinue | ForEach-Object {
            @{ Nom = $_.Name; Chemin = $_.FullName }
        })
    }
    return ,@($fixes + $dynamiques)
}

$btnSauvegarderConfig = New-Object System.Windows.Forms.Button
$btnSauvegarderConfig.Text = "Sauvegarder ma config..."
$btnSauvegarderConfig.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnSauvegarderConfig.Size = New-Object System.Drawing.Size(195, 28)
Rendre-BoutonPlat $btnSauvegarderConfig "discret"
$btnSauvegarderConfig.Add_Click({
    $fichiersConnus = @(Obtenir-FichiersConfigConnus | Where-Object { Test-Path $_.Chemin })
    if ($fichiersConnus.Count -eq 0) {
        Afficher-Boite "Aucun fichier de config a sauvegarder pour l'instant (rien n'a encore ete cree - prompt favori, historique, etc.)." "Rien a sauvegarder" "OK" "Info" | Out-Null
        return
    }
    $dialogue = New-Object System.Windows.Forms.SaveFileDialog
    $dialogue.Filter = "Archive ZIP (*.zip)|*.zip"
    $dialogue.FileName = "coloriser-stl-config_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    if ($dialogue.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("configstl_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dossierTemp | Out-Null
    try {
        foreach ($f in $fichiersConnus) { Copy-Item -Path $f.Chemin -Destination (Join-Path $dossierTemp $f.Nom) -Force }
        if (Test-Path $dialogue.FileName) { Remove-Item -Path $dialogue.FileName -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dossierTemp, $dialogue.FileName)
        Afficher-Boite "Config sauvegardee ($($fichiersConnus.Count) fichier(s)) :`r`n$($dialogue.FileName)`r`n`r`n(Les cles API ne sont pas incluses - chiffrees pour cette machine/ce compte Windows precis, a ressaisir a la main sur une nouvelle machine.)" "Sauvegarde terminee" "OK" "Info" | Out-Null
    } catch {
        Afficher-Boite "$_" "Erreur" "OK" "Error" | Out-Null
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
})
$form.Controls.Add($btnSauvegarderConfig)

$btnRestaurerConfig = New-Object System.Windows.Forms.Button
$btnRestaurerConfig.Text = "Restaurer ma config..."
$btnRestaurerConfig.Location = New-Object System.Drawing.Point(215, $yActuel)
$btnRestaurerConfig.Size = New-Object System.Drawing.Size(195, 28)
Rendre-BoutonPlat $btnRestaurerConfig "discret"
$btnRestaurerConfig.Add_Click({
    $dialogue = New-Object System.Windows.Forms.OpenFileDialog
    $dialogue.Filter = "Archive ZIP (*.zip)|*.zip"
    if ($dialogue.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    if ((Afficher-Boite "Ceci va REMPLACER ta config actuelle (prompts favoris, historiques, chemin de Melange-Couleurs) par celle de cette archive. Les cles API ne sont pas concernees (jamais incluses dans la sauvegarde).`r`n`r`nContinuer ?" "Restaurer la config" "YesNo" "Warning") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("configstl_" + [guid]::NewGuid().ToString("N"))
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::ExtractToDirectory($dialogue.FileName, $dossierTemp)
        $nombreRestaures = 0
        foreach ($fichierExtrait in (Get-ChildItem -Path $dossierTemp -File)) {
            # Accepte tout fichier de l'archive (fixes + "dernier_prompt_*.txt" dynamiques), sauf
            # les cles API au cas ou une archive plus ancienne (ou faite a la main) les contiendrait
            # - jamais restaurees ici, cf. note sur le chiffrement DPAPI plus haut.
            if ($fichierExtrait.Name -eq "cle_api.enc" -or $fichierExtrait.Name -eq "cle_api_tripo.enc") { continue }
            Copy-Item -Path $fichierExtrait.FullName -Destination (Join-Path $PSScriptRoot $fichierExtrait.Name) -Force
            $nombreRestaures++
        }
        # Les prompts favoris sont charges en memoire une seule fois au demarrage - sans ce
        # rechargement explicite, la restauration ecrirait bien le nouveau fichier sur le disque mais
        # l'appli continuerait d'afficher les anciens favoris jusqu'au prochain lancement.
        $script:promptsFavoris = Charger-PromptsFavoris
        Reconstruire-CategorieFavoris
        if ($menuCategorie.SelectedItem -and $menuCategorie.SelectedItem.ToString() -eq "Mes favoris") { Remplir-MenuPrompt }
        Afficher-Boite "Config restauree ($nombreRestaures fichier(s) trouve(s) dans l'archive)." "Restauration terminee" "OK" "Info" | Out-Null
    } catch {
        Afficher-Boite "$_" "Erreur" "OK" "Error" | Out-Null
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
})
$form.Controls.Add($btnRestaurerConfig)

$btnVerifierMiseAJour = New-Object System.Windows.Forms.Button
$btnVerifierMiseAJour.Text = "Verifier mise a jour"
$btnVerifierMiseAJour.Location = New-Object System.Drawing.Point(415, $yActuel)
$btnVerifierMiseAJour.Size = New-Object System.Drawing.Size(165, 28)
Rendre-BoutonPlat $btnVerifierMiseAJour "discret"
$btnVerifierMiseAJour.Add_Click({ Verifier-MiseAJourDisponible })
$form.Controls.Add($btnVerifierMiseAJour)
$yActuel += 34

# File d'attente de plusieurs lots (16/10/2026, idee validee "tu peux toutes les faire") :
# permet d'empiler plusieurs lots (fichiers + reglages de CE lot-la) et de les enchainer tout
# seul, sans devoir rester devant l'appli entre deux lots pour changer le dossier/prompt/
# fournisseur et recliquer sur Lancer. Chaque lot ajoute est un instantane des reglages actuels
# au moment du clic sur "Ajouter a la file" - modifier les reglages ensuite ne touche pas aux
# lots deja empiles. Lancer-Traitement lit ses reglages directement sur les controles (pas de
# parametres a part la liste de fichiers), donc on les restaure sur les controles juste avant
# chaque lot plutot que de modifier la fonction.
$script:fileAttenteLots = New-Object System.Collections.Generic.List[hashtable]

$listeFileAttente = New-Object System.Windows.Forms.ListBox
$listeFileAttente.Location = New-Object System.Drawing.Point(15, $yActuel)
$listeFileAttente.Size = New-Object System.Drawing.Size(690, 70)
$form.Controls.Add($listeFileAttente)

$btnAjouterFileAttente = New-Object System.Windows.Forms.Button
$btnAjouterFileAttente.Text = "Ajouter a la file"
$btnAjouterFileAttente.Location = New-Object System.Drawing.Point(715, $yActuel)
$btnAjouterFileAttente.Size = New-Object System.Drawing.Size(270, 22)
Rendre-BoutonPlat $btnAjouterFileAttente "discret"
$btnAjouterFileAttente.Add_Click({
    $fichiersInclus = @($script:fichiersAtraiter | Where-Object {
        $case = $script:casesACocher[$_.FullName]
        $case -eq $null -or $case.Checked
    })
    if ($fichiersInclus.Count -eq 0) {
        Afficher-Boite "Aucun fichier a ajouter a la file (coche au moins un fichier d'abord)." "Rien a ajouter" "OK" "Info" | Out-Null
        return
    }
    $lot = @{
        Fichiers = $fichiersInclus
        Fournisseur = $menuFournisseur.SelectedItem
        Prompt = $txtPrompt.Text
        NombreCouleurs = $numCouleurs.Value
        Triangles = $numTriangles.Value
        DossierSortie = $txtDossierSortie.Text
        Horodatage = $caseHorodatage.Checked
        Assombrir = $assombrirTexture.Value
        ComparerFournisseurs = $caseComparerFournisseurs.Checked
        MeshyObjExperimental = $caseMeshyObjExperimental.Checked
        SmartTopology = $caseSmartTopology.Checked
        GeometrieResolution = $menuGeometrieResolution.SelectedIndex
        TextureResolution = $menuTextureResolution.SelectedIndex
        ReparationParois = $caseReparationParois.Checked
        TailleImpression = $numTailleImpression.Value
    }
    [void]$script:fileAttenteLots.Add($lot)
    $promptCourt = if ($lot.Prompt -and $lot.Prompt.Length -gt 40) { $lot.Prompt.Substring(0, 40) + "..." } else { $lot.Prompt }
    [void]$listeFileAttente.Items.Add("$($lot.Fichiers.Count) fichier(s) - $($lot.Fournisseur) - $promptCourt")
}.GetNewClosure())
$form.Controls.Add($btnAjouterFileAttente)

$btnLancerFileAttente = New-Object System.Windows.Forms.Button
$btnLancerFileAttente.Text = "Lancer la file d'attente"
$btnLancerFileAttente.Location = New-Object System.Drawing.Point(715, ($yActuel + 24))
$btnLancerFileAttente.Size = New-Object System.Drawing.Size(270, 22)
Rendre-BoutonPlat $btnLancerFileAttente "chaud"
$btnLancerFileAttente.Add_Click({
    if ($script:fileAttenteLots.Count -eq 0) {
        Afficher-Boite "La file d'attente est vide." "Rien a lancer" "OK" "Info" | Out-Null
        return
    }
    $btnAjouterFileAttente.Enabled = $false
    $btnLancerFileAttente.Enabled = $false
    $btnViderFileAttente.Enabled = $false
    $nombreLots = $script:fileAttenteLots.Count
    try {
        while ($script:fileAttenteLots.Count -gt 0) {
            $lot = $script:fileAttenteLots[0]
            $menuFournisseur.SelectedItem = $lot.Fournisseur
            $txtPrompt.Text = $lot.Prompt
            $numCouleurs.Value = $lot.NombreCouleurs
            $numTriangles.Value = $lot.Triangles
            $txtDossierSortie.Text = $lot.DossierSortie
            $caseHorodatage.Checked = $lot.Horodatage
            $assombrirTexture.Value = $lot.Assombrir
            $caseComparerFournisseurs.Checked = $lot.ComparerFournisseurs
            $caseMeshyObjExperimental.Checked = $lot.MeshyObjExperimental
            # $lot est une Hashtable (pas un PSCustomObject) : une cle absente (vieux lot sauvegarde
            # avant l'ajout de ces 2 options) renvoie simplement $null via l'acces par point, pas
            # besoin (et pas fiable) de passer par .PSObject.Properties dessus.
            $caseSmartTopology.Checked = [bool]$lot.SmartTopology
            $menuGeometrieResolution.SelectedIndex = if ($lot.GeometrieResolution -ne $null) { $lot.GeometrieResolution } else { 0 }
            $menuTextureResolution.SelectedIndex = if ($lot.TextureResolution -ne $null) { $lot.TextureResolution } else { 0 }
            $caseReparationParois.Checked = [bool]$lot.ReparationParois
            $numTailleImpression.Value = if ($lot.TailleImpression -ne $null) { $lot.TailleImpression } else { 0 }
            [System.Windows.Forms.Application]::DoEvents()
            Lancer-Traitement $lot.Fichiers
            $script:fileAttenteLots.RemoveAt(0)
            $listeFileAttente.Items.RemoveAt(0)
        }
        Afficher-Boite "File d'attente terminee ($nombreLots lot(s) traite(s) a la suite)." "File d'attente terminee" "OK" "Info" | Out-Null
    } finally {
        $btnAjouterFileAttente.Enabled = $true
        $btnLancerFileAttente.Enabled = $true
        $btnViderFileAttente.Enabled = $true
    }
}.GetNewClosure())
$form.Controls.Add($btnLancerFileAttente)

$btnViderFileAttente = New-Object System.Windows.Forms.Button
$btnViderFileAttente.Text = "Vider la file"
$btnViderFileAttente.Location = New-Object System.Drawing.Point(715, ($yActuel + 48))
$btnViderFileAttente.Size = New-Object System.Drawing.Size(270, 22)
Rendre-BoutonPlat $btnViderFileAttente "secondaire"
$btnViderFileAttente.Add_Click({
    $script:fileAttenteLots.Clear()
    $listeFileAttente.Items.Clear()
}.GetNewClosure())
$form.Controls.Add($btnViderFileAttente)
$yActuel += 80

$yFinBlocLancement = $yActuel

# 16/10/2026, Tomyn : "trop discrete, il faudrait un vrai barre de progression qui se mete au
# dessus de l'appli et qui bloque toutes action sur les appli tant qu'elle n'est pas finie, style
# comme sur les photo que je viens de t'envoyer, bien sur dans le style de l'application" - meme
# recette que cote Melange-Couleurs (voir le commentaire equivalent la-bas) : une fenetre sans
# bordure, TopMost, aux couleurs de l'appli (violet fonce + remplissage orange), affichee par-dessus
# avec $form.Enabled = $false pour bloquer tout clic sur la fenetre principale pendant le
# traitement. Show() (pas ShowDialog, qui bloquerait le thread et empecherait les DoEvents()
# necessaires pendant le traitement).
$overlayProgression = New-Object System.Windows.Forms.Form
$overlayProgression.FormBorderStyle = "None"
$overlayProgression.ShowInTaskbar = $false
$overlayProgression.TopMost = $true
$overlayProgression.StartPosition = "Manual"
$overlayProgression.Size = New-Object System.Drawing.Size(440, 190)
$overlayProgression.BackColor = $THEME.FondBanniere
# 16/10/2026 : coins arrondis (voir le commentaire du THEME plus haut) - taille fixe des la
# creation ici (contrairement a Afficher-Boite, pas besoin d'attendre une branche conditionnelle),
# donc la Region peut etre posee tout de suite.
Definir-RegionArrondie $overlayProgression ($THEME.RayonArrondi + 5)

$labelOverlayTitre = New-Object System.Windows.Forms.Label
$labelOverlayTitre.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$labelOverlayTitre.ForeColor = [System.Drawing.Color]::White
$labelOverlayTitre.BackColor = [System.Drawing.Color]::Transparent
$labelOverlayTitre.AutoSize = $false
$labelOverlayTitre.AutoEllipsis = $true
$labelOverlayTitre.TextAlign = "MiddleCenter"
$labelOverlayTitre.Location = New-Object System.Drawing.Point(20, 25)
$labelOverlayTitre.Size = New-Object System.Drawing.Size(400, 28)
$overlayProgression.Controls.Add($labelOverlayTitre)

$pisteOverlay = New-Object System.Windows.Forms.Panel
$pisteOverlay.Location = New-Object System.Drawing.Point(30, 75)
$pisteOverlay.Size = New-Object System.Drawing.Size(380, 10)
$pisteOverlay.BackColor = [System.Drawing.Color]::FromArgb(0x36, 0x1D, 0x78)
$overlayProgression.Controls.Add($pisteOverlay)

$remplissageOverlay = New-Object System.Windows.Forms.Panel
$remplissageOverlay.Location = New-Object System.Drawing.Point(0, 0)
$remplissageOverlay.Size = New-Object System.Drawing.Size(0, 10)
$remplissageOverlay.BackColor = $THEME.AccentChaud
$pisteOverlay.Controls.Add($remplissageOverlay)

$labelOverlayPct = New-Object System.Windows.Forms.Label
$labelOverlayPct.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$labelOverlayPct.ForeColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$labelOverlayPct.BackColor = [System.Drawing.Color]::Transparent
$labelOverlayPct.AutoSize = $false
$labelOverlayPct.AutoEllipsis = $true
$labelOverlayPct.TextAlign = "MiddleCenter"
$labelOverlayPct.Location = New-Object System.Drawing.Point(20, 95)
$labelOverlayPct.Size = New-Object System.Drawing.Size(400, 24)
$labelOverlayPct.Text = "0%"
$overlayProgression.Controls.Add($labelOverlayPct)

# Bouton Annuler propre a cette fenetre (14/10/2026, Tomyn, voir $btnAnnuler plus bas) : le
# recouvrement bloque bien $form en dessous, mais Tomyn doit pouvoir annuler un lot en cours sans
# attendre la fin - meme action que $btnAnnuler.Add_Click (annule a la prochaine verification, pas
# instantanement, le traitement en cours sur un fichier va a son terme).
$btnAnnulerOverlay = New-Object System.Windows.Forms.Button
$btnAnnulerOverlay.Text = "Annuler"
$btnAnnulerOverlay.Location = New-Object System.Drawing.Point(225, 135)
$btnAnnulerOverlay.Size = New-Object System.Drawing.Size(100, 28)
$btnAnnulerOverlay.FlatStyle = "Flat"
$btnAnnulerOverlay.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$btnAnnulerOverlay.ForeColor = [System.Drawing.Color]::White
$btnAnnulerOverlay.BackColor = $THEME.FondBanniere
$btnAnnulerOverlay.Cursor = "Hand"
$overlayProgression.Controls.Add($btnAnnulerOverlay)
$btnAnnulerOverlay.Add_Click({
    $script:annulationDemandee = $true
    $btnAnnulerOverlay.Enabled = $false
    $btnAnnulerOverlay.Text = "Annulation..."
})

# Raccourci clavier (16/10/2026) : l'overlay est une fenetre a part qui recoit le focus pendant
# le traitement, Echap ici doit donc etre gere sur l'overlay lui-meme (le KeyDown pose sur $form
# ne recevrait rien tant que l'overlay a le focus).
$overlayProgression.KeyPreview = $true
$overlayProgression.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $btnAnnulerOverlay.Visible -and $btnAnnulerOverlay.Enabled) {
        $e.Handled = $true
        $btnAnnulerOverlay.PerformClick()
    }
}.GetNewClosure())

# Bouton Pause (16/10/2026, idee d'amelioration validee "tu peux toutes les faire") - une vraie
# pause EN PLEIN MILIEU d'un appel API serait trop risquee a faire a l'aveugle (pas de Windows pour
# tester) ; celle-ci est plus modeste mais sure : le fichier EN COURS va a son terme (comme pour
# Annuler), puis la boucle attend avant de passer au suivant - cf. le point de controle juste apres
# "if ($script:annulationDemandee)" dans la boucle du lot plus bas. Bascule Pause/Reprendre sur le
# meme bouton, comme Annuler/Annulation....
$script:pauseDemandeeColoriser = $false
$btnPauseOverlay = New-Object System.Windows.Forms.Button
$btnPauseOverlay.Text = "Pause"
$btnPauseOverlay.Location = New-Object System.Drawing.Point(115, 135)
$btnPauseOverlay.Size = New-Object System.Drawing.Size(100, 28)
$btnPauseOverlay.FlatStyle = "Flat"
$btnPauseOverlay.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$btnPauseOverlay.ForeColor = [System.Drawing.Color]::White
$btnPauseOverlay.BackColor = $THEME.FondBanniere
$btnPauseOverlay.Cursor = "Hand"
$overlayProgression.Controls.Add($btnPauseOverlay)
$btnPauseOverlay.Add_Click({
    $script:pauseDemandeeColoriser = -not $script:pauseDemandeeColoriser
    $btnPauseOverlay.Text = if ($script:pauseDemandeeColoriser) { "Reprendre" } else { "Pause" }
})

function Afficher-OverlayProgression([string]$titre) {
    $labelOverlayTitre.Text = $titre
    $remplissageOverlay.Width = 0
    $labelOverlayPct.Text = "0%"
    $btnAnnulerOverlay.Enabled = $true
    $btnAnnulerOverlay.Text = "Annuler"
    $script:pauseDemandeeColoriser = $false
    $btnPauseOverlay.Text = "Pause"
    $overlayProgression.Location = New-Object System.Drawing.Point(
        ($form.Location.X + [int](($form.Width - $overlayProgression.Width) / 2)),
        ($form.Location.Y + [int](($form.Height - $overlayProgression.Height) / 2))
    )
    # 16/10/2026, Tomyn (constate cote Melange-Couleurs, meme code ici) : "ça bloque completement,
    # ça fait 5 minutes, c'etait pas si long avant" - $form.Enabled = $false (retire) est la seule
    # vraie nouveaute de cette fenetre, tres probablement la cause (conflit de focus/activation
    # entre une fenetre desactivee et une autre TopMost au-dessus, qui ralentit la boucle de
    # messages Windows pendant les DoEvents() frequents du traitement). L'overlay reste affiche
    # par-dessus mais la fenetre principale n'est plus desactivee - les boutons d'action sont deja
    # desactives individuellement a cote de cet appel.
    $overlayProgression.Show()
    $overlayProgression.BringToFront()
    [System.Windows.Forms.Application]::DoEvents()
}

function Mettre-A-Jour-OverlayProgression([int]$pct, [string]$titre = $null, [string]$suffixePct = "") {
    if ($titre) { $labelOverlayTitre.Text = $titre }
    $pctBorne = [Math]::Max(0, [Math]::Min(100, $pct))
    $remplissageOverlay.Width = [int]($pisteOverlay.Width * $pctBorne / 100)
    # 16/10/2026, Tomyn : "ok pour tout" - $suffixePct (optionnel, "" par defaut, aucun changement
    # pour les appels existants) sert a afficher les credits reellement depenses juste a cote du
    # pourcentage, sans surcharger le titre (deja occupe par le nom du fichier + l'ETA).
    $labelOverlayPct.Text = "$pctBorne%$suffixePct"
    [System.Windows.Forms.Application]::DoEvents()
}

function Masquer-OverlayProgression {
    $overlayProgression.Hide()
}

# Disparition automatique de l'overlay quelques secondes apres avoir atteint 100% (16/10/2026,
# Tomyn, sur Melange-Couleurs mais meme recette ici : "il faudrait qu'elle disparaisse au bout
# d'un certain moment ... au bout de 5 ou 6 secondes des qu'elle est a 100% elle disparait
# d'elle-meme") - sans ca, l'overlay restait visible jusqu'au clic sur la boite de dialogue de
# resultat qui suit. Boucle non-bloquante (DoEvents) plutot qu'un Start-Sleep unique, pour garder
# l'IHM reactive pendant l'attente.
function Masquer-OverlayProgressionApresDelai([int]$delaiSecondes = 5) {
    $finAttente = (Get-Date).AddSeconds($delaiSecondes)
    while ((Get-Date) -lt $finAttente) {
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.Application]::DoEvents()
    }
    Masquer-OverlayProgression
}

# Panneaux de fond "carte" derriere chaque section : essayes le 14/10/2026, retires le meme jour
# suite au retour de Tomyn ("c'est encore pire, toujours ces rectangles blancs sur un fond gris" -
# 2e avis negatif de suite sur cette piste, pas la peine d'insister). Ajouter-PanneauSection et
# Obtenir-BasReelSection restent definies plus haut mais ne sont plus appelees ici - fond uni du
# formulaire (THEME.FondApp) derriere les sections, seuls les bandeaux d'en-tete (accent + titre)
# restent comme marqueurs visuels de section.

# --- Onglets : galerie de depart / galerie de resultats / avancement ---
# 17/10/2026, Tomyn (capture annotee d'une fleche, puis confirme "deplacer tout le bloc fichier 3D
# resultats et avancement la ou je t'ai mis la fleche") : bloc entier deplace a cote des sections
# "Source"/"Style et couleurs" (bande vide a droite, visible des l'ouverture) au lieu d'etre
# empile sous "Lancement" tout en bas de la fenetre, ou il finissait coupe par le bas de l'ecran.
# Rien d'autre ne change a l'interieur (3 onglets, galeries, toolbar) - Anchor toujours actif pour
# suivre le redimensionnement de la fenetre.
#
# Deux corrections du 17/10/2026, meme jour, suite aux retours de Tomyn sur les essais precedents
# (images a l'appui) :
# - X : 905 PUIS 960 chevauchaient encore "ca chevauche toujour sur des bouton et texte" - 930px
#   ne suffisait pas : le vrai record de largeur a gauche, c'est "Ajouter a la file"/"Lancer la
#   file d'attente"/"Vider la file" ET "Hist. fichiers", qui vont jusqu'a x=985 (verifie en
#   recalculant TOUTES les positions+largeurs du formulaire par script plutot qu'a l'oeil, vu que
#   deviner a la main avait deja rate deux fois). Passe a 1000 (985+15 de marge).
# - Y : $yBlocSource ("pourkoir ne pas lavoir positionne en hauteur en dessous du bandeau violet")
#   remonte a $yBlocConnexion (tout en haut, juste sous la banniere violette "ColoriserSTL") -
#   aligne le haut du bloc d'onglets avec le haut de "Connexion aux fournisseurs" au lieu de le
#   laisser decale plus bas, et donne d'un coup toute la hauteur de la colonne de gauche (pas
#   seulement ce qui reste a partir de "Source") a la galerie.
$onglets = New-Object System.Windows.Forms.TabControl
$onglets.Location = New-Object System.Drawing.Point(1000, $yBlocConnexion)
$onglets.Size = New-Object System.Drawing.Size(955, 860)
# Ancre sur les 4 cotes : c'est elle qui donne tout son interet au redimensionnement de la
# fenetre (voir $form.FormBorderStyle plus haut) - galeries et journal (Dock="Fill" a l'interieur
# de ses onglets) grandissent avec elle, alors que les champs/boutons au-dessus restent fixes.
$onglets.Anchor = "Top, Bottom, Left, Right"
$form.Controls.Add($onglets)

$ongletDepart = New-Object System.Windows.Forms.TabPage
$ongletDepart.Text = "Fichiers 3D"
$ongletResultats = New-Object System.Windows.Forms.TabPage
$ongletResultats.Text = "Resultats colorises"
$ongletJournal = New-Object System.Windows.Forms.TabPage
$ongletJournal.Text = "Avancement"
$onglets.TabPages.AddRange(@($ongletDepart, $ongletResultats, $ongletJournal))

$barreOutilsDepart = New-Object System.Windows.Forms.Panel
$barreOutilsDepart.Dock = "Top"
$barreOutilsDepart.Height = 34

$btnToutCocher = New-Object System.Windows.Forms.Button
$btnToutCocher.Text = "Tout cocher"
$btnToutCocher.Location = New-Object System.Drawing.Point(4, 4)
$btnToutCocher.Size = New-Object System.Drawing.Size(110, 26)
$barreOutilsDepart.Controls.Add($btnToutCocher)

$btnToutDecocher = New-Object System.Windows.Forms.Button
$btnToutDecocher.Text = "Tout decocher"
$btnToutDecocher.Location = New-Object System.Drawing.Point(120, 4)
$btnToutDecocher.Size = New-Object System.Drawing.Size(110, 26)
$barreOutilsDepart.Controls.Add($btnToutDecocher)

$ongletDepart.Controls.Add($barreOutilsDepart)

$galerieDepart = New-Object System.Windows.Forms.FlowLayoutPanel
$galerieDepart.Dock = "Fill"
$galerieDepart.AutoScroll = $true
$ongletDepart.Controls.Add($galerieDepart)

$btnToutCocher.Add_Click({
    foreach ($case in $script:casesACocher.Values) { $case.Checked = $true }
    Mettre-A-Jour-Estimation
})
$btnToutDecocher.Add_Click({
    foreach ($case in $script:casesACocher.Values) { $case.Checked = $false }
    Mettre-A-Jour-Estimation
})

# Deux colonnes cote a cote (Meshy / Tripo) plutot qu'une seule galerie : en mode comparaison
# chaque fournisseur remplit la sienne, ce qui permet de voir et choisir entre les deux resultats
# d'un meme fichier sans avoir a chercher lequel est lequel. Hors mode comparaison, seule la
# colonne du fournisseur choisi se remplit - l'autre reste simplement vide.
$tableResultats = New-Object System.Windows.Forms.TableLayoutPanel
$tableResultats.Dock = "Fill"
$tableResultats.ColumnCount = 2
$tableResultats.RowCount = 1
[void]$tableResultats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$tableResultats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$ongletResultats.Controls.Add($tableResultats)

function Creer-ColonneResultats($titre) {
    $panneauColonne = New-Object System.Windows.Forms.Panel
    $panneauColonne.Dock = "Fill"

    $entete = New-Object System.Windows.Forms.Label
    $entete.Text = $titre
    $entete.Dock = "Top"
    $entete.Height = 26
    $entete.TextAlign = "MiddleCenter"
    $entete.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $entete.BackColor = [System.Drawing.SystemColors]::ControlLight
    $panneauColonne.Controls.Add($entete)

    $galerie = New-Object System.Windows.Forms.FlowLayoutPanel
    $galerie.Dock = "Fill"
    $galerie.AutoScroll = $true
    $panneauColonne.Controls.Add($galerie)

    return @{ Panneau = $panneauColonne; Galerie = $galerie }
}

$colonneMeshy = Creer-ColonneResultats "Meshy"
$colonneTripo = Creer-ColonneResultats "Tripo"
# Ajoutes dans cet ordre (Tripo d'abord) car en TableLayoutPanel le dernier Dock="Top" ajoute se
# place au-dessus - sans importance ici (chaque colonne est independante), ordre garde simple.
$tableResultats.Controls.Add($colonneMeshy.Panneau, 0, 0)
$tableResultats.Controls.Add($colonneTripo.Panneau, 1, 0)
$galerieResultatsMeshy = $colonneMeshy.Galerie
$galerieResultatsTripo = $colonneTripo.Galerie

$txtJournal = New-Object System.Windows.Forms.TextBox
$txtJournal.Dock = "Fill"
$txtJournal.Multiline = $true
$txtJournal.ScrollBars = "Vertical"
$txtJournal.ReadOnly = $true
$txtJournal.Font = New-Object System.Drawing.Font("Consolas", 9)
# Trouve le 10/10/2026 (signale par Tomyn : le journal "est coupe" des qu'il depasse une certaine
# longueur, et ca ne defile meme plus pour le rattraper) : un TextBox Windows a, par defaut, une
# limite de 32767 caracteres (MaxLength) - meme en multiligne. Une fois cette limite atteinte,
# AppendText() n'ajoute plus rien du tout, silencieusement, sans la moindre erreur. Avec le journal
# qui log chaque poll de progression ("Retexture : IN_PROGRESS (..)...") et encore plus en mode
# Comparer Meshy+Tripo (deux fois plus de lignes), cette limite se fait atteindre facilement sur un
# lot un peu long. 0 = pas de limite pratique pour un TextBox multiligne.
$txtJournal.MaxLength = 0
$ongletJournal.Controls.Add($txtJournal)

function Ecrire-Journal($texte) {
    $txtJournal.AppendText("$texte`r`n")
    $txtJournal.SelectionStart = $txtJournal.Text.Length
    $txtJournal.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# --- Ajoute une vignette (miniature + nom + double-clic pour agrandir) a une galerie ---
# 13/10/2026, Tomyn : pas de depot automatise possible vers MakerWorld (pas d'API publique,
# confirme sur leur propre forum - acces reserve aux entreprises sur demande, de plus en plus
# ferme avec le temps ; tentative de scraping deja essayee par Tomyn, bloquee par Cloudflare).
# Seule la partie redaction est automatisable : un titre + une description prets a coller a la
# main dans le formulaire de depot MakerWorld (champs confirmes dans leur doc officielle : nom,
# categorie, licence, visibilite, description).
function Generer-DescriptionMakerWorld([string]$NomBase, [string]$PromptTexte) {
    # Nettoie le nom de fichier pour en faire un titre lisible : underscores/tirets -> espaces, et
    # suppression d'un eventuel suffixe d'horodatage ("_20261013_231500", ajoute par l'option
    # "Garder un historique des essais") qui n'a rien a faire dans un titre de depot.
    $titreBrut = $NomBase -replace '_\d{8}_\d{6}$', ''
    $titreBrut = ($titreBrut -replace '[_\-]+', ' ').Trim()
    $titre = if ($titreBrut) { (Get-Culture).TextInfo.ToTitleCase($titreBrut.ToLower()) } else { $NomBase }

    $descriptionPrompt = $PromptTexte.Trim()
    if ($descriptionPrompt -and $descriptionPrompt -notmatch '[.!?]\s*$') { $descriptionPrompt += "." }

    $texte = @"
$titre

Figurine imprimee en 3D et colorisee automatiquement, prete a trancher en multi-couleurs (AMS).
Rendu voulu : $descriptionPrompt

(Titre et description generes automatiquement par Coloriser-STL a partir du style choisi - a
relire et completer avant de deposer le modele.)
"@
    return @{ Titre = $titre; Texte = $texte }
}

# Passerelle vers Melange-Couleurs (16/10/2026, idee d'amelioration approuvee par Tomyn : "lier
# les deux apps") - evite de devoir rouvrir Melange-Couleurs a la main et re-selectionner le .3mf
# qu'on vient juste de coloriser ici. Resout puis retient l'emplacement de
# Lancer-Melange-Couleurs.vbs chez Tomyn (voir $CheminConfigMelangeCouleurs plus haut) : essaie
# d'abord quelques emplacements freres plausibles (les deux outils sont souvent installes cote a
# cote), sinon demande une seule fois via un selecteur de fichier et retient le choix pour la
# prochaine fois.
function Obtenir-CheminMelangeCouleurs {
    # 16/10/2026, reordonne suite au retour de Tomyn ("faut que l'application s'adapte... faut pas
    # qu'il aille chercher un nom de fichier en particulier") : la recherche EN DIRECT (ce dossier,
    # puis les dossiers freres connus) passe maintenant AVANT le chemin memorise sur le disque, pas
    # apres. Avant ce changement, un chemin memorise perime (Tomyn a renomme/deplace/reorganise ses
    # dossiers depuis) etait utilise tel quel sans meme revérifier si une recherche fraiche aurait
    # trouve mieux - exactement ce qui causait tout le probleme precedent (chargeait un ancien
    # dossier au lieu du bon, meme pointe droit sous son nez dans le MEME dossier que ce script).
    # Resultat : tant que les deux outils restent dans le meme dossier (ou des dossiers freres a l'un
    # des noms connus), AUCUNE memorisation n'est meme necessaire - tout se redecouvre a chaque
    # lancement, meme apres un renommage ou un deplacement. Le chemin memorise ne sert plus que de
    # tout dernier recours (machine avec une disposition vraiment inhabituelle), et seulement s'il
    # pointe encore vers un fichier qui existe reellement.

    # Verifie d'abord le MEME dossier que ce script (cas de Tomyn : tout a plat, Coloriser-STL et
    # Melange-Couleurs ensemble dans un seul dossier).
    $candidatMemeDossier = Join-Path $PSScriptRoot "Lancer-Melange-Couleurs.vbs"
    if (Test-Path $candidatMemeDossier) { return $candidatMemeDossier }

    # Sinon, emplacements freres plausibles - couvre le cas ou les deux outils sont installes cote a
    # cote dans des dossiers SEPARES (sous l'un ou l'autre nom de dossier/depot connu) sans jamais
    # supposer que c'est garanti.
    $dossierParent = Split-Path $PSScriptRoot -Parent
    $candidatsPossibles = @(
        "MelangeCouleurs3MF", "melangecouleurs3mf", "Melange-Couleurs-3MF", "Melange-Couleurs",
        "melange_couleurs_3mf", "Melange-Couleurs-GUI"
    )
    foreach ($nomDossier in $candidatsPossibles) {
        $candidat = Join-Path (Join-Path $dossierParent $nomDossier) "Lancer-Melange-Couleurs.vbs"
        if (Test-Path $candidat) { return $candidat }
    }

    # Dernier recours : chemin memorise d'une fois precedente (disposition inhabituelle ou
    # confirmee manuellement par Tomyn via le selecteur plus bas) - seulement s'il existe encore.
    if (Test-Path $CheminConfigMelangeCouleurs) {
        try {
            $objet = Get-Content -Path $CheminConfigMelangeCouleurs -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($objet.Chemin -and (Test-Path $objet.Chemin)) { return [string]$objet.Chemin }
        } catch { }
    }

    $dialogue = New-Object System.Windows.Forms.OpenFileDialog
    $dialogue.Title = "Localiser Melange-Couleurs (fichier Lancer-Melange-Couleurs.vbs)"
    $dialogue.Filter = "Lanceur Melange-Couleurs (Lancer-Melange-Couleurs.vbs)|Lancer-Melange-Couleurs.vbs|Tous les fichiers (*.*)|*.*"
    # 16/10/2026, correctif - Tomyn : chez lui, Melange-Couleurs est a PLAT dans le MEME dossier que
    # Coloriser-STL, pas dans un dossier frere separe - donc aucun des $candidatsPossibles ci-dessus
    # ne matchait, et cette boite de dialogue s'ouvrait dans un dossier Windows par defaut
    # quelconque, PAS dans $PSScriptRoot ou le fichier se trouvait reellement. Resultat : "introuvable"
    # alors que le fichier etait juste dans un autre dossier que celui affiche. Demarre maintenant
    # directement dans le dossier de CE script (Coloriser-STL-GUI.ps1) - le cas le plus probable
    # (meme dossier) est maintenant couvert sans que Tomyn ait besoin de naviguer manuellement.
    $dialogue.InitialDirectory = $PSScriptRoot
    if ($dialogue.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    Sauvegarder-CheminMelangeCouleurs $dialogue.FileName
    return $dialogue.FileName
}

function Sauvegarder-CheminMelangeCouleurs([string]$chemin) {
    try {
        (@{ Chemin = $chemin } | ConvertTo-Json) | Set-Content -Path $CheminConfigMelangeCouleurs -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Lancer-MelangeCouleurs([string]$cheminFichier3mf) {
    $cheminVbs = Obtenir-CheminMelangeCouleurs
    if (-not $cheminVbs) { return }
    try {
        # Lancer-Melange-Couleurs.vbs accepte depuis le 16/10/2026 un argument optionnel : le
        # chemin du .3mf a charger automatiquement au demarrage, a la place du dernier fichier
        # utilise (voir le .vbs et Melange-Couleurs-GUI.ps1, parametre -FichierInitial).
        # 16/10/2026, correctif (Tomyn : "il prend toujours pas le bon, il prend celui [non] genere
        # par colorisation") : "Start-Process -FilePath $cheminVbs -ArgumentList ..." passe par
        # l'association de fichier .vbs de Windows (ShellExecute) pour deviner comment lancer le
        # .vbs - et selon la configuration de la machine, cette association ne transmet pas
        # forcement les arguments en plus du fichier lui-meme (le "%*" de la commande d'ouverture
        # associee aux .vbs n'est pas garanti partout), d'ou Melange-Couleurs qui s'ouvrait bien
        # mais retombait sur le dernier fichier utilise au lieu du resultat tout juste colorise.
        # Appelle maintenant wscript.exe DIRECTEMENT avec le .vbs et le chemin du .3mf comme deux
        # arguments explicites et separes - plus besoin de compter sur cette association.
        Start-Process -FilePath "wscript.exe" -ArgumentList "`"$cheminVbs`"", "`"$cheminFichier3mf`""
    } catch {
        Afficher-Boite "Impossible de lancer Melange-Couleurs : $_" "Erreur" "OK" "Error" | Out-Null
    }
}

function Ajouter-Vignette($galerie, $cheminFichier, $imageDejaFournie = $null, $avecCaseACocher = $false, [string]$texteDescription = "") {
    # 13/10/2026 : carte plus haute seulement quand une description MakerWorld est fournie (voir
    # Generer-DescriptionMakerWorld plus haut), pour garder la galerie de depart (pas de
    # description) a sa taille habituelle.
    $hauteurBoutonDescription = if ($texteDescription) { 26 } else { 0 }
    # 16/10/2026 : bouton "Analyser les couleurs" (passerelle vers Melange-Couleurs) uniquement
    # sur les resultats .3mf - la galerie de depart (avecCaseACocher=true, toujours des .stl) et
    # les resultats .obj (variante "exporter en .obj" ou Tripo) n'ont pas de sens avec cet outil,
    # qui ne lit que des .3mf.
    # Correction du 16/10/2026 (Tomyn : "coupe" et "presque invisible") : la premiere version
    # ajoutait systematiquement une ligne de 26px aux cartes de resultat .3mf, ce qui recreait
    # exactement le probleme de galerie coupee regle la veille en reduisant $TailleMiniature. Une
    # description MakerWorld est TOUJOURS generee pour un resultat .3mf (voir les 3 appels a
    # Generer-DescriptionMakerWorld plus haut), donc $texteDescription est pour ainsi dire toujours
    # rempli ici : le bouton partage maintenant la ligne du bouton "Copier description" (cote a
    # cote) au lieu d'ajouter sa propre ligne - zero hauteur en plus dans le cas normal. La ligne
    # dediee ne sert plus que de filet de securite pour le cas (imprevu en pratique) ou
    # $texteDescription serait vide malgre tout.
    $estResultat3mf = (-not $avecCaseACocher) -and ([System.IO.Path]::GetExtension($cheminFichier).ToLower() -eq ".3mf")
    $hauteurBoutonAnalyse = if ($estResultat3mf -and -not $texteDescription) { 26 } else { 0 }
    $panneau = New-Object System.Windows.Forms.Panel
    $panneau.Size = New-Object System.Drawing.Size(($TailleMiniature + 16), ($TailleMiniature + 84 + $hauteurBoutonDescription + $hauteurBoutonAnalyse))
    # Carte "carte blanche" plutot que le cadre gris FixedSingle d'origine (10/10/2026) : fond
    # blanc + une bande violette de 3px en haut, dessinee a la main (Panel ne propose pas de
    # bordure coloree nativement sans passer par un Paint custom).
    $panneau.BorderStyle = "None"
    $panneau.BackColor = $THEME.Surface
    $panneau.Margin = New-Object System.Windows.Forms.Padding(6)

    # Coins arrondis (10/10/2026, Tomyn a demande d'aller plus loin que le niveau 1) : Panel n'a
    # pas d'option "coin arrondi" native - on definit sa Region sur un rectangle arrondi via GDI+.
    # Tout ce qui est peint (bande violette, bordure, miniature) se retrouve automatiquement
    # decoupe a cette forme, sans rien changer au Paint ci-dessous.
    # 16/10/2026 : factorise dans Definir-RegionArrondie (voir le commentaire du THEME plus haut),
    # appelee avec $panneau directement plutot que de recalculer largeur/hauteur a la main - $panneau.Size
    # vient juste d'etre fixe ci-dessus avec exactement la meme formule, donc $panneau.Width/.Height
    # valent deja ce que $largeurCarte/$hauteurCarte valaient ici. Meme rayon de 10 qu'avant.
    Definir-RegionArrondie $panneau 10

    $panneau.Add_Paint({
        param($expediteur, $evenement)
        $bandeau = New-Object System.Drawing.SolidBrush($THEME.AccentPrincipal)
        $evenement.Graphics.FillRectangle($bandeau, 0, 0, $expediteur.Width, 3)
        $stylo = New-Object System.Drawing.Pen($THEME.Bordure)
        $evenement.Graphics.DrawRectangle($stylo, 0, 3, $expediteur.Width - 1, $expediteur.Height - 4)
    })

    if ($avecCaseACocher) {
        # Permet d'exclure un fichier precis avant de lancer (ex: une variante "_Supported.stl"
        # ramassee par la recherche recursive mais qu'on ne veut pas traiter) sans devoir changer
        # de dossier ou refaire toute la selection.
        $caseACocher = Creer-CaseACocher "Inclure" ($TailleMiniature + 2) 20
        $caseACocher.Checked = $true
        $caseACocher.Location = New-Object System.Drawing.Point(8, 6)
        $panneau.Controls.Add($caseACocher)
        $script:casesACocher[$cheminFichier] = $caseACocher
        $caseACocher.Add_CheckedChanged({ Mettre-A-Jour-Estimation }.GetNewClosure())
    }

    # Pour les STL de depart : rendu maison. Pour les resultats : image deja fournie par Meshy
    # (apercu de la texturation), passee directement en parametre - plus fidele et plus rapide
    # que de tenter de rendre nous-memes un fichier .3mf (format bien plus complexe qu'un STL).
    if ($imageDejaFournie -ne $null) {
        $image = $imageDejaFournie
    } else {
        $image = Obtenir-Miniature $cheminFichier $TailleMiniature
    }
    if ($image -eq $null) { $image = $ImageRemplacement }

    $boiteImage = New-Object System.Windows.Forms.PictureBox
    $boiteImage.Image = $image
    $boiteImage.SizeMode = "Zoom"
    $boiteImage.Size = New-Object System.Drawing.Size($TailleMiniature, $TailleMiniature)
    $boiteImage.Location = New-Object System.Drawing.Point(8, 30)
    $boiteImage.Cursor = "Hand"
    $panneau.Controls.Add($boiteImage)

    $nomAffiche = Split-Path $cheminFichier -Leaf
    $etiquette = New-Object System.Windows.Forms.Label
    $etiquette.Text = $nomAffiche
    $etiquette.Size = New-Object System.Drawing.Size(($TailleMiniature + 6), 36)
    $etiquette.Location = New-Object System.Drawing.Point(5, ($TailleMiniature + 32))
    $etiquette.TextAlign = "TopCenter"
    $etiquette.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $panneau.Controls.Add($etiquette)

    # Double-clic sur la miniature ou le nom : ouvre le fichier avec l'application associee sur
    # cette machine (ton slicer habituel, le plus souvent), pour un vrai rendu interactif.
    # .GetNewClosure() est indispensable ici : sans lui, le bloc de script perd l'acces a
    # $cheminFichier des que cette fonction se termine (bien avant que l'utilisateur ne clique
    # vraiment), et Start-Process recoit alors un chemin vide - exactement l'erreur remontee
    # ("FilePath... Null ou vide") sur un clic de miniature de resultat.
    $gestionnaireDoubleClic = {
        try { Start-Process -FilePath $cheminFichier } catch {
            Afficher-Boite "Impossible d'ouvrir le fichier : $_" "Erreur" "OK" "Error" | Out-Null
        }
    }.GetNewClosure()
    $boiteImage.Add_DoubleClick($gestionnaireDoubleClic)
    $etiquette.Add_DoubleClick($gestionnaireDoubleClic)

    # 13/10/2026 : bouton "Copier description" (voir Generer-DescriptionMakerWorld plus haut) -
    # copie titre + description dans le presse-papier, a coller a la main dans le formulaire de
    # depot MakerWorld (pas d'automatisation possible cote depot, voir le commentaire sur cette
    # fonction).
    # 16/10/2026 : partage desormais sa ligne avec "Analyser les couleurs..." (cote a cote) sur un
    # resultat .3mf, plutot que d'empiler une ligne de plus sous lui - voir le commentaire sur
    # $hauteurBoutonAnalyse plus haut pour pourquoi (carte qui repoussait la galerie hors de vue).
    if ($texteDescription) {
        $yLigneBoutons = $TailleMiniature + 32 + 36
        if ($estResultat3mf) {
            $largeurDemiBouton = [math]::Floor((($TailleMiniature + 6) - 4) / 2)

            $btnCopierDescription = New-Object System.Windows.Forms.Button
            $btnCopierDescription.Text = "Copier desc."
            $btnCopierDescription.AutoEllipsis = $true
            $btnCopierDescription.Size = New-Object System.Drawing.Size($largeurDemiBouton, 22)
            $btnCopierDescription.Location = New-Object System.Drawing.Point(5, $yLigneBoutons)
            $btnCopierDescription.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
            $panneau.Controls.Add($btnCopierDescription)
            Rendre-BoutonPlat $btnCopierDescription "discret"
            $infobulleCopier = New-Object System.Windows.Forms.ToolTip
            $infobulleCopier.SetToolTip($btnCopierDescription, "Copier le titre et la description generes (a coller dans le formulaire de depot MakerWorld)")
            $btnCopierDescription.Add_Click({
                try {
                    [System.Windows.Forms.Clipboard]::SetText($texteDescription)
                    $btnCopierDescription.Text = "Copie !"
                } catch {
                    Afficher-Boite "Impossible de copier dans le presse-papier : $_" "Erreur" "OK" "Error" | Out-Null
                }
            }.GetNewClosure())

            $btnAnalyserCouleurs = New-Object System.Windows.Forms.Button
            $btnAnalyserCouleurs.Text = "Couleurs..."
            $btnAnalyserCouleurs.AutoEllipsis = $true
            $btnAnalyserCouleurs.Size = New-Object System.Drawing.Size($largeurDemiBouton, 22)
            $btnAnalyserCouleurs.Location = New-Object System.Drawing.Point((5 + $largeurDemiBouton + 4), $yLigneBoutons)
            $btnAnalyserCouleurs.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
            $panneau.Controls.Add($btnAnalyserCouleurs)
            Rendre-BoutonPlat $btnAnalyserCouleurs "discret"
            $infobulleAnalyser = New-Object System.Windows.Forms.ToolTip
            $infobulleAnalyser.SetToolTip($btnAnalyserCouleurs, "Analyser les couleurs de ce resultat dans Melange-Couleurs")
            $btnAnalyserCouleurs.Add_Click({ Lancer-MelangeCouleurs $cheminFichier }.GetNewClosure())
        } else {
            $btnCopierDescription = New-Object System.Windows.Forms.Button
            $btnCopierDescription.Text = "Copier description"
            $btnCopierDescription.Size = New-Object System.Drawing.Size(($TailleMiniature + 6), 22)
            $btnCopierDescription.Location = New-Object System.Drawing.Point(5, $yLigneBoutons)
            $btnCopierDescription.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
            $panneau.Controls.Add($btnCopierDescription)
            Rendre-BoutonPlat $btnCopierDescription "discret"
            $btnCopierDescription.Add_Click({
                try {
                    [System.Windows.Forms.Clipboard]::SetText($texteDescription)
                    $btnCopierDescription.Text = "Copie dans le presse-papier !"
                } catch {
                    Afficher-Boite "Impossible de copier dans le presse-papier : $_" "Erreur" "OK" "Error" | Out-Null
                }
            }.GetNewClosure())
        }
    } elseif ($estResultat3mf) {
        # Filet de securite (voir le commentaire sur $hauteurBoutonAnalyse plus haut) : ce cas
        # n'arrive pas en pratique aujourd'hui (une description est toujours generee pour un
        # resultat .3mf), mais si ca changeait un jour, le bouton garde sa propre ligne plutot que
        # de disparaitre silencieusement.
        $btnAnalyserCouleurs = New-Object System.Windows.Forms.Button
        $btnAnalyserCouleurs.Text = "Analyser les couleurs..."
        $btnAnalyserCouleurs.Size = New-Object System.Drawing.Size(($TailleMiniature + 6), 22)
        $btnAnalyserCouleurs.Location = New-Object System.Drawing.Point(5, ($TailleMiniature + 32 + 36))
        $btnAnalyserCouleurs.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
        $panneau.Controls.Add($btnAnalyserCouleurs)
        Rendre-BoutonPlat $btnAnalyserCouleurs "discret"
        $btnAnalyserCouleurs.Add_Click({ Lancer-MelangeCouleurs $cheminFichier }.GetNewClosure())
    }

    $galerie.Controls.Add($panneau)
}

# Liste de travail partagee : alimentee soit par un dossier (recursif), soit par une selection
# directe de fichiers - la galerie et le traitement reel (bouton Lancer) lisent tous les deux
# cette meme liste, pour etre toujours sûrs de traiter exactement ce qui est affiche.
$script:fichiersAtraiter = @()
# Chemin complet -> controle CheckBox correspondant, pour savoir lesquels sont inclus au moment
# de lancer le traitement (voir Ajouter-Vignette, appele avec avecCaseACocher=$true pour cette
# galerie uniquement).
$script:casesACocher = @{}

function Mettre-A-Jour-Estimation {
    $inclus = @($script:fichiersAtraiter | Where-Object {
        $case = $script:casesACocher[$_.FullName]
        $case -eq $null -or $case.Checked
    })
    # Image -> STL (08/10/2026) : surcout Image to 3D (maillage seul) a ajouter UNIQUEMENT pour
    # les fichiers images du lot - compte a part, pour afficher clairement d'ou vient le surcout
    # plutot que de le fondre dans le total sans explication.
    $nbImages = @($inclus | Where-Object { $_.Extension.ToLower() -in $EXTENSIONS_IMAGES }).Count
    # 20/10/2026 : +5 credits par image si 2K/4K choisi (geometry_resolution, voir
    # $menuGeometrieResolution) - meme principe que le surcout Image to 3D juste au-dessus, a part
    # pour que l'origine du cout reste claire dans le texte affiche.
    $surcoutResolution = if ($nbImages -gt 0 -and $menuGeometrieResolution.SelectedIndex -gt 0) { $nbImages * 5 } else { 0 }
    $texteSurcoutImages = if ($nbImages -gt 0) {
        " + ~$($nbImages * $CREDITS_ESTIMES_IMAGE_VERS_3D) credits Meshy pour generer le maillage des $nbImages image(s) avant colorisation" +
        $(if ($surcoutResolution -gt 0) { " (+ ~$surcoutResolution credits pour la resolution $($menuGeometrieResolution.Text))" } else { "" })
    } else { "" }
    # 20/10/2026 : reparation des parois (voir $caseReparationParois) - pas de compte precis
    # possible ici (l'Analyze gratuit decide au cas par cas si la Reparation payante s'applique,
    # voir Reparer-ParoisSiNecessaire), donc note generique plutot qu'un chiffre total qui serait faux.
    $texteSurcoutReparation = if ($caseReparationParois.Checked) {
        " + 0 a ~10 credits par fichier Meshy selon le resultat de l'analyse gratuite des parois (reparation payante seulement si reellement necessaire)"
    } else { "" }

    if ($inclus.Count -eq 0) {
        $txtEstimationCout.Text = ""
    } elseif ($caseComparerFournisseurs.Checked) {
        # Chiffre Tripo desormais confirme (voir $CREDITS_ESTIMES_PAR_FICHIER_TRIPO) - echelle de
        # credits separee de celle de Meshy, donc on les additionne mais sans pretendre que c'est
        # la meme "unite" de credit d'un fournisseur a l'autre.
        $totalTripo = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER_TRIPO
        if ($caseMeshyObjExperimental.Checked) {
            $totalMeshyObj = $inclus.Count * $CREDITS_ESTIMES_RETEXTURE_SEULE
            $txtEstimationCout.Text = "Cout estime : ~$totalMeshyObj credits Meshy (Retexture seule, sans Multi-Color Print) + ~$totalTripo credits Tripo ($($inclus.Count) fichier(s) chacun, deux echelles de credits differentes)$texteSurcoutImages$texteSurcoutReparation"
        } else {
            $totalMeshy = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER
            $txtEstimationCout.Text = "Cout estime : ~$totalMeshy credits Meshy + ~$totalTripo credits Tripo ($($inclus.Count) fichier(s) chacun, deux echelles de credits differentes)$texteSurcoutImages$texteSurcoutReparation"
        }
    } elseif ($menuFournisseur.SelectedItem -eq "Meshy" -and $caseMeshyObjExperimental.Checked) {
        # Une seule etape facturee (Retexture) au lieu de deux (Retexture + Multi-Color Print) -
        # economise le cout du Multi-Color Print (confirme a 10 credits le 07/10/2026).
        $totalMeshyObj = $inclus.Count * $CREDITS_ESTIMES_RETEXTURE_SEULE
        $txtEstimationCout.Text = "Cout estime : ~$totalMeshyObj credits ($($inclus.Count) fichier(s) x $CREDITS_ESTIMES_RETEXTURE_SEULE, Retexture seule - sans Multi-Color Print)$texteSurcoutImages$texteSurcoutReparation"
    } elseif ($menuFournisseur.SelectedItem -eq "Tripo") {
        # 20/10/2026 : les images sont desormais prises en charge cote Tripo (Image to 3D, voir
        # Lancer-ImageModelTripo) - l'ancien avertissement "echoueront" n'est plus vrai, retire.
        # Le surcout Image to 3D (deja compte dans $texteSurcoutImages juste au-dessus) reste
        # etiquete "Meshy" dans son propre texte, pas totalement exact ici, mais le detail precis
        # du cout Tripo pour une image n'est pas encore confirme (voir $CREDITS_ESTIMES_PAR_FICHIER_TRIPO) -
        # l'estimation de base reste donc la meme, juste sans le faux avertissement.
        $totalTripo = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER_TRIPO
        $txtEstimationCout.Text = "Cout estime : ~$totalTripo credits Tripo ($($inclus.Count) fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER_TRIPO)"
    } else {
        $total = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER
        $txtEstimationCout.Text = "Cout estime : ~$total credits ($($inclus.Count) fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER, estimation empirique)$texteSurcoutImages$texteSurcoutReparation"
    }
}

function Afficher-GalerieDepart {
    $galerieDepart.Controls.Clear()
    $script:casesACocher.Clear()

    $fichiersStl = $script:fichiersAtraiter
    if ($fichiersStl.Count -eq 0) {
        Afficher-Boite "Aucun fichier 3D selectionne." "Rien a afficher" | Out-Null
        return
    }

    $etiquetteCompteur = New-Object System.Windows.Forms.Label
    $etiquetteCompteur.AutoSize = $true
    $galerieDepart.Controls.Add($etiquetteCompteur)

    $reussites = 0
    $echecs = @()
    foreach ($f in $fichiersStl) {
        try {
            # Chaque fichier est isole dans son propre try/catch : un fichier problematique ne
            # doit jamais empecher l'affichage des autres, ni faire planter la galerie entiere
            # en silence (comportement observe lors du premier vrai test : rien ne s'affichait,
            # pas meme une image de remplacement, sans aucune indication de ce qui avait echoue).
            Ajouter-Vignette $galerieDepart $f.FullName $null $true
            $reussites++
        } catch {
            $echecs += "$($f.Name) : $_"
        }
        [System.Windows.Forms.Application]::DoEvents()
    }

    $etiquetteCompteur.Text = "$reussites / $($fichiersStl.Count) vignette(s) affichee(s)" + $(if ($echecs.Count -gt 0) { " - $($echecs.Count) erreur(s), voir ci-dessous" } else { "" })

    if ($echecs.Count -gt 0) {
        $txtJournal.Clear()
        Ecrire-Journal "=== Erreurs lors de la generation des vignettes ==="
        foreach ($e in $echecs) { Ecrire-Journal "  $e" }
        $onglets.SelectedTab = $ongletJournal
        Afficher-Boite "$($echecs.Count) fichier(s) n'ont pas pu etre affiches. Detail dans l'onglet Avancement." "Erreurs de generation" "OK" "Error" | Out-Null
    }

    Mettre-A-Jour-Estimation
}

function Charger-DepuisDossier($dossier) {
    if (-not (Test-Path $dossier -PathType Container)) {
        Afficher-Boite "Dossier introuvable : $dossier" "Erreur" "OK" "Error" | Out-Null
        return
    }
    $script:fichiersAtraiter = @(Get-ChildItem -Path $dossier -Recurse -File | Where-Object { $_.Extension.ToLower() -in $EXTENSIONS_SUPPORTEES })
    $txtDossier.Text = $dossier
    if (-not $txtDossierSortie.Text) { $txtDossierSortie.Text = Join-Path $dossier "colorise" }
    $onglets.SelectedTab = $ongletDepart
    Afficher-GalerieDepart
}

$btnParcourir.Add_Click({
    $dialogue = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialogue.ShowDialog() -eq "OK") { Charger-DepuisDossier $dialogue.SelectedPath }
})

$btnChoisirFichiers.Add_Click({
    $dialogue = New-Object System.Windows.Forms.OpenFileDialog
    $dialogue.Filter = "Fichiers 3D et images (*.stl;*.obj;*.fbx;*.glb;*.gltf;*.3mf;*.jpg;*.jpeg;*.png;*.webp)|*.stl;*.obj;*.fbx;*.glb;*.gltf;*.3mf;*.jpg;*.jpeg;*.png;*.webp"
    $dialogue.Multiselect = $true
    $dialogue.Title = "Choisir un ou plusieurs fichiers 3D ou images"
    if ($dialogue.ShowDialog() -eq "OK") {
        $script:fichiersAtraiter = @($dialogue.FileNames | ForEach-Object { Get-Item $_ })
        $dossierParent = Split-Path $dialogue.FileNames[0] -Parent
        $txtDossier.Text = $dossierParent
        if (-not $txtDossierSortie.Text) { $txtDossierSortie.Text = Join-Path $dossierParent "colorise" }
        $onglets.SelectedTab = $ongletDepart
        Afficher-GalerieDepart
    }
})

# --- Glisser-deposer : dossier(s) et/ou fichier(s) .stl directement sur la fenetre, ET texte
# (cle API) depose directement sur un des deux champs de cle - ajoute le 10/10/2026. Les champs
# $txtCleApi/$txtCleApiTripo ne peuvent pas recevoir de glisser-depose eux-memes : Windows
# desactive le drag&drop natif (source ET cible) sur un champ en mode mot de passe
# (UseSystemPasswordChar), par securite, meme si on force AllowDrop=$true sur le TextBox. On
# contourne donc en captant le depot au niveau de la fenetre (jamais soumise a cette restriction)
# et en ecrivant nous-memes .Text selon la position du curseur au moment du lacher. ---
$form.Add_DragEnter({
    param($sender, $e)
    if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop) -or $e.Data.GetDataPresent([Windows.Forms.DataFormats]::Text)) {
        $e.Effect = "Copy"
    } else {
        $e.Effect = "None"
    }
})
$form.Add_DragDrop({
    param($sender, $e)

    if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::Text)) {
        $positionDepot = $form.PointToClient((New-Object System.Drawing.Point($e.X, $e.Y)))
        $texteDepose = ($e.Data.GetData([Windows.Forms.DataFormats]::Text)).ToString().Trim()
        if ($texteDepose) {
            if ($txtCleApi.Bounds.Contains($positionDepot)) { $txtCleApi.Text = $texteDepose; return }
            if ($txtCleApiTripo.Bounds.Contains($positionDepot)) { $txtCleApiTripo.Text = $texteDepose; return }
        }
    }

    $cheminsDeposes = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    if (-not $cheminsDeposes -or $cheminsDeposes.Count -eq 0) { return }

    $fichiersTrouves = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($chemin in $cheminsDeposes) {
        if (Test-Path $chemin -PathType Container) {
            Get-ChildItem -Path $chemin -Recurse -File | Where-Object { $_.Extension.ToLower() -in $EXTENSIONS_SUPPORTEES } | ForEach-Object { $fichiersTrouves.Add($_) }
        } elseif ($EXTENSIONS_SUPPORTEES -contains [System.IO.Path]::GetExtension($chemin).ToLower()) {
            $fichiersTrouves.Add((Get-Item $chemin))
        }
    }

    if ($fichiersTrouves.Count -eq 0) {
        Afficher-Boite "Aucun fichier 3D supporte trouve dans ce qui a ete depose." "Rien a charger" | Out-Null
        return
    }

    $script:fichiersAtraiter = @($fichiersTrouves)
    $premierDossier = Split-Path $fichiersTrouves[0].FullName -Parent
    $txtDossier.Text = $premierDossier
    if (-not $txtDossierSortie.Text) { $txtDossierSortie.Text = Join-Path $premierDossier "colorise" }
    $onglets.SelectedTab = $ongletDepart
    Afficher-GalerieDepart
})

$btnActualiser.Add_Click({
    # Repart du champ texte comme d'un dossier (si tu as choisi des fichiers individuels, change
    # plutot de selection avec le bouton "Fichier(s)..." - ce bouton-ci est pour le mode dossier).
    Charger-DepuisDossier $txtDossier.Text
})

# ============================== LOGIQUE DE COLORISATION ==============================

$script:ANNULATION_MARQUEUR = "__ANNULATION_DEMANDEE__"
$script:annulationDemandee = $false
$script:debutTraitement = $null
$script:indexFichierCourant = 0
$script:totalFichiersLot = 0
# Credits reellement consommes sur le lot EN COURS (16/10/2026, Tomyn : "ok pour tout" - compteur
# en direct) - deja accumule plus bas dans Lancer-Traitement (promu en variable de script pour
# qu'Afficher-ProgressionEnCours, definie ici, puisse l'afficher pendant le traitement et pas
# seulement a la toute fin dans la ligne d'historique).
$script:creditsReelsLot = 0

# Regex partagee pour reconnaitre une erreur reseau/serveur TRANSITOIRE (16/10/2026, idee en
# passant validee par Tomyn - "tu peux tout faire") : timeout, connexion coupee/refusee, DNS,
# erreur 5xx cote serveur (Meshy/Tripo en surcharge momentanee) - a bien distinguer d'une vraie
# erreur "metier" (cle API invalide, credits insuffisants, prompt manquant, 4xx en general) qui ne
# doit SURTOUT PAS etre reessayee automatiquement (relancer 3 fois une cle invalide ne sert a
# rien et fait juste perdre du temps). Couverture volontairement large (anglais + francais, .NET
# et messages d'erreur HTTP) plutot qu'une liste figee de codes - mieux vaut reessayer une fois de
# trop sur un message ambigu que perdre un fichier entier (et ses credits deja depenses sur une
# etape precedente) pour un simple hoquet reseau, surtout sur un gros lot de 250 fichiers.
$script:REGEX_ERREUR_RESEAU_TRANSITOIRE = '(?i)timed?(-|\s)?out|a expire|delai d''attente|unable to connect|impossible de se connecter|connexion.*(reinitialisee|refusee|fermee|interrompue)|forcibly closed|existing connection was closed|remote name could not be resolved|nom distant n''a pas pu|no such host|temporarily unavailable|service unavailable|gateway time-?out|bad gateway|task was canceled|\(5(0[0-9]|[1-9][0-9])\)|: 5(0[0-9]|[1-9][0-9])\b'

# Reessaie automatiquement un appel reseau (Meshy/Tripo) en cas d'erreur TRANSITOIRE (voir la
# regex ci-dessus) avant d'abandonner le fichier pour de vrai - jusqu'ici, un seul hoquet reseau
# sur n'importe quel appel ponctuel (lancement d'etape, telechargement...) faisait echouer tout de
# suite le fichier entier, obligeant a repasser par "Relancer les echecs" a la main. Attente non
# bloquante (DoEvents) entre deux tentatives, et verification de l'annulation a chaque tour - pas
# question de reessayer bêtement 3 fois si Tomyn a deja clique Annuler pendant l'attente.
function Invoquer-AvecReessaiReseau([scriptblock]$Action, [string]$Libelle, [int]$TentativesMax = 3, [int]$DelaiSecondes = 4) {
    for ($tentative = 1; $tentative -le $TentativesMax; $tentative++) {
        if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
        try {
            return & $Action
        } catch {
            if ("$_" -eq $script:ANNULATION_MARQUEUR) { throw }
            $messageErreur = "$_"
            $estTransitoire = $messageErreur -match $script:REGEX_ERREUR_RESEAU_TRANSITOIRE
            if (-not $estTransitoire -or $tentative -ge $TentativesMax) { throw }
            Ecrire-Journal "    ($Libelle : erreur reseau transitoire, tentative $tentative/$TentativesMax - '$messageErreur' - nouvel essai dans ${DelaiSecondes}s)"
            $finAttente = (Get-Date).AddSeconds($DelaiSecondes)
            while ((Get-Date) -lt $finAttente) {
                if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    }
}

# Estimation du temps restant sur un lot (16/10/2026, Tomyn : "ok pour tout" - meme recette que
# cote Melange-Couleurs, voir le commentaire equivalent la-bas) : moyenne glissante simple (temps
# ecoule / fichiers deja faits) x fichiers restants - pas une vraie prediction, mais largement
# suffisant pour se faire une idee sur un gros lot plutot que de n'avoir que le chrono ecoule.
# Chaine vide tant qu'aucun fichier n'est encore termine (pas d'estimation fiable sur un seul
# point de mesure). $nombreFaits est le compte APRES le dernier fichier termine, pas le fichier en
# cours de traitement.
function Obtenir-TexteEtaLot([double]$secondesEcoulees, [int]$nombreFaits, [int]$nombreTotal) {
    if ($nombreFaits -le 0 -or $nombreFaits -ge $nombreTotal) { return "" }
    $dureeMoyenneParFichier = $secondesEcoulees / $nombreFaits
    $secondesRestantes = $dureeMoyenneParFichier * ($nombreTotal - $nombreFaits)
    $resteTxt = if ($secondesRestantes -ge 3600) {
        "{0}h{1:00}" -f [int]([Math]::Floor($secondesRestantes / 3600)), [int]([Math]::Floor(($secondesRestantes % 3600) / 60))
    } elseif ($secondesRestantes -ge 60) {
        "~{0} min" -f [int][Math]::Ceiling($secondesRestantes / 60)
    } else {
        "moins d'1 min"
    }
    return " - reste $resteTxt"
}

function Afficher-ProgressionEnCours($etapeTexte) {
    if ($script:debutTraitement -eq $null) { return }
    $ecoule = (Get-Date) - $script:debutTraitement
    $ecouleTexte = "{0:00}:{1:00}" -f [int]$ecoule.TotalMinutes, $ecoule.Seconds
    $etaTexte = Obtenir-TexteEtaLot $ecoule.TotalSeconds ($script:indexFichierCourant - 1) $script:totalFichiersLot
    # 16/10/2026, Tomyn : "ok pour tout" - compteur de credits reellement depenses EN DIRECT
    # pendant le lot (jusqu'ici $script:creditsReelsLot n'etait affiche qu'a la toute fin, dans la
    # ligne d'historique) - utile pour reperer un derapage avant la fin plutot qu'apres, surtout
    # sur un gros lot paye par le collegue dessinateur de Tomyn.
    $creditsTexte = " - $([Math]::Round($script:creditsReelsLot, 1)) credit(s) depenses"
    $txtEstimationCout.Text = "Fichier $($script:indexFichierCourant)/$($script:totalFichiersLot) - ecoule : $ecouleTexte$etaTexte$creditsTexte - $etapeTexte"
}

function Attendre-Tache($UrlTache, $Entetes, $Libelle) {
    $debut = Get-Date
    while ($true) {
        if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
        if (((Get-Date) - $debut).TotalSeconds -gt $TimeoutTacheSecondes) {
            throw "$Libelle : pas de reponse apres $($TimeoutTacheSecondes / 60) min"
        }
        $tache = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri $UrlTache -Headers $Entetes -Method Get } $Libelle
        switch ($tache.status) {
            "SUCCEEDED" { return $tache }
            "FAILED"    { throw "$Libelle a echoue : $($tache.task_error.message)" }
            "CANCELED"  { throw "$Libelle a ete annulee" }
            default     {
                Ecrire-Journal "    $Libelle : $($tache.status) ($($tache.progress)%)..."
                # 17/10/2026, Tomyn : "la barre de progression ne fonctionne plus" - la fenetre de
                # progression (overlay) n'etait mise a jour qu'UNE FOIS PAR FICHIER (avant de le
                # commencer, puis a 100% a la fin), jamais pendant - pour un lot d'un seul fichier
                # (le cas le plus courant), elle restait donc bloquee a 0% du debut a la fin, meme
                # si Remesh/Retexture/Multi-Color Print avancaient reellement (visible dans le
                # journal mais pas dans l'overlay). Relaie ici la vraie progression de la tache en
                # cours ($tache.progress, deja utilisee pour le journal juste au-dessus) a chaque
                # poll - $titre omis (laisse le nom du fichier/ETA deja affiches intacts).
                $creditsOverlayTexte = " - $([Math]::Round($script:creditsReelsLot, 1)) credit(s)"
                Mettre-A-Jour-OverlayProgression ([int]$tache.progress) $null $creditsOverlayTexte
            }
        }
        # Attente decoupee en petits intervalles (au lieu d'un seul Start-Sleep de 5s) pour que
        # l'annulation reagisse vite, pas seulement entre deux appels a l'API.
        for ($i = 0; $i -lt $IntervallePollSecondes; $i++) {
            if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
            Afficher-ProgressionEnCours "$Libelle en cours..."
            Start-Sleep -Seconds 1
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

# ============================== CLIENT TRIPO (fournisseur alternatif) ==============================
# Base documentee par le SDK Go officiel de VAST-AI-Research (societe editrice de Tripo). Les
# endpoints et l'authentification sont confirmes avec un bon niveau de certitude ; les noms exacts
# des champs du corps de /models/texture sont une deduction par recoupement de plusieurs sources
# tierces concordantes, pas une doc officielle citee mot pour mot comme pour Meshy - attendre de
# vraies corrections une fois teste avec une vraie cle, plus proche de nos debuts sur les lecteurs
# RFID que du niveau de certitude qu'on avait eu sur Meshy. Difference de fond avec Meshy a
# connaitre : Tripo encode la couleur par sommet du maillage (degrade continu), pas une palette
# figee a N couleurs - pas de parametre "nombre de couleurs" equivalent a $MaxCouleurs cote Tripo.
$BaseUrlTripo = "https://openapi.tripo3d.ai/v3"

function Attendre-TacheTripo($UrlTache, $Entetes, $Libelle) {
    $debut = Get-Date
    while ($true) {
        if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
        if (((Get-Date) - $debut).TotalSeconds -gt $TimeoutTacheSecondes) {
            throw "$Libelle : pas de reponse apres $($TimeoutTacheSecondes / 60) min"
        }
        $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri $UrlTache -Headers $Entetes -Method Get -TimeoutSec 15 } $Libelle
        # La reponse Tripo enveloppe les donnees dans un champ "data" (confirme par plusieurs
        # exemples de SDK), contrairement a Meshy qui renvoie directement l'objet a plat.
        $tache = if ($reponse.data) { $reponse.data } else { $reponse }
        # Correspondance large et insensible a la casse : le nom exact des statuts Tripo n'a
        # jamais ete confirme avec certitude (contrairement a Meshy), donc on couvre plusieurs
        # formulations plausibles plutot que d'attendre un seul mot precis qui pourrait ne jamais
        # arriver - c'etait tres probablement la vraie cause du blocage de plusieurs minutes.
        $statutBrut = "$($tache.status)"
        if ($statutBrut -match '^(success|succeeded|completed|done|finished)$') {
            return $tache
        } elseif ($statutBrut -match '^(failed|failure|error)$') {
            throw "$Libelle a echoue : $($tache.error_message)"
        } elseif ($statutBrut -match '^(banned|blocked|rejected)$') {
            throw "$Libelle refusee (contenu signale par Tripo)"
        } elseif ($statutBrut -match '^(cancelled|canceled)$') {
            throw "$Libelle a ete annulee"
        } else {
            Ecrire-Journal "    $Libelle : statut brut recu = '$statutBrut' ($($tache.progress)%)..."
            # 17/10/2026 : meme correctif que cote Meshy (Attendre-Tache plus haut) - relaie la
            # vraie progression de la tache Tripo en cours dans l'overlay a chaque poll, au lieu de
            # le laisser bloque a 0% jusqu'a la fin du fichier.
            $creditsOverlayTexte = " - $([Math]::Round($script:creditsReelsLot, 1)) credit(s)"
            Mettre-A-Jour-OverlayProgression ([int]$tache.progress) $null $creditsOverlayTexte
        }
        for ($i = 0; $i -lt $IntervallePollSecondes; $i++) {
            if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
            Afficher-ProgressionEnCours "$Libelle en cours..."
            Start-Sleep -Seconds 1
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

# 20/10/2026 : simplification Tripo avant texturation, parite avec Lancer-Remesh cote Meshy (voir
# $SEUIL_TRIANGLES_REMESH_AUTO plus haut) - API Retopology de Tripo (POST /v3/mesh/decimate),
# confirmee via le changelog officiel d'octobre 2026 et sa doc dediee
# (developers.tripo3d.ai/fr/docs/mesh-decimate) : "input" accepte directement le file_token issu de
# l'upload (pas besoin de passer par import_model d'abord, son task_id sert ensuite tel quel comme
# reference de modele pour la texturation - meme principe que le Remesh Meshy, dont le resultat
# remplace l'envoi du fichier brut). "face_limit" va de 500 a 20000 triangles en modele par defaut
# (v2.0, 30 credits) - la cible demandee (champ "Triangles vises" de l'interface, jusqu'a 300000)
# est donc bornee a cette plage plutot que d'envoyer une valeur hors limites que l'API rejetterait.
function Lancer-DecimateTripo($Entetes, $JetonFichier, [int]$TargetFaceLimit) {
    $cible = [Math]::Max(500, [Math]::Min(20000, $TargetFaceLimit))
    Ecrire-Journal "  Maillage volumineux - simplification (Retopology Tripo) avant texturation, cible ~$cible triangle(s)..."
    $corps = @{ input = $JetonFichier; face_limit = $cible } | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/mesh/decimate" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30 } "Retopology Tripo"
    $idDecimateReponse = if ($reponse.data) { $reponse.data } else { $reponse }
    $idDecimate = $idDecimateReponse.task_id
    $tache = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idDecimate" $Entetes "Retopology"
    Ecrire-Journal "  Maillage simplifie ($($tache.credits_consumed) credits) - la texturation va repartir de ce resultat (import_model saute, pas necessaire ici)."
    return $tache
}

# 20/10/2026, Tomyn : "pour l'image ca sera bien d'avoir Tripo aussi" - equivalent Tripo de
# Lancer-Image3D (Meshy) : POST /v3/generation/image-to-model, confirme via
# developers.tripo3d.ai/fr/docs/generation-image-to-model/standard. "input" accepte le file_token
# issu du meme upload presigne que pour un modele 3D (pas d'endpoint different). "texture"/"pbr" a
# $false quand un prompt sera envoye separement a models/texture juste apres (meme logique que cote
# Meshy, devise sa : "payer la texturation deux fois... n'aurait aucun sens") ; a $true quand il n'y
# a pas de prompt, pour laisser Tripo texturer directement depuis la photo plutot que de faire un
# appel Texture separe sans rien a lui dire de particulier.
#
# 22/10/2026, Tomyn : bug remonte ou la boite "Modele d'importation" de Bambu Studio (regroupement
# auto des couleurs par sommet en N filaments) reste quasi plate sur un .obj genere par l'appli,
# alors que le MEME .obj genere directement via le site web Tripo (meme image source, confirme par
# Tomyn : "l'image est la meme") s'y regroupe correctement. Comparaison octet pour octet des deux
# fichiers (statistiques RGB/teinte, nettete des transitions entre zones de couleur voisines) sans
# trouver de difference franche - MAIS "pbr" vaut true PAR DEFAUT chez Tripo (confirme dans leur
# doc), hypothese : un materiau PBR (cartes couleur/rugosite/normale projetees en UV, pensees pour
# un rendu realiste) exporte moins bien en simple couleur-par-sommet qu'une texture "standard"
# classique - le site web Tripo ne force peut-etre pas ce mode PBR par defaut pour une simple
# generation image -> modele. $AvecTexture (true pour "pas de prompt, Tripo texture directement
# depuis la photo") forcait aussi pbr=true jusqu'ici - separe desormais : texture demandee comme
# avant, mais pbr explicitement a $false. PAS CONFIRME avec une vraie generation Tripo (pas d'acces
# a la cle API de Tomyn pour tester ici, et ca consommerait des credits) - a verifier par Tomyn.
function Lancer-ImageModelTripo($Entetes, $JetonFichier, [bool]$AvecTexture) {
    Ecrire-Journal "  Envoi a l'API Image to 3D (Tripo)..."
    # 20/10/2026, trouve en usage reel par Tomyn : malgre la doc qui donne "v3.1-20260211" comme
    # defaut (sous-entendant le champ facultatif), l'API refuse desormais la requete sans "model"
    # explicite - erreur reelle recue : {"code":1004,...,"message":"model is required, allowed
    # values: P1-20260311, P2-20260801, v2.5-20250123, v3.0-20250812, v3.1-20260211"}. On envoie
    # donc explicitement la valeur la plus recente de cette liste (v3.1-20260211, qui est deja
    # celle documentee comme defaut) plutot que de compter sur un defaut cote serveur.
    $corps = @{ input = $JetonFichier; model = "v3.1-20260211"; texture = $AvecTexture; pbr = $false } | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/generation/image-to-model" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30 } "Image to 3D Tripo"
    $idReponse = if ($reponse.data) { $reponse.data } else { $reponse }
    $idTache = $idReponse.task_id
    $tache = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idTache" $Entetes "Image to 3D"
    Ecrire-Journal "  Modele genere depuis l'image ($($tache.credits_consumed) credits)."
    return $tache
}

# =====================================================================================
# Conversion automatique de l'OBJ colore par sommet (export Tripo) en .3mf peint pour
# Bambu Studio. 21/10/2026, demande de Tomyn suite au bug "pas un vrai .3mf" remonte sur
# le Melangeur (voir CHANGELOG.md melangecouleurs3mf) avec un fichier issu de ce pipeline
# Tripo - puis demande explicite de transformer directement l'OBJ colore en .3mf peint,
# automatiquement, a cote de l'OBJ (pas un outil/bouton separe).
#
# Format d'entree (confirme par recherche : doc Tripo + doc 3D AI Studio, meme
# ecosysteme) : lignes "v x y z r g b" (couleur ajoutee aux 3 premieres coordonnees,
# extension non standard mais repandue type MeshLab/PCL), lignes "f ..." standard (index
# 1-based, eventuellement suivis de /texture/normale a ignorer).
#
# Format de sortie (confirme par lecture du vrai code source BambuStudio/OrcaSlicer, pas
# d'une doc tierce) : attribut "paint_color" en hexa MAJUSCULE directement sur chaque
# <triangle> de 3D/3dmodel.model. Regle (etat = index de filament/extrudeur, 1-based) :
#   etat 0 (non peint)   -> pas d'attribut du tout
#   etat 1 ou 2          -> UN nibble = etat*4, converti en 1 chiffre hexa (4 ou 8)
#   etat 3..17           -> DEUX nibbles ecrits dans l'ordre [C, etat-3], mais chaque
#                            nouveau nibble est PREPEND au resultat -> chaine finale =
#                            hex(etat-3) + "C"
#   etat >= 18           -> C, puis floor((etat-3)/15) nibbles F, puis le nibble terminal
#                            (etat-3) % 15 - chaine finale (prepend a chaque etape) =
#                            hex(terminal) + "F"*repeats + "C"
#
# 21/10/2026, v2 : REECRITURE PERFORMANCE suite a un vrai blocage en production chez
# Tomyn (fenetre "Ne repond pas", sur un lot vise a 300000 triangles - jamais teste a
# cette echelle avant, seulement sur de petits fixtures de test). La v1 utilisait un
# PSCustomObject par sommet/triangle et des pipelines ForEach-Object, avec un k-means
# O(n*k*iterations) applique a TOUS les triangles - bien trop lent au-dela de quelques
# milliers de triangles, et bloquait le thread UI sans jamais pomper les messages
# Windows. Reecrite en tableaux primitifs (double[]/int[]) + k-means ajuste sur un
# ECHANTILLON borne (20000 points par defaut) suivi d'une SEULE passe d'affectation
# lineaire sur tous les triangles, avec pompage periodique des messages UI (Pomper-
# MessagesUI) dans les boucles longues. Teste reellement a 299538 triangles (grille
# 388x388) : ~15-16s, contre un blocage indefini avant.
#
# AVERTISSEMENT honnete : je n'ai pas Bambu Studio sous la main pour verifier a l'oeil que
# le .3mf produit s'ouvre et se peint correctement - le moteur est verifie par execution
# reelle (parsing, clustering, ecriture ET relecture du zip/XML produits, y compris a
# l'echelle de 300000 triangles, voir les tests), mais seul un premier essai reel de
# Tomyn dans Bambu Studio validera le resultat final.

function Convertir-EtatFilamentEnPaintColor([int]$EtatFilament) {
    if ($EtatFilament -le 0) { return $null }
    if ($EtatFilament -le 2) {
        $nibble = $EtatFilament * 4
        return ("{0:X}" -f $nibble)
    }
    if ($EtatFilament -le 17) {
        $nibbleTerminal = $EtatFilament - 3
        return ("{0:X}" -f $nibbleTerminal) + "C"
    }
    $n = $EtatFilament - 3
    $repetitionsF = [Math]::Floor($n / 15)
    $terminal = $n % 15
    return ("{0:X}" -f $terminal) + ("F" * $repetitionsF) + "C"
}

# Pompe les messages Windows (evite le "Ne repond pas") pendant les boucles longues -
# no-op silencieux si WinForms n'est pas charge dans le contexte d'appel (tests isoles).
function Pomper-MessagesUI {
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

# Lit un OBJ colore par sommet (export Tripo) en tableaux primitifs (pas d'objet par
# sommet/triangle - essentiel pour la vitesse sur de gros maillages, voir note v2
# ci-dessus). Index de sommet en sortie 0-based (plus pratique pour l'indexation
# PowerShell derriere, meme si l'OBJ lui-meme est 1-based).
function Lire-ObjColoreParSommet([string]$CheminObj) {
    $vx = New-Object System.Collections.Generic.List[double]
    $vy = New-Object System.Collections.Generic.List[double]
    $vz = New-Object System.Collections.Generic.List[double]
    $vr = New-Object System.Collections.Generic.List[int]
    $vg = New-Object System.Collections.Generic.List[int]
    $vb = New-Object System.Collections.Generic.List[int]
    $t1 = New-Object System.Collections.Generic.List[int]
    $t2 = New-Object System.Collections.Generic.List[int]
    $t3 = New-Object System.Collections.Generic.List[int]

    $cultureInvariante = [System.Globalization.CultureInfo]::InvariantCulture
    $separateurs = [char[]]@(' ', "`t")
    $optionsSplit = [System.StringSplitOptions]::RemoveEmptyEntries
    $compteurLignes = 0

    foreach ($ligne in [System.IO.File]::ReadLines($CheminObj)) {
        $compteurLignes++
        if ($compteurLignes % 50000 -eq 0) { Pomper-MessagesUI }

        if ($ligne.Length -lt 2) { continue }
        $premier = $ligne[0]
        if ($premier -ne 'v' -and $premier -ne 'f') { continue }

        if ($premier -eq 'v' -and $ligne[1] -eq ' ') {
            $parties = $ligne.Split($separateurs, $optionsSplit)
            # parties[0] == "v" ; x,y,z en [1..3] ; couleur optionnelle en [4..6].
            if ($parties.Count -lt 4) { continue }
            [void]$vx.Add([double]::Parse($parties[1], $cultureInvariante))
            [void]$vy.Add([double]::Parse($parties[2], $cultureInvariante))
            [void]$vz.Add([double]::Parse($parties[3], $cultureInvariante))
            if ($parties.Count -ge 7) {
                $r = [double]::Parse($parties[4], $cultureInvariante)
                $g = [double]::Parse($parties[5], $cultureInvariante)
                $b = [double]::Parse($parties[6], $cultureInvariante)
                # Certains exporteurs ecrivent du 0-1, d'autres du 0-255 - une seule valeur
                # du triplet au-dela de 1.5 suffit a trancher pour l'echelle 0-255 (une
                # couleur reelle en 0-1 ne depasse jamais 1.0 ; la marge de 1.5 evite un
                # faux positif sur une valeur 1.0 arrondie au-dessus par erreur de
                # precision flottante).
                if ($r -gt 1.5 -or $g -gt 1.5 -or $b -gt 1.5) { $r /= 255.0; $g /= 255.0; $b /= 255.0 }
                [void]$vr.Add([int][Math]::Round([Math]::Max(0, [Math]::Min(255, $r * 255))))
                [void]$vg.Add([int][Math]::Round([Math]::Max(0, [Math]::Min(255, $g * 255))))
                [void]$vb.Add([int][Math]::Round([Math]::Max(0, [Math]::Min(255, $b * 255))))
            } else {
                [void]$vr.Add(255); [void]$vg.Add(255); [void]$vb.Add(255)
            }
        } elseif ($premier -eq 'f' -and $ligne[1] -eq ' ') {
            $parties = $ligne.Split($separateurs, $optionsSplit)
            # parties[0] == "f" ; chaque jeton suivant est un index de sommet, eventuellement
            # suivi de "/texture/normale" a ignorer (pris avant le premier '/', sans regex
            # pour la vitesse).
            $nbSommetsFace = $parties.Count - 1
            if ($nbSommetsFace -lt 3) { continue }
            $indices = New-Object int[] $nbSommetsFace
            for ($k = 0; $k -lt $nbSommetsFace; $k++) {
                $jeton = $parties[$k + 1]
                $posSlash = $jeton.IndexOf('/')
                $texteIndex = if ($posSlash -ge 0) { $jeton.Substring(0, $posSlash) } else { $jeton }
                $indiceBrut = [int]$texteIndex
                # 21/10/2026, bug trouve suite a l'echec d'ouverture du premier .3mf genere chez
                # Tomyn dans Bambu Studio ("chargement echoue" / "pas de donnees geometriques") :
                # le format OBJ autorise des index RELATIFS negatifs ("f -1 -2 -3" = les 3
                # derniers sommets definis jusqu'ici), deja geres par le rendu de vignette
                # existant (RenduSTL.ChargerObj, "sommets.Count + indice") mais oublies ici - un
                # index negatif etait traite comme positif, produisant un index de sommet
                # completement faux, de maniere silencieuse (pas d'exception). Confirme par
                # recherche dans le vrai parseur de Bambu Studio (bbs_3mf.cpp) : UN SEUL triangle
                # avec un index hors bornes fait rejeter TOUT le fichier au chargement.
                $indices[$k] = if ($indiceBrut -gt 0) { $indiceBrut - 1 } else { $vx.Count + $indiceBrut }
            }
            # Triangulation en eventail si plus de 3 sommets (quad/polygone).
            for ($k = 1; $k -lt $nbSommetsFace - 1; $k++) {
                [void]$t1.Add($indices[0]); [void]$t2.Add($indices[$k]); [void]$t3.Add($indices[$k + 1])
            }
        }
    }

    if ($vx.Count -eq 0) { throw "aucun sommet lu dans l'OBJ (fichier vide ou format inattendu) : $CheminObj" }
    if ($t1.Count -eq 0) { throw "aucun triangle lu dans l'OBJ (fichier vide ou format inattendu) : $CheminObj" }

    # Filet de securite : Bambu Studio rejette tout le fichier des qu'UN SEUL triangle reference
    # un index de sommet hors bornes (confirme par lecture du vrai parseur bbs_3mf.cpp). Plutot
    # que de risquer de livrer un .3mf invalide pour une seule face fautive parmi potentiellement
    # plusieurs millions, on ecarte ici les triangles invalides et on le journalise, au lieu de
    # laisser Bambu Studio decouvrir le probleme et rejeter tout le fichier sans dire pourquoi.
    $nbSommets = $vx.Count
    $t1Valides = New-Object System.Collections.Generic.List[int]
    $t2Valides = New-Object System.Collections.Generic.List[int]
    $t3Valides = New-Object System.Collections.Generic.List[int]
    $nbTrianglesInvalides = 0
    for ($i = 0; $i -lt $t1.Count; $i++) {
        $a = $t1[$i]; $b = $t2[$i]; $c = $t3[$i]
        if ($a -ge 0 -and $a -lt $nbSommets -and $b -ge 0 -and $b -lt $nbSommets -and $c -ge 0 -and $c -lt $nbSommets) {
            [void]$t1Valides.Add($a); [void]$t2Valides.Add($b); [void]$t3Valides.Add($c)
        } else {
            $nbTrianglesInvalides++
        }
    }
    if ($nbTrianglesInvalides -gt 0) {
        Ecrire-Journal "  -> ATTENTION : $nbTrianglesInvalides triangle(s) avec un index de sommet hors bornes ont ete ignores (sur $($t1.Count) au total)."
    }
    if ($t1Valides.Count -eq 0) { throw "tous les triangles referencent des index de sommet hors bornes - OBJ probablement corrompu : $CheminObj" }

    return [PSCustomObject]@{
        VX = $vx.ToArray(); VY = $vy.ToArray(); VZ = $vz.ToArray()
        VR = $vr.ToArray(); VG = $vg.ToArray(); VB = $vb.ToArray()
        T1 = $t1Valides.ToArray(); T2 = $t2Valides.ToArray(); T3 = $t3Valides.ToArray()
    }
}

# Couleur representative de chaque triangle = moyenne RGB de ses 3 sommets (une seule
# passe lineaire sur des tableaux primitifs, pas de pipeline/objet par triangle).
function Obtenir-CouleursTriangles($Donnees) {
    $n = $Donnees.T1.Count
    $tr = New-Object int[] $n
    $tg = New-Object int[] $n
    $tb = New-Object int[] $n
    $vr = $Donnees.VR; $vg = $Donnees.VG; $vb = $Donnees.VB
    $t1 = $Donnees.T1; $t2 = $Donnees.T2; $t3 = $Donnees.T3
    for ($i = 0; $i -lt $n; $i++) {
        $a = $t1[$i]; $b = $t2[$i]; $c = $t3[$i]
        $tr[$i] = [int](($vr[$a] + $vr[$b] + $vr[$c]) / 3)
        $tg[$i] = [int](($vg[$a] + $vg[$b] + $vg[$c]) / 3)
        $tb[$i] = [int](($vb[$a] + $vb[$b] + $vb[$c]) / 3)
        if ($i % 50000 -eq 0) { Pomper-MessagesUI }
    }
    return [PSCustomObject]@{ TR = $tr; TG = $tg; TB = $tb }
}

# K-means en espace RGB, en tableaux primitifs (regroupement grossier pour la peinture
# du .3mf, pas un dosage de melange precis - ca reste le travail du Melangeur en aval).
# L'AJUSTEMENT des centres se fait sur un ECHANTILLON borne (20000 points par defaut,
# deterministe - pas aleatoire) pour que le cout n'explose jamais avec la taille du
# maillage ; l'AFFECTATION finale reste une seule passe lineaire O(n*k) sur TOUS les
# triangles (pas de re-iteration), donc toujours rapide meme a 300000+ triangles.
function Grouper-CouleursKMeans($CouleursTriangles, [int]$K, [int]$IterationsMax = 15, [int]$EchantillonMax = 20000) {
    $tr = $CouleursTriangles.TR; $tg = $CouleursTriangles.TG; $tb = $CouleursTriangles.TB
    $n = $tr.Count
    if ($n -eq 0) { return [PSCustomObject]@{ CentresR = @(); CentresG = @(); CentresB = @(); Affectations = (New-Object int[] 0) } }

    if ($n -gt $EchantillonMax) {
        $pas = [Math]::Max(1, [int]($n / $EchantillonMax))
        $indicesEchantillon = New-Object System.Collections.Generic.List[int]
        for ($i = 0; $i -lt $n; $i += $pas) { [void]$indicesEchantillon.Add($i) }
    } else {
        $indicesEchantillon = New-Object System.Collections.Generic.List[int]
        for ($i = 0; $i -lt $n; $i++) { [void]$indicesEchantillon.Add($i) }
    }
    $nEch = $indicesEchantillon.Count

    $vues = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($idx in $indicesEchantillon) {
        [void]$vues.Add(($tr[$idx] -shl 16) -bor ($tg[$idx] -shl 8) -bor $tb[$idx])
    }
    $kReel = [Math]::Min($K, $vues.Count)
    if ($kReel -le 0) { return [PSCustomObject]@{ CentresR = @(); CentresG = @(); CentresB = @(); Affectations = (New-Object int[] $n) } }

    # 21/10/2026, retour de Tomyn : avec un trio Melangeur, les 16 couleurs demandees ressortaient
    # bien au nombre de 16 mais "tres approchantes" les unes des autres au lieu de couvrir le
    # noir/beige/marron-rouge reel du modele. Cause : l'ancienne initialisation prenait les germes
    # en parcourant l'ECHANTILLON dans son ORDRE DE FICHIER (pas selon la diversite des couleurs) -
    # sur un maillage ou une seule couleur dominante occupe la majorite des triangles, la plupart
    # des germes atterrissaient dans cette zone et le k-means convergeait vers plusieurs centres
    # quasi identiques au lieu de capturer les vraies couleurs minoritaires (taches, collier).
    # Remplace par un "farthest-point seeding" deterministe (variante sans alea de k-means++) : le
    # premier germe est le premier point de l'echantillon, puis chaque germe suivant est le point
    # le PLUS ELOIGNE (en couleur) de tous les germes deja choisis - garantit des centres de depart
    # bien repartis sur toute la diversite de couleurs, quel que soit le nombre de couleurs demande.
    $cr = New-Object double[] $kReel
    $cg = New-Object double[] $kReel
    $cb = New-Object double[] $kReel
    $distMinGerme = New-Object double[] $nEch
    for ($j = 0; $j -lt $nEch; $j++) { $distMinGerme[$j] = [double]::MaxValue }

    $idxGerme0 = $indicesEchantillon[0]
    $cr[0] = $tr[$idxGerme0]; $cg[0] = $tg[$idxGerme0]; $cb[0] = $tb[$idxGerme0]

    for ($c = 1; $c -lt $kReel; $c++) {
        $dernierR = $cr[$c - 1]; $dernierG = $cg[$c - 1]; $dernierB = $cb[$c - 1]
        $meilleurJ = 0; $meilleureDistMax = -1.0
        for ($j = 0; $j -lt $nEch; $j++) {
            $idx = $indicesEchantillon[$j]
            $dr = $tr[$idx] - $dernierR; $dg = $tg[$idx] - $dernierG; $db = $tb[$idx] - $dernierB
            $d = $dr * $dr + $dg * $dg + $db * $db
            if ($d -lt $distMinGerme[$j]) { $distMinGerme[$j] = $d }
            if ($distMinGerme[$j] -gt $meilleureDistMax) { $meilleureDistMax = $distMinGerme[$j]; $meilleurJ = $j }
        }
        $idxGerme = $indicesEchantillon[$meilleurJ]
        $cr[$c] = $tr[$idxGerme]; $cg[$c] = $tg[$idxGerme]; $cb[$c] = $tb[$idxGerme]
    }

    $affEch = New-Object int[] $nEch
    for ($iter = 0; $iter -lt $IterationsMax; $iter++) {
        $aChange = $false
        for ($j = 0; $j -lt $nEch; $j++) {
            $idx = $indicesEchantillon[$j]
            $r = $tr[$idx]; $g = $tg[$idx]; $b = $tb[$idx]
            $meilleur = 0; $meilleureDist = [double]::MaxValue
            for ($c = 0; $c -lt $kReel; $c++) {
                $dr = $r - $cr[$c]; $dg = $g - $cg[$c]; $db = $b - $cb[$c]
                $d = $dr * $dr + $dg * $dg + $db * $db
                if ($d -lt $meilleureDist) { $meilleureDist = $d; $meilleur = $c }
            }
            if ($affEch[$j] -ne $meilleur) { $aChange = $true }
            $affEch[$j] = $meilleur
        }
        $sommeR = New-Object double[] $kReel; $sommeG = New-Object double[] $kReel; $sommeB = New-Object double[] $kReel
        $compte = New-Object int[] $kReel
        for ($j = 0; $j -lt $nEch; $j++) {
            $c = $affEch[$j]; $idx = $indicesEchantillon[$j]
            $sommeR[$c] += $tr[$idx]; $sommeG[$c] += $tg[$idx]; $sommeB[$c] += $tb[$idx]
            $compte[$c]++
        }
        for ($c = 0; $c -lt $kReel; $c++) {
            if ($compte[$c] -gt 0) {
                $cr[$c] = $sommeR[$c] / $compte[$c]
                $cg[$c] = $sommeG[$c] / $compte[$c]
                $cb[$c] = $sommeB[$c] / $compte[$c]
            }
        }
        Pomper-MessagesUI
        if (-not $aChange) { break }
    }

    $affectations = New-Object int[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $r = $tr[$i]; $g = $tg[$i]; $b = $tb[$i]
        $meilleur = 0; $meilleureDist = [double]::MaxValue
        for ($c = 0; $c -lt $kReel; $c++) {
            $dr = $r - $cr[$c]; $dg = $g - $cg[$c]; $db = $b - $cb[$c]
            $d = $dr * $dr + $dg * $dg + $db * $db
            if ($d -lt $meilleureDist) { $meilleureDist = $d; $meilleur = $c }
        }
        $affectations[$i] = $meilleur
        if ($i % 50000 -eq 0) { Pomper-MessagesUI }
    }

    $centresRint = New-Object int[] $kReel
    $centresGint = New-Object int[] $kReel
    $centresBint = New-Object int[] $kReel
    for ($c = 0; $c -lt $kReel; $c++) {
        $centresRint[$c] = [int][Math]::Round($cr[$c])
        $centresGint[$c] = [int][Math]::Round($cg[$c])
        $centresBint[$c] = [int][Math]::Round($cb[$c])
    }

    return [PSCustomObject]@{ CentresR = $centresRint; CentresG = $centresGint; CentresB = $centresBint; Affectations = $affectations }
}

function Obtenir-HexDepuisRGB24([int]$R, [int]$G, [int]$B) {
    return ("#{0:X2}{1:X2}{2:X2}" -f $R, $G, $B)
}

# 21/10/2026, retour de Tomyn apres avoir enfin pu ouvrir un .3mf peint : "les couleurs sont pas
# tres bien definies, on dirait qu'il a fait ca a l'arrache". Cause : les couleurs de sommet
# exportees par Tripo integrent l'ombrage du rendu (pas des couleurs "materiau" plates), donc la
# simple moyenne par triangle + k-means produit des affectations bruitees - des triangles isoles
# mal classes au milieu d'une zone par ailleurs uniforme. Les 2 fonctions suivantes construisent
# l'adjacence des triangles (voisins = triangles partageant une arete) puis lissent les
# affectations par vote majoritaire, pour corriger ces triangles isoles sans effacer les
# vraies frontieres de couleur (qui ont toujours une majorite de voisins du meme cote).
function Obtenir-VoisinsTriangles($Donnees) {
    $n = $Donnees.T1.Count
    $voisin1 = New-Object int[] $n; $voisin2 = New-Object int[] $n; $voisin3 = New-Object int[] $n
    for ($i = 0; $i -lt $n; $i++) { $voisin1[$i] = -1; $voisin2[$i] = -1; $voisin3[$i] = -1 }
    # Cle = arete non orientee (min,max sommets) empaquetee dans un long - pas besoin de
    # materialiser une vraie liste d'aretes : chaque arete est resolue (appariee) des qu'elle
    # est vue une 2e fois, puis retiree du dictionnaire.
    $aretesEnAttente = New-Object 'System.Collections.Generic.Dictionary[long,long]'
    $t1 = $Donnees.T1; $t2 = $Donnees.T2; $t3 = $Donnees.T3
    for ($i = 0; $i -lt $n; $i++) {
        $sommetsTri = @($t1[$i], $t2[$i], $t3[$i])
        for ($slot = 0; $slot -lt 3; $slot++) {
            $u = $sommetsTri[$slot]; $v = $sommetsTri[($slot + 1) % 3]
            $mn = [Math]::Min($u, $v); $mx = [Math]::Max($u, $v)
            $cle = ([long]$mn -shl 32) -bor [long]$mx
            $valeur = $null
            if ($aretesEnAttente.TryGetValue($cle, [ref]$valeur)) {
                $jAutre = [int]($valeur -shr 2); $slotAutre = [int]($valeur -band 3)
                switch ($slot) { 0 { $voisin1[$i] = $jAutre } 1 { $voisin2[$i] = $jAutre } 2 { $voisin3[$i] = $jAutre } }
                switch ($slotAutre) { 0 { $voisin1[$jAutre] = $i } 1 { $voisin2[$jAutre] = $i } 2 { $voisin3[$jAutre] = $i } }
                $aretesEnAttente.Remove($cle) | Out-Null
            } else {
                $aretesEnAttente[$cle] = ([long]$i -shl 2) -bor [long]$slot
            }
        }
        if ($i % 50000 -eq 0) { Pomper-MessagesUI }
    }
    return [PSCustomObject]@{ V1 = $voisin1; V2 = $voisin2; V3 = $voisin3 }
}

function Lisser-AffectationsCouleurs($Voisins, [int[]]$Affectations, [int]$Iterations = 2) {
    $n = $Affectations.Count
    if ($n -eq 0) { return $Affectations }
    # Comparaisons manuelles (pas de pipeline Group-Object/Where-Object par triangle - beaucoup
    # trop lent sur plusieurs millions de triangles, recreerait le blocage "Ne repond pas" deja
    # corrige ailleurs). Au plus 3 voisins : le "vote majoritaire" se reduit a quelques
    # comparaisons directes.
    $v1 = $Voisins.V1; $v2 = $Voisins.V2; $v3 = $Voisins.V3
    $courant = $Affectations.Clone()

    for ($iter = 0; $iter -lt $Iterations; $iter++) {
        $suivant = $courant.Clone()
        for ($i = 0; $i -lt $n; $i++) {
            $cas = 0
            $l1 = -1; $l2 = -1; $l3 = -1
            if ($v1[$i] -ge 0) { $l1 = $courant[$v1[$i]]; $cas++ }
            if ($v2[$i] -ge 0) { $l2 = $courant[$v2[$i]]; $cas++ }
            if ($v3[$i] -ge 0) { $l3 = $courant[$v3[$i]]; $cas++ }
            if ($cas -lt 2) { continue }

            $modeEtiquette = -1; $modeCompte = 0
            if ($cas -eq 2) {
                if ($l1 -ge 0 -and $l1 -eq $l2) { $modeEtiquette = $l1; $modeCompte = 2 }
                elseif ($l1 -ge 0 -and $l1 -eq $l3) { $modeEtiquette = $l1; $modeCompte = 2 }
                elseif ($l2 -ge 0 -and $l2 -eq $l3) { $modeEtiquette = $l2; $modeCompte = 2 }
            } else {
                if ($l1 -eq $l2 -and $l2 -eq $l3) { $modeEtiquette = $l1; $modeCompte = 3 }
                elseif ($l1 -eq $l2) { $modeEtiquette = $l1; $modeCompte = 2 }
                elseif ($l1 -eq $l3) { $modeEtiquette = $l1; $modeCompte = 2 }
                elseif ($l2 -eq $l3) { $modeEtiquette = $l2; $modeCompte = 2 }
            }

            if ($modeCompte -ge 2 -and $modeEtiquette -ne $courant[$i]) {
                $suivant[$i] = $modeEtiquette
            }
            if ($i % 50000 -eq 0) { Pomper-MessagesUI }
        }
        $courant = $suivant
    }
    return $courant
}

# 21/10/2026, cause racine du rejet du .3mf par Bambu Studio ("chargement echoue" / "pas de
# donnees geometriques") sur le vrai fichier de Tomyn : [System.Text.Encoding]::UTF8 de .NET
# ecrit un BOM (3 octets EF BB BF) en tete de fichier avec WriteAllText - confirme en inspectant
# octet par octet le .3mf rejete (envoye par Tomyn), qui commencait bien par EF BB BF avant
# "<?xml", alors que le XML lui-meme etait par ailleurs complet et bien forme (pas de troncature).
# Reproduit et corrige sur le vrai fichier (730372 sommets, 1460768 triangles) : le XML reparse
# sans erreur une fois le BOM retire.
$script:EncodageUtf8SansBOM = New-Object System.Text.UTF8Encoding($false)

# Fonction principale : lit l'OBJ colore par Tripo, regroupe les couleurs en au plus
# $NombreCouleursMax teintes, et ecrit un .3mf peint directement exploitable dans Bambu
# Studio (geometrie + attribut paint_color par triangle + palette filament_colour dans
# Metadata/project_settings.config, meme schema que celui deja lu par le Melangeur).
# 21/10/2026 : genere Metadata/project_settings.config dans le MEME format qu'un vrai export
# BambuStudio (confirme en inspectant un .3mf Meshy fourni par Tomyn, qui s'ouvre sans probleme
# dans Bambu Studio avec toutes ses couleurs) - necessaire car le fichier se declare maintenant
# "Application: BambuStudio-..." (voir Convertir-ObjColoreVers3mfPeint), donc Bambu Studio traite
# ce fichier comme un vrai projet BambuStudio et LIT reellement ce fichier (contrairement a avant).
# Couleurs au format RGBA 8 chiffres (#RRGGBBFF) - confirme que c'est le format attendu (Meshy
# utilise ce format, pas #RRGGBB a 6 chiffres).
function Construire-ProjectSettingsBambu($HexCouleurs) {
    $n = $HexCouleurs.Count
    if ($n -eq 0) { $n = 1 }
    $couleursRgba = @($HexCouleurs | ForEach-Object { "$_" + "FF" })
    if ($couleursRgba.Count -eq 0) { $couleursRgba = @("#CCCCCCFF") }

    $matriceFlush = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = 0; $j -lt $n; $j++) {
            $valeurFlush = "280"
            if ($i -eq $j) { $valeurFlush = "0" }
            [void]$matriceFlush.Add($valeurFlush)
        }
    }
    $vecteurFlush = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt (2 * $n); $i++) { [void]$vecteurFlush.Add("140") }

    $repete = { param($valeur) @(1..$n | ForEach-Object { $valeur }) }

    $config = [ordered]@{
        filament_colour                       = $couleursRgba
        filament_settings_id                  = (& $repete "Bambu PLA Basic @BBL X1C")
        filament_type                         = (& $repete "PLA")
        filament_minimal_purge_on_wipe_tower  = (& $repete "15")
        filament_flow_ratio                   = (& $repete "0.98")
        filament_diameter                     = (& $repete "1.75")
        wipe                                   = (& $repete "1")
        wipe_distance                         = (& $repete "2")
        retract_length_toolchange             = (& $repete "2")
        retract_restart_extra_toolchange      = (& $repete "0")
        standby_temperature_delta             = "-5"
        enable_prime_tower                    = "1"
        prime_tower_width                     = "20"
        prime_tower_brim_width                = "3"
        prime_volume                          = "20"
        flush_into_infill                     = "0"
        flush_into_objects                    = "0"
        flush_into_support                    = "1"
        flush_multiplier                      = "1"
        flush_volumes_matrix                  = $matriceFlush.ToArray()
        flush_volumes_vector                  = $vecteurFlush.ToArray()
        wipe_tower_x                          = @("15")
        wipe_tower_y                          = @("145")
        wipe_tower_rotation_angle             = "0"
        wipe_tower_no_sparse_layers           = "0"
        wipe_speed                            = "80%"
        single_extruder_multi_material        = "1"
        print_sequence                        = "by layer"
        printer_model                         = "Bambu Lab A1"
        printer_settings_id                   = "Bambu Lab A1 0.4 nozzle"
        nozzle_diameter                       = @("0.4")
        print_settings_id                     = "0.20mm Standard @BBL A1"
        layer_change_gcode                    = "; layer change`nG92 E0`n"
        from                                   = "project"
        name                                   = "project_settings"
        version                                = "02.03.01.00"
    }
    return ($config | ConvertTo-Json -Depth 5)
}

# 21/10/2026 : genere Metadata/model_settings.config, desormais OBLIGATOIRE des que le fichier se
# declare "Application: BambuStudio-..." - sans ce fichier (ou avec un contenu que Bambu Studio
# n'arrive pas a parser), le chargement du .3mf echoue EN ENTIER ("Archive does not contain a
# valid model config"), confirme dans le code source reel de Bambu Studio. Structure copiee de
# celle d'un vrai .3mf Meshy fonctionnel fourni par Tomyn (object id=1 ici, pas de composants
# separes puisqu'on n'a qu'un seul objet dans un seul fichier).
function Construire-ModelSettingsBambu([int]$NombreTriangles) {
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="1">
    <metadata key="name" value="Model"/>
    <metadata key="extruder" value="1"/>
    <metadata face_count="$NombreTriangles"/>
  </object>
  <plate>
    <metadata key="plater_id" value="1"/>
    <metadata key="plater_name" value=""/>
    <metadata key="locked" value="false"/>
    <model_instance>
      <metadata key="object_id" value="1"/>
      <metadata key="instance_id" value="0"/>
      <metadata key="identify_id" value="1"/>
    </model_instance>
  </plate>
  <assemble>
  </assemble>
</config>
"@
}

function Convertir-ObjColoreVers3mfPeint([string]$CheminObj, [string]$CheminSortie3mf, [int]$NombreCouleursMax = 8, [double]$TailleImpressionMm = 0) {
    $donnees = Lire-ObjColoreParSommet $CheminObj

    # 22/10/2026, bug remonte par Tomyn (screenshot Bambu Studio : voiture couchee/de travers sur
    # le plateau, meme apres les correctifs de centrage/pose/echelle ci-dessous). Verifie sur le
    # vrai .obj Tripo (DeLorean) en isolant les sommets sombres (pneus/dessous de caisse, RVB <
    # 0.12) : ils se regroupent nettement du cote NEGATIF de l'axe Y du fichier source (median
    # -0,10 sur une plage de -0,26 a +0,26), pas de Z - preuve que Tripo (export Blender) sort
    # l'objet en Y-up (Y = la verticale), alors que 3mf/Bambu Studio attend du Z-up (Z = la
    # verticale). Le code copiait jusqu'ici Y->Y et Z->Z sans rotation : la largeur de la voiture
    # (Z source) se retrouvait verticale, et la hauteur reelle (Y source) a l'horizontale - d'ou
    # le modele couche. Corrige par une rotation de -90 degres autour de X (rotation rigide,
    # ne deforme ni ne retourne le maillage en miroir) : nouveau Y = -ancien Z, nouveau Z = ancien
    # Y, X inchange.
    for ($i = 0; $i -lt $donnees.VY.Count; $i++) {
        $zAvant = $donnees.VZ[$i]
        $donnees.VZ[$i] = $donnees.VY[$i]
        $donnees.VY[$i] = -$zAvant
    }

    $couleursTriangles = Obtenir-CouleursTriangles $donnees
    $groupes = Grouper-CouleursKMeans $couleursTriangles $NombreCouleursMax
    $voisinsTriangles = Obtenir-VoisinsTriangles $donnees
    $groupes.Affectations = Lisser-AffectationsCouleurs $voisinsTriangles $groupes.Affectations

    # 22/10/2026, bug remonte par Tomyn : le modele apparaissait MINUSCULE sur le plateau Bambu
    # Studio. Cause : l'export .obj de Tripo n'est PAS en metres comme suppose au premier correctif
    # (un facteur fixe *1000 donnait alors un objet de PRES D'1 METRE, verifie trop grand aussi) -
    # en realite Tripo normalise son maillage dans une boite de 1x1x1 SANS rapport avec une taille
    # physique reelle (confirme : le plus grand cote des coordonnees brutes vaut quasiment
    # exactement 1.0). Il n'y a donc pas de "bonne" taille a deduire du fichier lui-meme - on
    # reutilise le champ UI existant "Taille d'impression prevue (plus grand cote, mm)"
    # ($numTailleImpression, deja utilise pour Meshy/Lancer-AnalyseImprimabilite), avec le meme
    # defaut de repli que cote Meshy (150 mm) quand il vaut 0/n'est pas renseigne.
    $xMin = [double]::MaxValue; $xMax = [double]::MinValue
    $yMin = [double]::MaxValue; $yMax = [double]::MinValue
    $zMin = [double]::MaxValue; $zMax = [double]::MinValue
    for ($i = 0; $i -lt $donnees.VX.Count; $i++) {
        if ($donnees.VX[$i] -lt $xMin) { $xMin = $donnees.VX[$i] }
        if ($donnees.VX[$i] -gt $xMax) { $xMax = $donnees.VX[$i] }
        if ($donnees.VY[$i] -lt $yMin) { $yMin = $donnees.VY[$i] }
        if ($donnees.VY[$i] -gt $yMax) { $yMax = $donnees.VY[$i] }
        if ($donnees.VZ[$i] -lt $zMin) { $zMin = $donnees.VZ[$i] }
        if ($donnees.VZ[$i] -gt $zMax) { $zMax = $donnees.VZ[$i] }
    }
    $plusGrandCote = [Math]::Max(($xMax - $xMin), [Math]::Max(($yMax - $yMin), ($zMax - $zMin)))
    $tailleCibleMm = if ($TailleImpressionMm -gt 0) { $TailleImpressionMm } else { 150.0 }
    $echelle = if ($plusGrandCote -gt 0) { $tailleCibleMm / $plusGrandCote } else { 1.0 }
    # 22/10/2026, bug remonte par Tomyn (screenshot Bambu Studio : voiture coupee en deux par le
    # plateau, avertissement "objets places au-dessus") : l'export Tripo centre le maillage sur
    # l'origine (ex. Z de -63 a +63mm pour le chien) au lieu de le poser sur Z=0 comme Bambu
    # Studio l'attend pour un objet pose sur le plateau. Centre X/Y sur l'origine (deja a peu pres
    # le cas, mais garanti desormais) et Z recale pour que le dessous du modele touche Z=0.
    $centreX = ($xMin + $xMax) / 2.0
    $centreY = ($yMin + $yMax) / 2.0

    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("obj3mf_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $dossierTemp "3D") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dossierTemp "_rels") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dossierTemp "Metadata") -Force | Out-Null

    $hexCouleurs = New-Object System.Collections.Generic.List[string]
    for ($c = 0; $c -lt $groupes.CentresR.Count; $c++) {
        [void]$hexCouleurs.Add((Obtenir-HexDepuisRGB24 $groupes.CentresR[$c] $groupes.CentresG[$c] $groupes.CentresB[$c]))
    }

    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('<?xml version="1.0" encoding="UTF-8"?>')
        # 21/10/2026, retour de Tomyn (confirme avec un vrai .3mf Meshy fourni par lui, qui NE
        # pose PAS ce probleme, compare octet pour octet a ma sortie Tripo) : Bambu Studio
        # n'affichait que les 4 filaments deja presents dans le projet, quel que soit le nombre de
        # couleurs demande. Premiere piste (colorgroup/pid/p1 standard 3MF) fausse - le fichier
        # Meshy n'en contient PAS du tout. La vraie difference : le fichier Meshy declare
        # <metadata name="Application">BambuStudio-02.03.01.00</metadata> - il se fait carrement
        # passer pour un fichier genere par Bambu Studio lui-meme (met m_is_bbl_3mf=true cote
        # Bambu Studio), ce qui fait que project_settings.config (palette filament_colour) EST
        # bien lu et applique. En contrepartie, une fois m_is_bbl_3mf=true, un
        # Metadata/model_settings.config valide devient OBLIGATOIRE (son absence/un parse rate
        # fait echouer le chargement ENTIER - confirme dans le code source reel de Bambu Studio) :
        # on l'ecrit desormais aussi, avec la meme structure que le fichier Meshy fonctionnel.
        [void]$sb.Append('<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:BambuStudio="http://schemas.bambulab.com/package/2021">')
        [void]$sb.Append('<metadata name="Application">BambuStudio-02.03.01.00</metadata>')
        [void]$sb.Append('<metadata name="BambuStudio:3mfVersion">2</metadata>')
        [void]$sb.Append('<metadata name="BambuStudio:MmPaintingVersion">1</metadata>')
        [void]$sb.Append('<resources><object id="1" type="model"><mesh><vertices>')
        # Mise a l'echelle vers $tailleCibleMm (plus grand cote) + recentrage X/Y et pose sur Z=0 -
        # voir le commentaire detaille plus haut sur la normalisation 1x1x1 de Tripo, le champ
        # $numTailleImpression reutilise, et le centrage sur l'origine qui faisait flotter/couper
        # le modele en deux sur le plateau.
        $nSommets = $donnees.VX.Count
        for ($i = 0; $i -lt $nSommets; $i++) {
            $xStr = (($donnees.VX[$i] - $centreX) * $echelle).ToString("0.######", [System.Globalization.CultureInfo]::InvariantCulture)
            $yStr = (($donnees.VY[$i] - $centreY) * $echelle).ToString("0.######", [System.Globalization.CultureInfo]::InvariantCulture)
            $zStr = (($donnees.VZ[$i] - $zMin) * $echelle).ToString("0.######", [System.Globalization.CultureInfo]::InvariantCulture)
            [void]$sb.Append("<vertex x=`"$xStr`" y=`"$yStr`" z=`"$zStr`"/>")
            if ($i % 50000 -eq 0) { Pomper-MessagesUI }
        }
        [void]$sb.Append('</vertices><triangles>')
        $nTriangles = $donnees.T1.Count
        for ($i = 0; $i -lt $nTriangles; $i++) {
            $etatFilament = $groupes.Affectations[$i] + 1
            $hexPeinture = Convertir-EtatFilamentEnPaintColor $etatFilament
            $attrPeinture = if ($hexPeinture) { " paint_color=`"$hexPeinture`"" } else { "" }
            [void]$sb.Append("<triangle v1=`"$($donnees.T1[$i])`" v2=`"$($donnees.T2[$i])`" v3=`"$($donnees.T3[$i])`"$attrPeinture/>")
            if ($i % 50000 -eq 0) { Pomper-MessagesUI }
        }
        [void]$sb.Append('</triangles></mesh></object></resources>')
        # 22/10/2026, bug remonte par Tomyn (capture d'ecran) : meme apres le centrage X/Y sur
        # l'origine (0,0) ci-dessus, le modele flotte a cote du plateau dans Bambu Studio au lieu
        # d'etre dessus - "objets places au-dessus" toujours affiche. Cause : le maillage est bien
        # centre sur (0,0), mais le plateau Bambu (A1 : 256x256mm) a son origine au coin avant-
        # gauche, pas au centre - un objet centre sur (0,0) se retrouve donc a moitie hors du
        # plateau, dans le quadrant negatif. Il manque une translation de l'item vers le centre du
        # plateau (128,128 pour un plateau 256x256). Ajoutee ici via le transform de <item> plutot
        # que de retoucher les sommets : matrice 3mf = 9 valeurs de rotation/echelle (identite) +
        # 3 valeurs de translation (Tx Ty Tz).
        [void]$sb.Append('<build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 128 128 0"/></build>')
        [void]$sb.Append('</model>')
        [System.IO.File]::WriteAllText((Join-Path $dossierTemp "3D/3dmodel.model"), $sb.ToString(), $script:EncodageUtf8SansBOM)

        $contentTypes = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/><Default Extension="config" ContentType="text/xml"/></Types>'
        [System.IO.File]::WriteAllText((Join-Path $dossierTemp "[Content_Types].xml"), $contentTypes, $script:EncodageUtf8SansBOM)

        $rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>'
        [System.IO.File]::WriteAllText((Join-Path $dossierTemp "_rels/.rels"), $rels, $script:EncodageUtf8SansBOM)

        # Metadata/project_settings.config - meme schema qu'un vrai export Bambu Studio (confirme
        # en comparant a un .3mf Meshy fonctionnel fourni par Tomyn), pour que Bambu Studio
        # l'applique reellement (voir commentaire plus haut) ET pour que le Melangeur
        # (Obtenir-CouleursFichier3MF) continue de le lire sans rien changer de son cote.
        $configJson = Construire-ProjectSettingsBambu $hexCouleurs
        [System.IO.File]::WriteAllText((Join-Path $dossierTemp "Metadata/project_settings.config"), $configJson, $script:EncodageUtf8SansBOM)

        # Obligatoire des que le fichier se declare "BambuStudio-..." (voir commentaire plus haut) -
        # sans ca, Bambu Studio refuse de charger le fichier EN ENTIER ("Archive does not contain a
        # valid model config"), confirme dans son code source reel.
        $modelSettingsXml = Construire-ModelSettingsBambu $donnees.T1.Count
        [System.IO.File]::WriteAllText((Join-Path $dossierTemp "Metadata/model_settings.config"), $modelSettingsXml, $script:EncodageUtf8SansBOM)

        if (Test-Path -LiteralPath $CheminSortie3mf) { Remove-Item -LiteralPath $CheminSortie3mf -Force }
        # 21/10/2026 : CreateFromDirectory nomme chaque entree du zip avec le separateur de
        # chemin de l'OS - sous Windows ca donne des ANTISLASHS ("3D\3dmodel.model"), ce qui
        # viole le format OPC/.3mf (qui exige des slashs "/" dans les chemins internes) et
        # empeche Bambu Studio de retrouver "3D/3dmodel.model" -> "le chargement du fichier
        # modele a echoue" / "le fichier ne contient pas de donnees geometriques". Bug confirme
        # en inspectant au niveau des octets un vrai .3mf genere par Tomyn sous Windows (les
        # entrees s'appelaient bien "3D\3dmodel.model" etc.) - invisible depuis mon
        # environnement de test Linux, ou CreateFromDirectory utilise deja des slashs par
        # defaut. On construit donc le zip a la main pour forcer des slashs "/" partout, quel
        # que soit l'OS qui execute ce script.
        $fluxZip = [System.IO.File]::Open($CheminSortie3mf, [System.IO.FileMode]::Create)
        try {
            $archiveZip = New-Object System.IO.Compression.ZipArchive($fluxZip, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $longueurRacine = $dossierTemp.Length
                # -Force indispensable : ".rels" commence par un point et est marque "cache"
                # (attribut Hidden) par .NET - sans -Force, Get-ChildItem l'ignore silencieusement
                # et le .3mf se retrouve sans _rels/.rels, un autre rejet garanti par Bambu Studio.
                foreach ($fichierAEmpaqueter in (Get-ChildItem -Path $dossierTemp -Recurse -File -Force)) {
                    $cheminRelatif = $fichierAEmpaqueter.FullName.Substring($longueurRacine).TrimStart('\', '/') -replace '\\', '/'
                    $entreeZip = $archiveZip.CreateEntry($cheminRelatif, [System.IO.Compression.CompressionLevel]::Optimal)
                    $fluxEntree = $entreeZip.Open()
                    try {
                        $fluxSource = [System.IO.File]::OpenRead($fichierAEmpaqueter.FullName)
                        try { $fluxSource.CopyTo($fluxEntree) } finally { $fluxSource.Dispose() }
                    } finally { $fluxEntree.Dispose() }
                }
            } finally { $archiveZip.Dispose() }
        } finally { $fluxZip.Dispose() }
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]@{
        NombreSommets   = $donnees.VX.Count
        NombreTriangles = $donnees.T1.Count
        NombreCouleurs  = $groupes.CentresR.Count
        Couleurs        = $hexCouleurs.ToArray()
    }
}
# =====================================================================================

function Coloriser-UnFichierTripo($FichierStl, $Prompt, $CleApi, $DossierSortie, $AvecHorodatage, $GalerieCible, $SuffixeFournisseur = "", [int]$TargetPolycount = 30000, [double]$TailleImpressionMm = 0) {
    Ecrire-Journal ""
    Ecrire-Journal "=== $($FichierStl.Name) (via Tripo) ==="

    # 20/10/2026, Tomyn : "pour l'image ca sera bien d'avoir Tripo aussi" - image-to-model Tripo
    # ajoute plus bas (voir Lancer-ImageModelTripo). Seul le plafond de taille reste different
    # entre image et modele 3D (voir juste en dessous), meme principe que cote Meshy
    # (Coloriser-UnFichier : le controle de taille en Mo ne s'applique qu'aux modeles 3D, pas aux
    # images, qui n'ont jamais eu ce genre de limite documentee de notre cote).
    $estUneImage = $FichierStl.Extension.ToLower() -in $EXTENSIONS_IMAGES

    if (-not $estUneImage) {
        # 20/10/2026 : plafond remonte de 50 a 150 Mo, d'apres la vraie doc officielle Tripo
        # (developers.tripo3d.ai/fr/docs/models-import) : "input" (le file_token issu de l'upload)
        # accepte un fichier jusqu'a 150 Mo - l'ancien seuil de 50 Mo n'avait jamais ete confirme
        # nulle part, c'etait juste une marge de securite arbitraire. Concretement utile pour les
        # .3mf tres denses convertis en .stl (ex. 149,7 Mo / 3,1M triangles observe chez Tomyn le
        # 20/10/2026) : ca passe chez Tripo (150 Mo) meme si ca depasse le plafond "data: URI" de
        # Meshy (100 Mo).
        $tailleMo = $FichierStl.Length / 1MB
        if ($tailleMo -gt 150) {
            throw "fichier de $([math]::Round($tailleMo,1)) Mo, limite Tripo (import) = 150 Mo - non envoye"
        }
    }

    $entetes = @{ Authorization = "Bearer $CleApi" }
    $extension = $FichierStl.Extension.TrimStart(".").ToLower()

    # --- Etape 1 : reserver une URL d'upload ---
    Ecrire-Journal "  Reservation d'un upload (Tripo)..."
    $corps = @{ format = $extension } | ConvertTo-Json
    $reponsePresign = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/files/presign" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30 } "Reservation upload Tripo"
    $donneesPresign = if ($reponsePresign.data) { $reponsePresign.data } else { $reponsePresign }
    # "upload_url" est accepte comme alias de "presigned_url" selon la doc trouvee - on essaie
    # les deux noms plutot que de ne tenter qu'un seul et echouer silencieusement si c'est l'autre.
    $urlPresignee = if ($donneesPresign.presigned_url) { $donneesPresign.presigned_url } else { $donneesPresign.upload_url }
    $jetonFichier = $donneesPresign.file_token

    # Verification immediate plutot que de tenter un PUT voue a l'echec (ou pire, a un blocage
    # silencieux) sur une URL vide ou invalide - c'est tres probablement ce qui causait le
    # blocage de plusieurs minutes observe en test reel : le nom du champ devine ne correspondait
    # probablement pas a la vraie reponse Tripo.
    if (-not $urlPresignee) {
        $reponseBrute = $reponsePresign | ConvertTo-Json -Depth 5 -Compress
        throw "reponse de reservation d'upload sans URL exploitable - reponse brute recue : $reponseBrute"
    }

    # --- Etape 2 : uploader le fichier brut sur cette URL (pas d'en-tete Authorization ici,
    # c'est un stockage externe, pas l'API Tripo elle-meme) ---
    # Expect100Continue desactive : probleme classique et documente de PowerShell face a une URL
    # S3 presignee - sans cette ligne, .NET envoie un en-tete "Expect: 100-continue" que beaucoup
    # d'URL S3 signees gerent mal, ce qui peut bloquer la connexion indefiniment (bien au-dela du
    # -TimeoutSec demande) plutot que d'echouer proprement. Tres probablement la vraie cause du
    # blocage de plusieurs minutes observe en test reel, vu que l'URL elle-meme est correcte.
    [System.Net.ServicePointManager]::Expect100Continue = $false

    Ecrire-Journal "  Envoi du fichier vers : $urlPresignee"
    $octets = [System.IO.File]::ReadAllBytes($FichierStl.FullName)
    # System.Net.WebClient plutot qu'Invoke-WebRequest : confirme en test reel (curl.exe reussit
    # sans probleme sur la meme URL, donc le souci etait bien cote PowerShell) - Invoke-WebRequest
    # peut mal gerer l'envoi d'un tableau d'octets vers une URL S3 signee (bascule parfois sur un
    # envoi fragmente que la signature S3 n'accepte pas), WebClient.UploadData envoie le Content-
    # Length exact sans ce probleme, comme le fait curl.
    try {
        Invoquer-AvecReessaiReseau {
            $clientWeb = New-Object System.Net.WebClient
            $clientWeb.Headers.Add("Content-Type", "application/octet-stream")
            $clientWeb.UploadData($urlPresignee, "PUT", $octets) | Out-Null
            $clientWeb.Dispose()
        } "Envoi du fichier (Tripo)"
    } catch {
        throw "echec de l'envoi du fichier vers l'URL presignee : $_"
    }
    Ecrire-Journal "  Fichier envoye."

    # --- Etape 2bis : image, maillage volumineux, ou import normal ---
    # 20/10/2026 : trois chemins possibles avant la texturation.
    # - Image (Tomyn : "pour l'image ca sera bien d'avoir Tripo aussi") : Image to 3D Tripo, qui
    #   saute import_model (son task_id est deja une reference valide). Sans prompt, elle texture
    #   elle-meme directement depuis la photo et $sauterTexturation saute l'etape Texture separee -
    #   avec prompt, geometrie seule (texture=$false) puis Texture classique juste apres avec CE
    #   prompt (meme logique que cote Meshy, voir Lancer-Image3D).
    # - Maillage volumineux (parite Meshy, voir $SEUIL_TRIANGLES_REMESH_AUTO et Lancer-Remesh) :
    #   Retopology (mesh/decimate) a la place de l'import_model habituel, meme principe (saute
    #   import_model, son task_id sert directement a la texturation).
    # - Sinon : import_model habituel, inchange.
    # Nombre de triangles non pertinent pour une image (rien a mesurer avant generation) - laisse a
    # $null dans ce cas, condition suivante jamais evaluee grace au court-circuit de "elseif".
    $nbTriangles = if ($estUneImage) { $null } else { Obtenir-NombreTriangles $FichierStl.FullName }
    $idModeleSource = $null
    $tacheADecimee = $null
    $creditsImport = 0
    $sauterTexturation = $false

    if ($estUneImage) {
        $avecPrompt = -not [string]::IsNullOrWhiteSpace($Prompt)
        $tacheImageModel = Lancer-ImageModelTripo $entetes $jetonFichier (-not $avecPrompt)
        $idModeleSource = $tacheImageModel.task_id
        $creditsImport = [double]($tacheImageModel.credits_consumed)
        $sauterTexturation = -not $avecPrompt
    } elseif ($nbTriangles -ne $null -and $nbTriangles -gt $SEUIL_TRIANGLES_REMESH_AUTO) {
        $tacheADecimee = Lancer-DecimateTripo $entetes $jetonFichier $TargetPolycount
        $idModeleSource = $tacheADecimee.task_id
        $creditsImport = [double]($tacheADecimee.credits_consumed)
    } else {
        # --- Etape 3 : import du modele uploade ---
        # Etape decouverte a posteriori, absente des premieres versions : la doc officielle
        # (docs.tripo3d.ai/model-generation/import-model.html) precise qu'un fichier uploade doit
        # d'abord passer par une tache "import_model" avant de pouvoir etre texture - confirme aussi
        # en conditions reelles via l'historique du tableau de bord Tripo : chaque texturation en
        # echec ("Internal processing error") etait precedee d'une tache import_model en succes que
        # notre code ne reutilisait jamais, envoyant directement le jeton de fichier brut a la
        # texturation au lieu du resultat de cet import. Tres probablement la vraie cause des echecs
        # systematiques observes jusqu'ici (meme sur un simple cube de test).
        Ecrire-Journal "  Import du modele (Tripo)..."
        # 20/10/2026 : "input" = $jetonFichier ajoute EN PLUS (jamais retire ce qui marche) - la doc
        # officielle actuelle (developers.tripo3d.ai/fr/docs/models-import) ne documente plus QUE ce
        # champ unique "input" (file_token ou URL), sans "type"/"file.file_token". Vu le risque de
        # casser un appel qui fonctionne reellement (succes confirmes avec les champs actuels), pas de
        # suppression a l'aveugle sur la seule foi de la doc - juste un ajout defensif : un champ JSON
        # en plus, inconnu de l'API, est normalement ignore sans consequence, donc cet envoi reste
        # compatible que l'API lise encore "type"/"file.file_token" ou soit passee a "input" entre
        # temps.
        $corps = @{ type = "import_model"; file = @{ file_token = $jetonFichier }; input = $jetonFichier } | ConvertTo-Json
        $reponseImport = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/models/import" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30 } "Import Tripo"
        $idImportReponse = if ($reponseImport.data) { $reponseImport.data } else { $reponseImport }
        $idModeleSource = $idImportReponse.task_id

        $tacheImport = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idModeleSource" $entetes "Import"
        Ecrire-Journal "  Import termine."
        # Corrige le 07/10/2026 : contrairement a ce qu'on pensait ("0 observe partout dans le
        # tableau de bord"), Tomyn a confirme que l'import N'EST PAS gratuit (5 credits observes) -
        # ce chiffre n'etait simplement jamais ajoute au total renvoye jusqu'ici, qui sous-comptait
        # donc le cout reel de chaque generation Tripo de 5 credits.
        $creditsImport = [double]($tacheImport.credits_consumed)
    }

    # --- Etape 4 : texturation (a partir du resultat de l'import, pas du jeton de fichier brut) ---
    # Champs corriges d'apres la vraie doc officielle (platform.tripo3d.ai/docs/texture, trouvee
    # par Tomyn) : le champ s'appelle "original_model_task_id", pas "input" comme envoye jusqu'ici
    # depuis le debut - "input" etait silencieusement ignore par leur API, qui tournait alors sans
    # jamais avoir de vraie reference de modele, d'ou l'echec systematique en cours de route quel
    # que soit le fichier. Le prompt texte est imbrique dans "texture_prompt.text", pas un champ
    # "prompt" a plat.
    # 20/10/2026 : "model" = "v3.5-20260815" ajoute - confirme reel dans la doc officielle actuelle
    # (developers.tripo3d.ai/fr/docs/models-texture), modele de texture plus recent que le defaut
    # "v3.0-20250812" (aucun surcout en credits documente pour ce champ a lui seul, contrairement
    # a "texture_quality=fast/detailed/extreme" qui eux changent le cout - on ne touche pas a
    # "texture_quality", laisse a son defaut "standard").
    # "input" = $idModeleSource ajoute EN PLUS du champ actuel "original_model_task_id" - meme logique
    # defensive que pour l'import ci-dessus (la doc actuelle ne documente plus que "input", mais
    # "original_model_task_id" est confirme fonctionner reellement - on garde les deux plutot que
    # de parier sur lequel l'API lit vraiment aujourd'hui). Attention : le 07/10/2026, "input" avait
    # ete teste et trouve "silencieusement ignore" sur CET appel precisement - donc son ajout ici
    # est surtout une securite pour le jour ou l'API bascule vraiment, pas une garantie d'effet
    # immediat.
    # $sauterTexturation : cas d'une image sans prompt (voir Etape 2bis plus haut) - Image to 3D
    # Tripo a deja texture directement depuis la photo (texture=$true a cet appel-la), inutile de
    # repayer une texturation separate sans rien de plus a lui dire.
    $creditsTexture = 0
    if ($sauterTexturation) {
        Ecrire-Journal "  Texturation deja faite par Image to 3D (pas de prompt fourni) - etape Texture sautee."
        $idTexture = $idModeleSource
    } else {
        Ecrire-Journal "  Envoi a l'API Texture (Tripo)..."
        # $idModeleSource : resultat de l'import habituel, de la simplification Retopology (maillage
        # volumineux), ou de l'Image to 3D (geometrie seule, texture=$false) - les trois sont un
        # task_id Tripo valide.
        # 22/10/2026 : "pbr" ajoute explicitement a $false - ce champ n'etait pas envoye ici avant,
        # ce qui laissait l'API appliquer SON propre defaut (potentiellement $true, comme confirme
        # sur /generation/image-to-model - voir le commentaire dans Lancer-ImageModelTripo pour le
        # detail de l'hypothese PBR/couleur-par-sommet). Meme precaution ici par coherence/securite,
        # pas confirmee non plus avec une vraie generation.
        $corps = @{ original_model_task_id = $idModeleSource; input = $idModeleSource; texture_prompt = @{ text = $Prompt }; model = "v3.5-20260815"; pbr = $false } | ConvertTo-Json
        $reponseTexture = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/models/texture" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30 } "Texture Tripo"
        $idTextureReponse = if ($reponseTexture.data) { $reponseTexture.data } else { $reponseTexture }
        $idTexture = $idTextureReponse.task_id

        $tacheTexture = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idTexture" $entetes "Texturation"
        Ecrire-Journal "  Texturation terminee."
        $creditsTexture = [double]($tacheTexture.credits_consumed)
    }

    # --- Etape 5 : conversion en OBJ colore par sommet (pas en 3MF) ---
    # Changement du 2026-10-07 : "export_vertex_colors" est documente par Tripo comme valide
    # UNIQUEMENT pour les formats OBJ et GLTF (developers.tripo3d.com/en/docs/models-convert) -
    # demande avec format=3MF comme avant, ce parametre etait silencieusement ignore, d'ou les
    # 3MF recus avec une palette de 4 couleurs ajoutee mais jamais appliquee a la geometrie
    # (confirme par Tomyn : aucune texture visible dans un lecteur .3mf). Bambu Studio sachant lire
    # un OBJ colore par sommet et proposer ses couleurs dans l'AMS, on demande directement ce
    # format-la a la place.
    Ecrire-Journal "  Envoi a l'API Convert (Tripo, format OBJ)..."
    $corps = @{ input = $idTexture; format = "OBJ"; export_vertex_colors = $true } | ConvertTo-Json
    $reponseConvert = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/models/convert" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30 } "Convert Tripo"
    $idConvertReponse = if ($reponseConvert.data) { $reponseConvert.data } else { $reponseConvert }
    $idConvert = $idConvertReponse.task_id

    $tacheConvert = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idConvert" $entetes "Conversion OBJ"
    Ecrire-Journal "  Conversion terminee."

    # Confirme par une vraie reponse Tripo complete (premier succes de bout en bout) : le champ
    # s'appelle "output.model_url", pas "output.model" comme devine au depart.
    $urlSortie = $tacheConvert.output.model_url
    if (-not $urlSortie) {
        $reponseBrute = $tacheConvert | ConvertTo-Json -Depth 6 -Compress
        throw "reponse de conversion sans URL de modele exploitable - reponse brute recue : $reponseBrute"
    }
    # "credits_consumed" confirme present dans la meme reponse (5.00 observe sur l'etape de
    # conversion) - extrait ici plutot que de toujours renvoyer 0 comme avant.
    $creditsConvert = [double]($tacheConvert.credits_consumed)
    # Texture confirmee a 10 credits par Tomyn le 07/10/2026 (valeur reelle lue ici, pas codee en
    # dur). 20/10/2026 : $creditsTexture est maintenant calcule plus haut, directement dans la
    # branche Texture (0 si $sauterTexturation, sinon la vraie valeur) - plus de reaffectation ici.

    # Contrairement au 3MF (un seul fichier), l'export OBJ de Tripo est livre sous forme de ZIP
    # (maillage + materiau .mtl + images de texture) - documente par le SDK/doc tiers, pas un
    # fichier unique a ecrire directement comme avant. On extrait tout dans un SOUS-DOSSIER dedie
    # (plutot que de deposer les fichiers directement dans $DossierSortie) pour eviter toute
    # collision de nom entre plusieurs fichiers du meme lot : Tripo nomme souvent son .obj/.mtl de
    # facon generique (ex. "model.obj"), qui serait alors identique pour chaque fichier traite.
    $suffixe = $SuffixeFournisseur + $(if ($AvecHorodatage) { "_colorise_" + (Get-Date -Format 'yyyyMMdd_HHmmss') } else { "_colorise" })
    $dossierResultat = Join-Path $DossierSortie ($FichierStl.BaseName + $suffixe)
    New-Item -ItemType Directory -Force -Path $dossierResultat | Out-Null

    $cheminZip = Join-Path ([System.IO.Path]::GetTempPath()) ("tripo_" + [System.Guid]::NewGuid().ToString() + ".zip")
    Invoquer-AvecReessaiReseau { Invoke-WebRequest -Uri $urlSortie -OutFile $cheminZip -TimeoutSec 60 } "Telechargement du resultat (Tripo)" | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($cheminZip, $dossierResultat)
    } catch {
        throw "echec de l'extraction du ZIP renvoye par Tripo (format OBJ) : $_"
    } finally {
        Remove-Item $cheminZip -Force -ErrorAction SilentlyContinue
    }

    # Le .obj peut se trouver directement a la racine du ZIP ou dans un sous-dossier selon la
    # structure exacte que Tripo utilise (jamais documentee avec certitude) - recherche recursive
    # plutot que de supposer un chemin fixe.
    $fichierObj = Get-ChildItem -Path $dossierResultat -Filter "*.obj" -Recurse | Select-Object -First 1
    if (-not $fichierObj) {
        throw "le ZIP recu de Tripo ne contient aucun fichier .obj (contenu extrait dans $dossierResultat)"
    }

    # 21/10/2026, demande explicite de Tomyn : convertir automatiquement l'OBJ colore par
    # sommet en .3mf peint, directement a cote de l'OBJ (pas un outil/bouton separe). En
    # defense en profondeur : un echec de conversion (OBJ malforme, cas non prevu) ne doit
    # jamais faire perdre le resultat Tripo deja obtenu - l'OBJ reste utilisable tel quel,
    # on journalise juste l'echec sans faire planter tout le traitement du fichier.
    $cheminSortie3mfReussi = $null
    try {
        $cheminSortie3mf = Join-Path $dossierResultat ($fichierObj.BaseName + ".3mf")
        # 21/10/2026 : utilise le reglage "Nombre de couleurs" de l'interface (deja utilise pour
        # Meshy, voir $numCouleurs plus haut dans le script) au lieu d'un 8 fixe code en dur - pas
        # de raison que ce reglage n'influence pas aussi le regroupement cote Tripo.
        $infoConversion = Convertir-ObjColoreVers3mfPeint $fichierObj.FullName $cheminSortie3mf ([int]$numCouleurs.Value) $TailleImpressionMm
        Ecrire-Journal "  -> .3mf peint genere automatiquement : $($infoConversion.NombreCouleurs) couleur(s), $($infoConversion.NombreTriangles) triangles ($cheminSortie3mf)"
        $cheminSortie3mfReussi = $cheminSortie3mf
    } catch {
        Ecrire-Journal "  -> ECHEC de la conversion automatique en .3mf peint (l'OBJ colore reste disponible) : $_"
    }

    # 22/10/2026, demande explicite de Tomyn : l'OBJ laisse a cote du .3mf dans le dossier de
    # resultat posait un vrai probleme d'usage, pas juste cosmetique - notre galerie generait une
    # miniature rendue (donc "parlante") pour l'OBJ mais pas pour le .3mf (format .3mf trop
    # complexe pour notre rendu maison, voir Ajouter-Vignette/Obtenir-Miniature), et le message de
    # journal d'alors disait meme explicitement d'ouvrir l'OBJ dans Bambu Studio. Resultat : un
    # utilisateur lambda ouvrait naturellement l'OBJ (celui qui "se voit"), tombait sur
    # l'assistant d'import OBJ natif de Bambu Studio - dont la detection du nombre de couleurs
    # s'est averee peu fiable sur les fichiers Tripo (enquete statistique approfondie menee en
    # amont, aucun levier trouve cote fichier - tres probablement un comportement interne/ferme de
    # Bambu Studio, hors de portee d'un correctif ici) - au lieu du .3mf, deja correctement
    # colorise et pose, genere juste a cote. Plutot que d'essayer encore de corriger le
    # comportement de l'assistant OBJ de Bambu Studio (deja explore sans succes), on supprime
    # purement l'ambiguite : l'OBJ intermediaire est efface des que la conversion en .3mf reussit,
    # il ne reste plus qu'un seul fichier dans le dossier de resultat. L'OBJ n'est conserve que si
    # la conversion a echoue (seul resultat exploitable dans ce cas, comportement inchange).
    if ($cheminSortie3mfReussi) {
        try { Remove-Item -Path $fichierObj.FullName -Force -ErrorAction Stop } catch {
            Ecrire-Journal "  -> Impossible de supprimer l'OBJ intermediaire ($($fichierObj.Name)) : $_"
        }
        Ecrire-Journal "  -> Enregistre : $dossierResultat (ouvrir $([System.IO.Path]::GetFileName($cheminSortie3mfReussi)) dans Bambu Studio)"
    } else {
        Ecrire-Journal "  -> Enregistre : $dossierResultat (ouvrir le fichier $($fichierObj.Name) dans Bambu Studio)"
    }

    # 13/10/2026 : titre + description prets a coller dans le formulaire de depot MakerWorld (voir
    # Generer-DescriptionMakerWorld) - fichier texte a cote du resultat, et bouton "Copier
    # description" sur la vignette correspondante.
    $descriptionGeneree = Generer-DescriptionMakerWorld $FichierStl.BaseName $Prompt
    try { Set-Content -Path (Join-Path $dossierResultat "description_makerworld.txt") -Value $descriptionGeneree.Texte -Encoding UTF8 } catch { }

    # 22/10/2026 : une seule vignette desormais - celle du .3mf (deliverable final) s'il a ete
    # genere, sinon celle de l'OBJ (seul resultat restant, cas d'echec de conversion ci-dessus).
    # Avant, les DEUX vignettes etaient ajoutees systematiquement (OBJ toujours visible, .3mf en
    # plus si reussi) - c'est justement cette double presence qui laissait l'OBJ trainer comme
    # option visible/cliquable a cote du .3mf.
    if ($cheminSortie3mfReussi) {
        Ajouter-Vignette $GalerieCible $cheminSortie3mfReussi $null -texteDescription $descriptionGeneree.Texte
    } else {
        Ajouter-Vignette $GalerieCible $fichierObj.FullName $null -texteDescription $descriptionGeneree.Texte
    }
    [System.Windows.Forms.Application]::DoEvents()

    # Credits reellement consommes sur les TROIS etapes facturees : import (5), texturation (10)
    # et conversion (confirmes par Tomyn le 07/10/2026 - l'import n'est pas gratuit, contrairement
    # a ce qui etait suppose avant).
    $creditsTotal = $creditsImport + $creditsTexture + $creditsConvert
    $cheminHistorique = if ($cheminSortie3mfReussi) { $cheminSortie3mfReussi } else { $fichierObj.FullName }
    Enregistrer-HistoriqueFichier $FichierStl.Name "Tripo" $creditsTotal $cheminHistorique
    return $creditsTotal
}

function Lancer-Image3D($FichierImage, $Entetes, [int]$TargetPolycount = 30000, [bool]$SmartTopology = $false, [string]$GeometryResolution = "") {
    # Image -> maillage (ajoute le 08/10/2026) : "Image to 3D" de Meshy, maillage seul
    # (should_texture=false) - la texture est refaite juste apres par la Retexture habituelle avec
    # LE PROMPT choisi par l'utilisateur, pas celle (generique) que ferait Image to 3D elle-meme.
    # Payer la texturation deux fois (une ici, une a la Retexture) n'aurait aucun sens.
    $extension = $FichierImage.Extension.ToLower()
    # 20/10/2026 : ajout de .webp (voir $EXTENSIONS_IMAGES) - mime correct obligatoire, sinon on
    # enverrait un .webp etiquete "image/png" a l'API.
    $mime = switch ($extension) {
        { $_ -in @(".jpg", ".jpeg") } { "image/jpeg" }
        ".webp" { "image/webp" }
        default { "image/png" }
    }
    $octets = [System.IO.File]::ReadAllBytes($FichierImage.FullName)
    $base64 = [Convert]::ToBase64String($octets)
    $dataUri = "data:$mime;base64,$base64"

    # 13/10/2026, Tomyn : "ca sort un truc tres low poly, sur le site Meshy tu peux dire combien
    # de triangles tu veux" - "target_polycount" existe bien dans l'API, mais Meshy l'ignore si
    # "should_remesh" n'est pas explicitement a true (false par defaut pour Meshy 6/7, donc AUCUN
    # remaillage avant ce correctif - d'ou le maillage brut, parfois clairseme, de la generation).
    $corps = @{ image_url = $dataUri; should_texture = $false; should_remesh = $true; target_polycount = $TargetPolycount }

    # 20/10/2026, Tomyn : "Smart Topology" - confirme reel dans le changelog officiel Meshy
    # (model_type "smart-topology" + ai_model "meshy-t2.5", ajoute le 15/10/2026). Plage de
    # target_polycount plus etroite (100-30000) que le mode normal (100-300000) : on ecrete la
    # valeur demandee plutot que de risquer un 400 de l'API, et on previent dans le journal pour
    # que ce ne soit pas une surprise silencieuse.
    if ($SmartTopology) {
        if ($TargetPolycount -gt 30000) {
            Ecrire-Journal "  Smart Topology : $TargetPolycount triangle(s) demandes, limite a 30000 pour ce mode."
            $corps.target_polycount = 30000
        }
        $corps.model_type = "smart-topology"
        $corps.ai_model = "meshy-t2.5"
    }

    # 20/10/2026, Tomyn : "geometry_resolution" (standard/2k/4k), ajoute par Meshy le 18/09/2026 -
    # voir $menuGeometrieResolution. Remplace l'ancien "ultra_mode" qu'on n'a jamais utilise.
    # CORRECTIF du 20/10/2026 (usage reel sur la version Android, meme pipeline) : l'hypothese
    # "le 4k necessite meshy-7.1, deja notre defaut tant qu'on ne fixe pas ai_model ailleurs"
    # etait FAUSSE - erreur reelle recue : "geometry_resolution '4k' requires ai_model
    # 'meshy-7.1'". L'API ne defaut PAS silencieusement dessus, il faut l'envoyer explicitement.
    # On l'envoie pour "2k" aussi par prudence (meme famille de parametre, jamais teste seul).
    # CORRECTIF du 21/10/2026 (usage reel, meme pipeline) : Smart Topology ET geometry_resolution
    # coches en meme temps donnaient ENCORE HTTP 400, meme apres le correctif ci-dessus, car les
    # deux exigent chacun un ai_model incompatible avec l'autre ("meshy-t2.5" vs "meshy-7.1"),
    # confirme sur la documentation officielle Meshy - ce n'est pas un oubli, c'est une combinaison
    # invalide cote API. Smart Topology est prioritaire : geometry_resolution est simplement ignore
    # si Smart Topology est actif, avec un mot dans le journal plutot qu'un echec silencieux.
    if ($SmartTopology -and $GeometryResolution -in @("2k", "4k")) {
        Ecrire-Journal "  Smart Topology et la resolution $GeometryResolution sont incompatibles cote Meshy (modeles differents) - Smart Topology est prioritaire, la resolution choisie est ignoree."
    } elseif ($GeometryResolution -in @("2k", "4k")) {
        $corps.geometry_resolution = $GeometryResolution
        $corps.ai_model = "meshy-7.1"
    }

    Ecrire-Journal "  Image detectee - envoi a l'API Image to 3D (maillage seul, $($corps.target_polycount) triangle(s) vises$(if ($SmartTopology) { ', Smart Topology' })$(if ($corps.geometry_resolution) { ", resolution $($corps.geometry_resolution)" }))..."
    $corps = $corps | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/image-to-3d" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps } "Image to 3D"
    $tache = Attendre-Tache "$BaseUrl/image-to-3d/$($reponse.result)" $Entetes "Image to 3D"
    Ecrire-Journal "  Maillage genere depuis l'image ($($tache.consumed_credits) credits)."
    return $tache
}

# Simplifie un .stl trop lourd via l'API Remesh de Meshy, AVANT la Retexture (15/10/2026, voir
# $SEUIL_TRIANGLES_REMESH_AUTO plus haut) - meme principe d'enchainement que Lancer-Image3D
# ci-dessus (input_task_id de cette tache reutilise comme point de depart de la Retexture qui
# suit, au lieu de renvoyer le fichier d'origine tel quel).
function Lancer-Remesh($FichierStl, $Entetes, [int]$TargetPolycount, [int]$NbTrianglesDepart) {
    Ecrire-Journal "  Maillage volumineux ($NbTrianglesDepart triangles) - simplification (Remesh) avant Retexture, cible ~$TargetPolycount triangle(s)..."
    $octets = [System.IO.File]::ReadAllBytes($FichierStl.FullName)
    $base64 = [Convert]::ToBase64String($octets)
    $dataUri = "data:application/octet-stream;base64,$base64"
    # 20/10/2026 : "glb" ajoute a cote de "stl" - necessaire si Tomyn active la reparation des
    # parois (voir Lancer-ReparationImprimabilite plus bas), qui exige que la tache source (ici
    # celle de Remesh, chainee via input_task_id) possede un asset .glb. Ne change rien d'autre :
    # on continue a chainer par input_task_id, pas par le contenu de model_urls.
    $corps = @{ model_url = $dataUri; target_polycount = $TargetPolycount; target_formats = @("stl", "glb") } | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/remesh" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps } "Remesh"
    $tache = Attendre-Tache "$BaseUrl/remesh/$($reponse.result)" $Entetes "Remesh"
    Ecrire-Journal "  Maillage simplifie ($($tache.consumed_credits) credits) - Retexture va repartir de ce resultat."
    return $tache
}

# 20/10/2026, Tomyn ("OK pour moi" sur l'idee suggeree juste apres l'ajout de la reparation) :
# "Analyze Printability" de Meshy - meme diagnostic que Repair (parois trop fines, etancheite,
# trous, faces degenerees) mais GRATUIT (0 credit, confirme par la doc : "This endpoint is free")
# et NE MODIFIE RIEN au maillage. Sert maintenant de filtre avant de payer la Reparation (voir
# Reparer-ParoisSiNecessaire plus bas) : pas la peine de depenser 10 credits sur une piece qui
# n'a aucun probleme de parois.
function Lancer-AnalyseImprimabilite($Entetes, [string]$IdTacheSource, [string]$PrinterType = "fdm", $TailleImpressionMm = $null) {
    Ecrire-Journal "  Analyse de l'imprimabilite (gratuit, imprimante $PrinterType)..."
    $corpsAnalyse = @{ input_task_id = $IdTacheSource; printer_type = $PrinterType }
    # 20/10/2026 : "intended_print_longest_side_mm" (voir $numTailleImpression) - seulement si
    # renseigne par Tomyn (1-1000 mm documente), sinon on ne l'envoie pas du tout et Meshy applique
    # son propre defaut (150 mm pour une tache chainee par input_task_id).
    if ($TailleImpressionMm -ne $null -and $TailleImpressionMm -gt 0) {
        $corpsAnalyse.intended_print_longest_side_mm = $TailleImpressionMm
    }
    $corps = $corpsAnalyse | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/print/analyze" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps } "Analyse imprimabilite"
    $tache = Attendre-Tache "$BaseUrl/print/analyze/$($reponse.result)" $Entetes "Analyse imprimabilite"
    $diag = $tache.printability
    if ($diag -ne $null) {
        # Infos de sante du maillage toujours loggees (gratuit), meme quand les parois sont saines -
        # utile a Tomyn independamment de la reparation (etancheite, trous, faces degenerees).
        if ($diag.metrics -ne $null) {
            $m = $diag.metrics
            $etat = if ($m.is_watertight) { "etanche" } else { "NON etanche" }
            Ecrire-Journal "  Diagnostic maillage : $etat, $($m.holes) trou(s), $($m.non_manifold_edges) arete(s) non-manifold, $($m.degenerate_faces) face(s) degeneree(s)."
        }
        if ($diag.thin_walls -ne $null -and $diag.thin_walls.has_thin_walls) {
            $ratio = if ($diag.thin_walls.thin_area_ratio -ne $null) { [math]::Round($diag.thin_walls.thin_area_ratio * 100, 1) } else { "?" }
            Ecrire-Journal "  Parois trop fines detectees ($ratio% de la surface) - reparation (+10 credits) lancee."
        } else {
            Ecrire-Journal "  Parois deja assez epaisses pour $PrinterType - reparation non necessaire, 0 credit supplementaire."
        }
    }
    return $tache
}

# Orchestre Analyze (gratuit) puis Repair (10 credits, seulement si necessaire) - c'est cette
# fonction qu'appelle Coloriser-UnFichier, plus Lancer-ReparationImprimabilite directement.
# Retourne $null si aucune reparation n'a ete necessaire (l'appelant garde alors la tache source
# d'origine comme point de depart pour la Retexture), ou la tache de reparation sinon.
function Reparer-ParoisSiNecessaire($Entetes, [string]$IdTacheSource, [string]$PrinterType = "fdm", $TailleImpressionMm = $null) {
    $tacheAnalyse = Lancer-AnalyseImprimabilite $Entetes $IdTacheSource $PrinterType $TailleImpressionMm
    $besoinReparation = $tacheAnalyse.printability -ne $null -and $tacheAnalyse.printability.thin_walls -ne $null -and $tacheAnalyse.printability.thin_walls.has_thin_walls
    if (-not $besoinReparation) {
        return $null
    }
    # Meme taille d'impression passee a la Reparation qu'a l'Analyse qui l'a decidee - sinon le
    # seuil utilise par Repair ne correspondrait pas a celui qui a determine qu'elle etait necessaire.
    return Lancer-ReparationImprimabilite $Entetes $IdTacheSource $PrinterType $TailleImpressionMm
}

# 20/10/2026, Tomyn (apres discussion sur les pistes du changelog Meshy, celle-ci jugee utile
# contrairement aux trois autres) : "Repair Printability" de Meshy - epaissit automatiquement les
# parois plus fines que le minimum imprimable pour le type d'imprimante choisi (FDM = 1.0 mm,
# documente), AVANT la Retexture (la texture existante est supprimee par cette reparation - d'ou
# le besoin de la lancer sur le maillage NU, puis de retexturer le resultat juste apres, jamais
# apres coup). Chaine par input_task_id comme Lancer-Image3D/Lancer-Remesh : $IdTacheSource doit
# etre une tache Meshy existante (Image to 3D ou Remesh) possedant un asset .glb - pas un nouvel
# upload, Meshy reutilise directement son propre fichier deja heberge. N'est plus appelee
# directement par Coloriser-UnFichier depuis l'ajout de l'Analyze gratuit ci-dessus (voir
# Reparer-ParoisSiNecessaire) - conservee telle quelle, c'est elle qui fait le travail reel.
function Lancer-ReparationImprimabilite($Entetes, [string]$IdTacheSource, [string]$PrinterType = "fdm", $TailleImpressionMm = $null) {
    Ecrire-Journal "  Verification/reparation de l'epaisseur des parois (imprimante $PrinterType) avant Retexture..."
    $corpsReparation = @{ input_task_id = $IdTacheSource; printer_type = $PrinterType }
    if ($TailleImpressionMm -ne $null -and $TailleImpressionMm -gt 0) {
        $corpsReparation.intended_print_longest_side_mm = $TailleImpressionMm
    }
    $corps = $corpsReparation | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/print/repair" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps } "Reparation imprimabilite"
    $tache = Attendre-Tache "$BaseUrl/print/repair/$($reponse.result)" $Entetes "Reparation imprimabilite"
    # "print_repair_report" : present seulement si Meshy a reussi a mesurer les parois ("route"
    # peut etre "thin_wall" = epaissies, "topology" = deja assez epaisses, ou
    # "topology_unmeasured" = non mesurable). Pas documente comme toujours present - on gere donc
    # son absence sans faire echouer le traitement pour autant (l'essentiel, le maillage reparee,
    # est quand meme disponible).
    $rapport = $tache.print_repair_report
    if ($rapport -ne $null) {
        switch ($rapport.route) {
            "thin_wall" {
                $avant = if ($rapport.thin_area_ratio_before -ne $null) { [math]::Round($rapport.thin_area_ratio_before * 100, 1) } else { "?" }
                $apres = if ($rapport.thin_area_ratio_after -ne $null) { [math]::Round($rapport.thin_area_ratio_after * 100, 1) } else { "?" }
                Ecrire-Journal "  Parois trop fines detectees et epaissies : $avant% de la surface concernee avant reparation, $apres% apres."
            }
            "topology" { Ecrire-Journal "  Parois deja assez epaisses pour $PrinterType - aucune reparation necessaire." }
            "topology_unmeasured" { Ecrire-Journal "  Epaisseur des parois non mesurable sur ce maillage - reparation non appliquee, Retexture repart du maillage d'origine." }
            default { Ecrire-Journal "  Reparation terminee ($($tache.consumed_credits) credits)." }
        }
    } else {
        Ecrire-Journal "  Reparation terminee ($($tache.consumed_credits) credits)."
    }
    return $tache
}

# 20/10/2026 : traduit l'index du menu "Qualite du maillage" (voir $menuGeometrieResolution) en
# valeur attendue par l'API ("" = standard, pas de parametre envoye).
function Obtenir-GeometryResolutionChoisie {
    switch ($menuGeometrieResolution.SelectedIndex) {
        1 { return "2k" }
        2 { return "4k" }
        default { return "" }
    }
}

# 20/10/2026 : meme principe que Obtenir-GeometryResolutionChoisie ci-dessus, mais pour
# "texture_resolution" (voir $menuTextureResolution) - "" = on ne precise rien, Meshy applique
# son propre defaut ("2k") sans qu'on ait besoin de l'envoyer explicitement.
function Obtenir-TextureResolutionChoisie {
    switch ($menuTextureResolution.SelectedIndex) {
        1 { return "4k" }
        2 { return "8k" }
        default { return "" }
    }
}

# 20/10/2026 : "0" (valeur par defaut du champ $numTailleImpression) -> $null, pour que
# Lancer-AnalyseImprimabilite/Lancer-ReparationImprimabilite sachent qu'il ne faut rien envoyer
# (et laisser Meshy appliquer son propre defaut de 150 mm) plutot que d'envoyer explicitement 0,
# une valeur hors de la plage documentee (1 a 1000 mm) qui serait refusee par l'API.
function Obtenir-TailleImpressionChoisie {
    if ($numTailleImpression.Value -gt 0) { return [int]$numTailleImpression.Value }
    return $null
}

function Coloriser-UnFichier($FichierStl, $Prompt, $Entetes, $DossierSortie, $MaxCouleurs, $AvecHorodatage, $GalerieCible, $SuffixeFournisseur = "", $ExperimentalObj = $false, [double]$AssombrirPourcent = 0, [int]$TargetPolycount = 30000, [bool]$SmartTopology = $false, [string]$GeometryResolution = "", [string]$TextureResolution = "", [bool]$ReparerParois = $false, $TailleImpressionMm = $null) {
    Ecrire-Journal ""
    Ecrire-Journal "=== $($FichierStl.Name) ==="

    $estUneImage = $FichierStl.Extension.ToLower() -in $EXTENSIONS_IMAGES
    # Credits d'une eventuelle etape prealable a la Retexture (Image to 3D si la source est une
    # image, Remesh si c'est un .stl trop lourd - les deux sont mutuellement exclusifs pour un
    # meme fichier, mais partagent ce meme compteur pour le bilan de credits en fin de fonction).
    $creditsEtapePrealable = 0

    if (-not $estUneImage) {
        $tailleMo = $FichierStl.Length / 1MB
        # 20/10/2026, Tomyn : "on a pas la fonctionnalite 400 Mo" - verifie dans le changelog officiel
        # de l'API Meshy (entree du 14/10/2026) : "model_url" accepte desormais jusqu'a 400 Mo, MAIS
        # seulement quand c'est une vraie URL http/https. On envoie le fichier en "data:" URI (base64,
        # voir $dataUri plus bas) - cette forme-la reste plafonnee a 100 Mo ("A data: URI stays at
        # 100 MB"), pas 400. Passer aux 400 Mo demanderait d'heberger le fichier quelque part avant
        # l'appel (hors scope pour l'instant, Tomyn confirme ne pas en avoir besoin : "au pire je les
        # repasserai en remesh"). Limite remontee de 50 a 100 Mo, qui est le vrai plafond actuel pour
        # notre methode en data URI (l'ancien seuil de 50 Mo etait deja perime).
        if ($tailleMo -gt 100) {
            # Bloque AVANT l'envoi plutot que d'avertir apres coup : inutile de gaspiller un appel
            # API (et potentiellement des credits) voue a l'echec sur un fichier trop gros.
            throw "fichier de $([math]::Round($tailleMo,1)) Mo, limite Meshy (data URI) = 100 Mo - non envoye"
        }
    }

    if ($estUneImage) {
        $tacheImage3D = Lancer-Image3D $FichierStl $Entetes $TargetPolycount $SmartTopology $GeometryResolution
        $creditsEtapePrealable = [int]$tacheImage3D.consumed_credits
        # 20/10/2026 : reparation des parois (voir Reparer-ParoisSiNecessaire, Analyze gratuit
        # puis Repair seulement si besoin) lancee ICI, sur le maillage NU juste genere, avant la
        # Retexture - jamais apres (la reparation supprime la texture existante). $idSourceRetexture
        # pointe ensuite vers le resultat le plus recent (repare si besoin reel, sinon le maillage
        # genere tel quel - $null signifie "pas de reparation necessaire, rien a changer").
        $idSourceRetexture = $tacheImage3D.id
        if ($ReparerParois) {
            $tacheReparation = Reparer-ParoisSiNecessaire $Entetes $tacheImage3D.id "fdm" $TailleImpressionMm
            if ($tacheReparation -ne $null) {
                $creditsEtapePrealable += [int]$tacheReparation.consumed_credits
                $idSourceRetexture = $tacheReparation.id
            }
        }
        Ecrire-Journal "  Envoi a l'API Retexture (a partir du maillage genere)..."
        if ([string]::IsNullOrWhiteSpace($Prompt)) {
            # 16/10/2026, Tomyn : veut parfois lancer sans prompt. Meshy exige pourtant un de
            # text_style_prompt / image_style_url / multiview_image_urls sur la Retexture - sans
            # prompt texte, on repasse l'image source elle-meme en "image_style_url" (meme principe
            # que image_url en data URI deja utilise dans Lancer-Image3D ci-dessus) : Meshy reapplique
            # alors les couleurs/le style de la photo d'origine plutot que d'echouer.
            $extensionImg = $FichierStl.Extension.ToLower()
            # 20/10/2026 : meme correction .webp que dans Lancer-Image3D (voir plus haut).
            $mimeImg = switch ($extensionImg) {
                { $_ -in @(".jpg", ".jpeg") } { "image/jpeg" }
                ".webp" { "image/webp" }
                default { "image/png" }
            }
            $dataUriStyle = "data:$mimeImg;base64," + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($FichierStl.FullName))
            $corpsRetexture = @{ input_task_id = $idSourceRetexture; image_style_url = $dataUriStyle; enable_original_uv = $false }
        } else {
            $corpsRetexture = @{ input_task_id = $idSourceRetexture; text_style_prompt = $Prompt; enable_original_uv = $false }
        }
    } else {
        $nbTriangles = Obtenir-NombreTriangles $FichierStl.FullName
        if ($nbTriangles -ne $null -and $nbTriangles -gt $SEUIL_TRIANGLES_REMESH_AUTO) {
            $tacheRemesh = Lancer-Remesh $FichierStl $Entetes $TargetPolycount $nbTriangles
            $creditsEtapePrealable = [int]$tacheRemesh.consumed_credits
            # 20/10/2026 : meme principe que pour la branche image ci-dessus - reparation sur le
            # maillage simplifie (Remesh), avant Retexture.
            $idSourceRetexture = $tacheRemesh.id
            if ($ReparerParois) {
                $tacheReparation = Reparer-ParoisSiNecessaire $Entetes $tacheRemesh.id "fdm" $TailleImpressionMm
                if ($tacheReparation -ne $null) {
                    $creditsEtapePrealable += [int]$tacheReparation.consumed_credits
                    $idSourceRetexture = $tacheReparation.id
                }
            }
            Ecrire-Journal "  Envoi a l'API Retexture (a partir du maillage simplifie)..."
            $corpsRetexture = @{ input_task_id = $idSourceRetexture; text_style_prompt = $Prompt; enable_original_uv = $false }
        } else {
            $octets = [System.IO.File]::ReadAllBytes($FichierStl.FullName)
            $base64 = [Convert]::ToBase64String($octets)
            $dataUri = "data:application/octet-stream;base64,$base64"

            # 20/10/2026 : reparation des parois IMPOSSIBLE ici - ce fichier est envoye directement
            # en "model_url" (data URI), sans tache Meshy prealable a chainer, et l'API Repair
            # Printability n'accepte justement PAS de data URI pour un .stl (http/https uniquement
            # pour ce format - seuls .glb/.gltf acceptent une data URI). Forcer un Remesh ici juste
            # pour obtenir une tache a chainer gaspillerait des credits sur un fichier qui n'en a
            # pas besoin par ailleurs. On previent simplement dans le journal plutot que d'ignorer
            # la case en silence.
            if ($ReparerParois) {
                Ecrire-Journal "  Reparation des parois ignoree pour ce fichier (trop petit pour passer par Remesh, l'API ne l'accepte qu'a partir d'une tache Meshy existante)."
            }
            Ecrire-Journal "  Envoi a l'API Retexture..."
            $corpsRetexture = @{ model_url = $dataUri; text_style_prompt = $Prompt; enable_original_uv = $false }
        }
    }
    # 20/10/2026 : "texture_resolution" (voir Obtenir-TextureResolutionChoisie) - ajoute seulement
    # si different du defaut Meshy ("2k"), pour les 4 branches ci-dessus a la fois (le parametre
    # s'applique a l'etape Retexture elle-meme, peu importe comment on y est arrive).
    if ($TextureResolution -in @("4k", "8k")) {
        $corpsRetexture.texture_resolution = $TextureResolution
    }
    $corps = $corpsRetexture | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/retexture" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps } "Retexture"
    $idRetexture = $reponse.result

    $tacheRetexture = Attendre-Tache "$BaseUrl/retexture/$idRetexture" $Entetes "Retexture"
    Ecrire-Journal "  Retexture terminee ($($tacheRetexture.consumed_credits) credits)."

    # Apercu fourni directement par Meshy (image du modele texture), recupere maintenant tant
    # qu'on a l'URL sous la main - sert de vignette pour ce resultat, pas de rendu a faire nous-memes.
    $imageApercu = if ($tacheRetexture.thumbnail_url) { Obtenir-ImageDepuisUrl $tacheRetexture.thumbnail_url } else { $null }

    $suffixe = $SuffixeFournisseur + $(if ($AvecHorodatage) { "_colorise_" + (Get-Date -Format 'yyyyMMdd_HHmmss') } else { "_colorise" })

    if ($ExperimentalObj) {
        # --- Variante experimentale (2026-10-07) : .obj texture directement depuis Retexture,
        # sans passer par Multi-Color Print (une seule etape facturee au lieu de deux). A la
        # difference de Tripo, cette texture est une image PBR en UV, pas une couleur par sommet -
        # rien ne garantit que Bambu Studio proposera la meme boite de dialogue de correspondance
        # automatique. Trois fichiers a recuperer (obj + mtl + image de texture), dans un
        # sous-dossier dedie comme pour Tripo (eviter toute collision de nom entre fichiers d'un
        # meme lot, les noms generes par Meshy n'etant pas forcement uniques).
        $urlObj = $tacheRetexture.model_urls.obj
        $urlMtl = $tacheRetexture.model_urls.mtl
        $urlTexture = if ($tacheRetexture.texture_urls -and $tacheRetexture.texture_urls.Count -gt 0) { $tacheRetexture.texture_urls[0].base_color } else { $null }
        if (-not $urlObj) {
            $reponseBrute = $tacheRetexture | ConvertTo-Json -Depth 6 -Compress
            throw "reponse Retexture sans .obj exploitable (model_urls.obj manquant) - reponse brute recue : $reponseBrute"
        }

        $dossierResultat = Join-Path $DossierSortie ($FichierStl.BaseName + $suffixe)
        New-Item -ItemType Directory -Force -Path $dossierResultat | Out-Null

        foreach ($url in @($urlObj, $urlMtl, $urlTexture)) {
            if (-not $url) { continue }
            # Nom de fichier tel que fourni par Meshy (sans la partie requete de l'URL) - garde la
            # correspondance interne obj->mtl->texture telle que Meshy l'a generee, plutot que de
            # risquer de la casser en renommant nous-memes.
            $nomFichier = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
            $cheminTelecharge = Join-Path $dossierResultat $nomFichier
            Invoquer-AvecReessaiReseau { Invoke-WebRequest -Uri $url -OutFile $cheminTelecharge -TimeoutSec 60 } "Telechargement du resultat" | Out-Null

            # Assombrissement (demande de Tomyn le 08/10/2026) : uniquement l'image de texture,
            # pas le .obj ni le .mtl - precompense l'eclaircissement du melange automatique Bambu
            # Studio quand le jeu de filaments choisi ensuite comprend du blanc (voir l'infobulle).
            if ($url -eq $urlTexture -and $AssombrirPourcent -gt 0) {
                Assombrir-FichierImage $cheminTelecharge $AssombrirPourcent
                Ecrire-Journal "  Texture assombrie de $AssombrirPourcent% (reglage utilisateur)."
            }
        }
        Ecrire-Journal "  -> Enregistre : $dossierResultat (ouvrir le .obj dans Bambu Studio - un 'reparer le maillage' peut etre propose, c'est normal pour un import OBJ)"

        $cheminObjFinal = Join-Path $dossierResultat ([System.IO.Path]::GetFileName(([Uri]$urlObj).AbsolutePath))

        # 13/10/2026 : voir le commentaire equivalent dans Coloriser-UnFichierTripo plus haut.
        $descriptionGeneree = Generer-DescriptionMakerWorld $FichierStl.BaseName $Prompt
        try { Set-Content -Path (Join-Path $dossierResultat "description_makerworld.txt") -Value $descriptionGeneree.Texte -Encoding UTF8 } catch { }

        Ajouter-Vignette $GalerieCible $cheminObjFinal $imageApercu -texteDescription $descriptionGeneree.Texte
        [System.Windows.Forms.Application]::DoEvents()

        # Une seule etape facturee dans cette variante (pas de Multi-Color Print), plus le
        # maillage Image to 3D si la source etait une image (0 si c'etait deja un modele 3D).
        $creditsTotal = $creditsEtapePrealable + [int]$tacheRetexture.consumed_credits
        Enregistrer-HistoriqueFichier $FichierStl.Name "Meshy (.obj)" $creditsTotal $cheminObjFinal
        return $creditsTotal
    }

    Ecrire-Journal "  Envoi a l'API Multi-Color Print..."
    $corps = @{ input_task_id = $idRetexture; max_colors = $MaxCouleurs; style = "cartoon"; printer_brand = "bambu" } | ConvertTo-Json
    $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/print/multi-color" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps } "Multi-Color Print"
    $idImpression = $reponse.result

    $tacheImpression = Attendre-Tache "$BaseUrl/print/multi-color/$idImpression" $Entetes "Multi-Color Print"
    Ecrire-Journal "  Multi-Color Print terminee ($($tacheImpression.consumed_credits) credits)."

    $cheminSortie = Join-Path $DossierSortie ($FichierStl.BaseName + $suffixe + ".3mf")
    Invoquer-AvecReessaiReseau { Invoke-WebRequest -Uri $tacheImpression.model_urls.'3mf' -OutFile $cheminSortie } "Telechargement du .3mf final" | Out-Null
    Ecrire-Journal "  -> Enregistre : $cheminSortie"

    # 13/10/2026 : voir le commentaire equivalent dans Coloriser-UnFichierTripo plus haut. Fichier
    # unique ici (pas de sous-dossier) - le .txt est depose juste a cote avec le meme nom de base.
    $descriptionGeneree = Generer-DescriptionMakerWorld $FichierStl.BaseName $Prompt
    $cheminDescription = Join-Path $DossierSortie ($FichierStl.BaseName + $suffixe + "_description_makerworld.txt")
    try { Set-Content -Path $cheminDescription -Value $descriptionGeneree.Texte -Encoding UTF8 } catch { }

    Ajouter-Vignette $GalerieCible $cheminSortie $imageApercu -texteDescription $descriptionGeneree.Texte
    [System.Windows.Forms.Application]::DoEvents()

    # Credits reellement consommes pour ce fichier (les deux etapes, plus l'Image to 3D en amont
    # si la source etait une image), pour le total du lot dans l'historique - distinct de
    # l'estimation affichee avant de lancer.
    $creditsTotal = $creditsEtapePrealable + [int]$tacheRetexture.consumed_credits + [int]$tacheImpression.consumed_credits
    Enregistrer-HistoriqueFichier $FichierStl.Name "Meshy" $creditsTotal $cheminSortie
    return $creditsTotal
}

function Afficher-FenetreHistorique {
    $fenetre = New-Object System.Windows.Forms.Form
    $fenetre.Text = "Historique des lots traites"
    $fenetre.Size = New-Object System.Drawing.Size(560, 420)
    $fenetre.StartPosition = "CenterParent"
    $fenetre.FormBorderStyle = "FixedDialog"
    $fenetre.MaximizeBox = $false
    $fenetre.MinimizeBox = $false
    $fenetre.BackColor = $THEME.FondApp
    try { $fenetre.Icon = $form.Icon } catch { }

    $zoneTexte = New-Object System.Windows.Forms.TextBox
    $zoneTexte.Multiline = $true
    $zoneTexte.ReadOnly = $true
    $zoneTexte.ScrollBars = "Vertical"
    $zoneTexte.BackColor = $THEME.Surface
    $zoneTexte.ForeColor = $THEME.Texte
    $zoneTexte.Font = New-Object System.Drawing.Font("Consolas", 9)
    $zoneTexte.Location = New-Object System.Drawing.Point(10, 10)
    $zoneTexte.Size = New-Object System.Drawing.Size(525, 330)

    if (Test-Path $CheminHistorique) {
        $lignes = Get-Content $CheminHistorique
        $totalCredits = 0
        $totalReussites = 0
        $texteAffiche = New-Object System.Text.StringBuilder
        [void]$texteAffiche.AppendLine("Date              Fichiers  Reussis  Echecs  Credits")
        [void]$texteAffiche.AppendLine("----------------------------------------------------")
        foreach ($ligne in ($lignes | Where-Object { $_.Trim() })) {
            $champs = $ligne -split ';'
            if ($champs.Count -ge 5) {
                [void]$texteAffiche.AppendLine("{0,-17} {1,-9} {2,-8} {3,-7} {4}" -f $champs[0], $champs[1], $champs[2], $champs[3], $champs[4])
                $totalCredits += [int]$champs[4]
                $totalReussites += [int]$champs[2]
            }
        }
        [void]$texteAffiche.AppendLine("----------------------------------------------------")
        [void]$texteAffiche.AppendLine("Total : $totalReussites figurine(s) reussie(s), $totalCredits credits consommes (sur $($lignes.Count) lot(s))")
        $zoneTexte.Text = $texteAffiche.ToString()
    } else {
        $zoneTexte.Text = "Aucun lot traite pour l'instant."
    }
    $fenetre.Controls.Add($zoneTexte)

    $btnVider = New-Object System.Windows.Forms.Button
    $btnVider.Text = "Vider l'historique"
    $btnVider.Location = New-Object System.Drawing.Point(10, 350)
    $btnVider.Size = New-Object System.Drawing.Size(130, 28)
    $btnVider.Add_Click({
        if (Test-Path $CheminHistorique) { Remove-Item $CheminHistorique -Force }
        $fenetre.Close()
    }.GetNewClosure())
    $fenetre.Controls.Add($btnVider)
    Rendre-BoutonPlat $btnVider "danger"

    $btnFermer = New-Object System.Windows.Forms.Button
    $btnFermer.Text = "Fermer"
    $btnFermer.Location = New-Object System.Drawing.Point(405, 350)
    $btnFermer.Size = New-Object System.Drawing.Size(130, 28)
    $btnFermer.Add_Click({ $fenetre.Close() }.GetNewClosure())
    $fenetre.Controls.Add($btnFermer)
    Rendre-BoutonPlat $btnFermer "secondaire"

    [void]$fenetre.ShowDialog($form)
}

# Historique PAR FICHIER avec recherche (16/10/2026, idee d'amelioration validee "tu peux toutes
# les faire") - contrairement a Afficher-FenetreHistorique ci-dessus (un resume par LOT, pas de nom
# de fichier dedans), celui-ci liste chaque fichier individuellement avec un champ de recherche qui
# filtre en direct (nom de fichier, date, fournisseur, chemin de sortie) - $CheminHistoriqueFichiers
# etait deja alimente a chaque fichier reussi (Enregistrer-HistoriqueFichier) mais n'avait jusqu'ici
# aucune fenetre pour le consulter dans l'appli.
function Charger-LignesHistoriqueFichiers {
    if (-not (Test-Path $CheminHistoriqueFichiers)) { return @() }
    $lignes = @(Get-Content $CheminHistoriqueFichiers | Where-Object { $_.Trim() })
    if ($lignes.Count -le 1) { return @() }  # rien que l'en-tete
    return @($lignes | Select-Object -Skip 1 | ForEach-Object {
        $champs = $_ -split ';'
        if ($champs.Count -ge 5) {
            [PSCustomObject]@{ Date = $champs[0]; Fichier = $champs[1]; Fournisseur = $champs[2]; Credits = $champs[3]; Sortie = $champs[4] }
        }
    } | Where-Object { $_ })
}

function Afficher-FenetreHistoriqueFichiers {
    $fenetre = New-Object System.Windows.Forms.Form
    $fenetre.Text = "Historique par fichier"
    $fenetre.Size = New-Object System.Drawing.Size(820, 480)
    $fenetre.MinimumSize = New-Object System.Drawing.Size(500, 300)
    $fenetre.StartPosition = "CenterParent"
    $fenetre.BackColor = $THEME.FondApp
    try { $fenetre.Icon = $form.Icon } catch { }

    $labelRecherche = New-Object System.Windows.Forms.Label
    $labelRecherche.Text = "Rechercher :"
    $labelRecherche.Location = New-Object System.Drawing.Point(10, 14)
    $labelRecherche.AutoSize = $true
    $labelRecherche.ForeColor = $THEME.Texte
    $fenetre.Controls.Add($labelRecherche)

    $txtRecherche = New-Object System.Windows.Forms.TextBox
    $txtRecherche.Location = New-Object System.Drawing.Point(95, 10)
    $txtRecherche.Size = New-Object System.Drawing.Size(300, 24)
    $fenetre.Controls.Add($txtRecherche)

    $labelCompteur = New-Object System.Windows.Forms.Label
    $labelCompteur.Location = New-Object System.Drawing.Point(410, 14)
    $labelCompteur.AutoSize = $true
    $labelCompteur.ForeColor = $THEME.TexteSecondaire
    $fenetre.Controls.Add($labelCompteur)

    $liste = New-Object System.Windows.Forms.ListView
    $liste.View = "Details"
    $liste.FullRowSelect = $true
    $liste.GridLines = $true
    $liste.Location = New-Object System.Drawing.Point(10, 44)
    $liste.Size = New-Object System.Drawing.Size(790, 370)
    $liste.Anchor = "Top, Bottom, Left, Right"
    [void]$liste.Columns.Add("Date", 130)
    [void]$liste.Columns.Add("Fichier", 260)
    [void]$liste.Columns.Add("Fournisseur", 110)
    [void]$liste.Columns.Add("Credits", 70)
    [void]$liste.Columns.Add("Sortie", 210)
    $fenetre.Controls.Add($liste)

    $btnFermer = New-Object System.Windows.Forms.Button
    $btnFermer.Text = "Fermer"
    $btnFermer.Location = New-Object System.Drawing.Point(725, 420)
    $btnFermer.Size = New-Object System.Drawing.Size(75, 28)
    $btnFermer.Anchor = "Bottom, Right"
    Rendre-BoutonPlat $btnFermer "secondaire"
    $btnFermer.Add_Click({ $fenetre.Close() }.GetNewClosure())
    $fenetre.Controls.Add($btnFermer)

    $toutesLesLignes = @(Charger-LignesHistoriqueFichiers)

    # Scriptblock plutot qu'une fonction nommee imbriquee (incertain qu'une fonction definie DANS
    # cette fonction reste resolvable depuis la closure de l'evenement TextChanged plus bas) -
    # capture $liste/$txtRecherche/$toutesLesLignes/$labelCompteur via GetNewClosure comme partout
    # ailleurs dans ce fichier.
    $rafraichirListe = {
        $liste.Items.Clear()
        $filtre = $txtRecherche.Text.Trim()
        $lignesAffichees = if ($filtre) {
            @($toutesLesLignes | Where-Object { "$($_.Date) $($_.Fichier) $($_.Fournisseur) $($_.Sortie)" -like "*$filtre*" })
        } else { $toutesLesLignes }
        foreach ($l in $lignesAffichees) {
            $item = New-Object System.Windows.Forms.ListViewItem($l.Date)
            [void]$item.SubItems.Add($l.Fichier)
            [void]$item.SubItems.Add($l.Fournisseur)
            [void]$item.SubItems.Add($l.Credits)
            [void]$item.SubItems.Add($l.Sortie)
            [void]$liste.Items.Add($item)
        }
        $labelCompteur.Text = "$($lignesAffichees.Count) / $($toutesLesLignes.Count) ligne(s)"
    }.GetNewClosure()

    $txtRecherche.Add_TextChanged($rafraichirListe)

    if ($toutesLesLignes.Count -eq 0) {
        $labelCompteur.Text = "Aucun fichier dans l'historique pour l'instant."
    } else {
        & $rafraichirListe
    }

    [void]$fenetre.ShowDialog($form)
}

# Graphique de consommation de credits dans le temps (16/10/2026, idee validee "tu peux toutes
# les faire") - dessin GDI+ maison (pas de bibliotheque de graphique disponible dans cet
# environnement), un simple diagramme en barres a partir de historique_lots.csv (format
# "Date;Fichiers;Reussis;Echecs;Credits", une ligne par lot - voir plus haut dans
# Lancer-Traitement). Les 40 lots les plus recents seulement, pour garder des barres assez
# larges pour rester lisibles. PAS TESTE VISUELLEMENT (pas de Windows sous la main) - logique de
# calcul des coordonnees relue attentivement, meme risque que le reste du rendu GDI+ de cette
# appli (coins arrondis, miniatures STL).
function Afficher-FenetreGraphiqueCredits {
    if (-not (Test-Path $CheminHistorique)) {
        Afficher-Boite "Aucun historique de lot pour l'instant - rien a afficher (le graphique se remplit a chaque lot traite)." "Historique vide" "OK" "Info" | Out-Null
        return
    }
    $points = New-Object System.Collections.Generic.List[hashtable]
    foreach ($ligne in (Get-Content $CheminHistorique)) {
        $champs = $ligne -split ';'
        if ($champs.Count -lt 5) { continue }
        $creditsLigne = 0
        if ([int]::TryParse($champs[4], [ref]$creditsLigne)) {
            [void]$points.Add(@{ Date = $champs[0]; Credits = $creditsLigne })
        }
    }
    if ($points.Count -eq 0) {
        Afficher-Boite "Aucune ligne d'historique exploitable pour l'instant." "Historique vide" "OK" "Info" | Out-Null
        return
    }
    $pointsAffiches = @($points | Select-Object -Last 40)

    $fenetre = New-Object System.Windows.Forms.Form
    $fenetre.Text = "Consommation de credits par lot"
    $fenetre.StartPosition = "CenterParent"
    $fenetre.ClientSize = New-Object System.Drawing.Size(900, 480)
    $fenetre.BackColor = $THEME.Surface
    $fenetre.MinimizeBox = $false
    try { $fenetre.Icon = $form.Icon } catch { }

    $panneauGraphique = New-Object System.Windows.Forms.Panel
    $panneauGraphique.Location = New-Object System.Drawing.Point(10, 10)
    $panneauGraphique.Size = New-Object System.Drawing.Size(880, 420)
    $panneauGraphique.Anchor = "Top, Bottom, Left, Right"
    $panneauGraphique.BackColor = [System.Drawing.Color]::White
    $fenetre.Controls.Add($panneauGraphique)

    $panneauGraphique.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $largeur = $panneauGraphique.Width
        $hauteur = $panneauGraphique.Height
        $margeGauche = 55
        $margeBas = 40
        $margeHaut = 25
        $margeDroite = 15
        $zoneLargeur = $largeur - $margeGauche - $margeDroite
        $zoneHauteur = $hauteur - $margeHaut - $margeBas
        if ($zoneLargeur -le 10 -or $zoneHauteur -le 10) { return }

        $maxCredits = [Math]::Max(1, ($pointsAffiches | ForEach-Object { $_.Credits } | Measure-Object -Maximum).Maximum)

        $styloAxe = New-Object System.Drawing.Pen([System.Drawing.Color]::Gainsboro, 1)
        $styloGrille = New-Object System.Drawing.Pen([System.Drawing.Color]::WhiteSmoke, 1)
        $pinceauTexte = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::DimGray)
        $policeAxe = New-Object System.Drawing.Font("Segoe UI", 7.5)
        $policeTitre = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)

        $g.DrawLine($styloAxe, $margeGauche, $margeHaut, $margeGauche, $margeHaut + $zoneHauteur)
        $g.DrawLine($styloAxe, $margeGauche, $margeHaut + $zoneHauteur, $margeGauche + $zoneLargeur, $margeHaut + $zoneHauteur)

        foreach ($f in @(0, 0.5, 1)) {
            $y = $margeHaut + $zoneHauteur - ($f * $zoneHauteur)
            $valeur = [int]([Math]::Round($maxCredits * $f))
            $g.DrawString("$valeur", $policeAxe, $pinceauTexte, 2, ($y - 7))
            $g.DrawLine($styloGrille, $margeGauche, $y, $margeGauche + $zoneLargeur, $y)
        }

        $nombreBarres = $pointsAffiches.Count
        $pasBarre = $zoneLargeur / $nombreBarres
        $largeurBarre = [Math]::Max(3, $pasBarre * 0.6)
        $pinceauBarre = New-Object System.Drawing.SolidBrush($THEME.AccentPrincipal)
        $sautEtiquette = [Math]::Max(1, [Math]::Ceiling($nombreBarres / 12.0))

        for ($i = 0; $i -lt $nombreBarres; $i++) {
            $pt = $pointsAffiches[$i]
            $hauteurBarre = [Math]::Max(1, ($pt.Credits / $maxCredits) * $zoneHauteur)
            $x = $margeGauche + ($i * $pasBarre) + (($pasBarre - $largeurBarre) / 2)
            $y = $margeHaut + $zoneHauteur - $hauteurBarre
            $g.FillRectangle($pinceauBarre, $x, $y, $largeurBarre, $hauteurBarre)
            if ($i % $sautEtiquette -eq 0) {
                $dateCourte = ($pt.Date -split ' ')[0]
                $tailleTexte = $g.MeasureString($dateCourte, $policeAxe)
                $g.DrawString($dateCourte, $policeAxe, $pinceauTexte, ($x + $largeurBarre / 2 - $tailleTexte.Width / 2), ($margeHaut + $zoneHauteur + 4))
            }
        }
        $totalAffiche = ($pointsAffiches | ForEach-Object { $_.Credits } | Measure-Object -Sum).Sum
        $g.DrawString("Total sur les $nombreBarres dernier(s) lot(s) : $totalAffiche credits", $policeTitre, $pinceauTexte, $margeGauche, 2)
    }.GetNewClosure())

    [void]$fenetre.ShowDialog($form)
}

# Verifie la cle ET recupere le solde en un seul appel (meme endpoint) :
#   statut "valide"   -> $solde contient le vrai solde
#   statut "invalide" -> cle refusee par Meshy (HTTP 401/403), bloquant
#   statut "inconnu"  -> echec pour une autre raison (reseau, timeout...), pas bloquant en soi,
#                        on ne peut juste pas confirmer - a l'utilisateur de decider s'il continue
function Verifier-CleEtSolde($cleApi) {
    try {
        $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrl/balance" -Headers @{ Authorization = "Bearer $cleApi" } -Method Get } "Verification cle Meshy" 2 3
        # 20/10/2026, Tomyn (suite au changelog Meshy du 10/10/2026) : la reponse contient maintenant
        # aussi monthly_credits, permanent_credits et monthly_resets_at - utile pour distinguer les
        # credits qui vont expirer au prochain renouvellement de ceux qui restent definitivement.
        # Lues en "best effort" (PSObject.Properties.Name) : certains comptes/plans pourraient ne pas
        # les renvoyer, pas de raison de faire planter la verification de solde pour autant.
        $mensuels = if ($reponse.PSObject.Properties.Name -contains "monthly_credits") { [int]$reponse.monthly_credits } else { $null }
        $permanents = if ($reponse.PSObject.Properties.Name -contains "permanent_credits") { [int]$reponse.permanent_credits } else { $null }
        $renouvellement = if ($reponse.PSObject.Properties.Name -contains "monthly_resets_at") { $reponse.monthly_resets_at } else { $null }
        return @{ Statut = "valide"; Solde = [int]$reponse.balance; CreditsMensuels = $mensuels; CreditsPermanents = $permanents; RenouvellementLe = $renouvellement }
    } catch {
        $codeHttp = $null
        try { $codeHttp = [int]$_.Exception.Response.StatusCode.value__ } catch { }
        if ($codeHttp -eq 401 -or $codeHttp -eq 403) {
            return @{ Statut = "invalide"; Solde = $null }
        }
        return @{ Statut = "inconnu"; Solde = $null }
    }
}

# 20/10/2026 : endpoint corrige, "/user/balance" n'avait jamais ete confirme (devine a l'origine) -
# le vrai endpoint documente est "/account/balance" (developers.tripo3d.ai/fr/docs/account),
# reponse "data.balance" + "data.frozen" (credits geles, taches en cours). Fonction non appelee
# pour l'instant (solde Tripo pas encore verifie avant lancement, voir plus bas), mais corrigee
# puisque l'ancien endpoint etait un pari jamais verifie et celui-ci est maintenant confirme.
function Verifier-CleEtSoldeTripo($cleApi) {
    try {
        $reponse = Invoquer-AvecReessaiReseau { Invoke-RestMethod -Uri "$BaseUrlTripo/account/balance" -Headers @{ Authorization = "Bearer $cleApi" } -Method Get -TimeoutSec 15 } "Verification cle Tripo" 2 3
        $donnees = if ($reponse.data) { $reponse.data } else { $reponse }
        # 20/10/2026 : [double] au lieu de [int] - confirme dans le changelog officiel Tripo (note
        # du 08/2026) : "balance" (et credits_consumed/frozen) sont des nombres avec jusqu'a 2
        # decimales (credits fractionnaires possibles, ex. remises VIP) - un [int] tronquait
        # silencieusement vers le bas (42.75 affiche "42"). Fonction non appelee pour l'instant (solde
        # Tripo pas encore verifie avant lancement, voir plus bas), corrige quand meme en passant.
        $solde = if ($donnees.balance -ne $null) { [double]$donnees.balance } else { $null }
        return @{ Statut = "valide"; Solde = $solde }
    } catch {
        $codeHttp = $null
        try { $codeHttp = [int]$_.Exception.Response.StatusCode.value__ } catch { }
        if ($codeHttp -eq 401 -or $codeHttp -eq 403) {
            return @{ Statut = "invalide"; Solde = $null }
        }
        return @{ Statut = "inconnu"; Solde = $null }
    }
}

$script:dernierLotEchecs = @()

function Lancer-Traitement($fichiersStl) {
    if ($fichiersStl.Count -eq 0) {
        Afficher-Boite "Aucun fichier a traiter." "Rien a faire" | Out-Null
        return
    }
    # Au moins une des deux cles est obligatoire, peu importe laquelle - jamais une exigence
    # specifique sur Meshy precisement.
    if (-not $txtCleApi.Text -and -not $txtCleApiTripo.Text) {
        Afficher-Boite "Aucune cle API renseignee (Meshy ou Tripo, au moins une est necessaire)." "Erreur" "OK" "Error" | Out-Null
        return
    }
    $fournisseur = $menuFournisseur.SelectedItem
    if ($caseComparerFournisseurs.Checked) {
        if (-not $txtCleApi.Text -or -not $txtCleApiTripo.Text) {
            Afficher-Boite "Le mode comparaison necessite les deux cles API (Meshy et Tripo)." "Erreur" "OK" "Error" | Out-Null
            return
        }
    } else {
        if ($fournisseur -eq "Meshy" -and -not $txtCleApi.Text) {
            Afficher-Boite "Meshy est selectionne mais sa cle API est vide." "Erreur" "OK" "Error" | Out-Null
            return
        }
        if ($fournisseur -eq "Tripo" -and -not $txtCleApiTripo.Text) {
            Afficher-Boite "Tripo est selectionne mais sa cle API est vide." "Erreur" "OK" "Error" | Out-Null
            return
        }
        if ($fournisseur -ne "Meshy" -and $fournisseur -ne "Tripo") {
            Afficher-Boite "Choisis un fournisseur (Meshy ou Tripo) avant de lancer." "Erreur" "OK" "Error" | Out-Null
            return
        }
    }
    # 16/10/2026, Tomyn : "des fois je veux lancer la colorisation sans mettre de prompt". Premier
    # essai (retirer purement et simplement le blocage) corrige par son propre test reel : Meshy
    # EXIGE un de text_style_prompt / image_style_url / multiview_image_urls sur la Retexture, sinon
    # elle echoue net APRES avoir deja depense les credits de l'etape Image to 3D ("Either
    # text_style_prompt, image_style_url or multiview_image_urls must be provided"). Coloriser-
    # UnFichier (Meshy, cas image) sait maintenant repasser l'image source elle-meme comme reference
    # de style quand le prompt est vide - mais seulement dans CE cas precis (Meshy + image source).
    # 20/10/2026 : Tripo aussi, maintenant que Image to 3D Tripo existe (voir
    # Lancer-ImageModelTripo) - sans prompt, elle texture directement depuis la photo (texture=$true
    # a l'appel Image to 3D, pas d'etape Texture separee a alimenter). Exemption donc etendue a
    # Tripo seul et au mode comparaison, tant que ce sont bien des images dans les deux cas - un
    # fichier 3D sans photo source reste bloque, ni Meshy ni Tripo n'ont de repli possible pour ca.
    if (-not $txtPrompt.Text) {
        $toutesImages = -not ($fichiersStl | Where-Object { $_.Extension.ToLower() -notin $EXTENSIONS_IMAGES })
        $exemptionPossible = $toutesImages
        if (-not $exemptionPossible) {
            Afficher-Boite "Le style/couleurs voulues est vide.`r`n`r`n(Sans prompt, Meshy et Tripo ont besoin de repartir du style de l'image source - possible seulement sur des fichiers image, pas de .stl/.obj.)" "Erreur" "OK" "Error" | Out-Null
            return
        }
    }
    if (-not $txtDossierSortie.Text) {
        Afficher-Boite "Dossier de sortie vide." "Erreur" "OK" "Error" | Out-Null
        return
    }

    # Verification de l'espace disque disponible (16/10/2026, idee d'amelioration validee "tu peux
    # toutes les faire") - estimation large (30 Mo/fichier, un resultat colorise avec sa texture
    # peut peser plusieurs dizaines de Mo) : avertit AVANT de lancer un gros lot plutot que de
    # decouvrir un disque plein en cours de route (echec moche, credits potentiellement deja
    # depenses pour rien). Non bloquant, comme la verification de solde juste en dessous - jamais
    # sur de la taille reelle avant coup, donc pas question d'empecher totalement de continuer.
    try {
        $dossierSortieTest = $txtDossierSortie.Text
        if (-not (Test-Path $dossierSortieTest)) { $dossierSortieTest = Split-Path $dossierSortieTest -Parent }
        if ($dossierSortieTest -and (Test-Path $dossierSortieTest)) {
            $racineDisque = (Get-Item $dossierSortieTest).PSDrive.Root
            $lecteur = New-Object System.IO.DriveInfo($racineDisque)
            if ($lecteur.IsReady) {
                $espaceLibreMo = [Math]::Round($lecteur.AvailableFreeSpace / 1MB)
                $espaceEstimeMo = $fichiersStl.Count * 30
                if ($espaceLibreMo -lt $espaceEstimeMo) {
                    $reponseEspace = Afficher-Boite "Espace disque libre sur $($lecteur.Name) : ~$espaceLibreMo Mo. Estimation (large) pour ce lot : ~$espaceEstimeMo Mo.`r`n`r`nContinuer quand meme ?" "Espace disque potentiellement insuffisant" "YesNo" "Warning"
                    if ($reponseEspace -ne "Yes") { return }
                }
            }
        }
    } catch { }

    # --- Verification de la cle API et du solde avant de lancer, selon le fournisseur choisi ---
    # 21/10/2026 : Tripo reactivee ici. Elle etait desactivee depuis l'origine car le tout premier
    # endpoint devine (/user/balance, jamais confirme) provoquait un blocage de l'appli des le clic
    # sur Lancer. Le 20/10/2026, Verifier-CleEtSoldeTripo a ete corrigee vers le vrai endpoint
    # documente (/account/balance, developers.tripo3d.ai/fr/docs/account) mais etait restee non
    # appelee, le blocage original n'ayant pas encore ete reproduit/confirme regle. Elle partage
    # exactement le meme squelette (try/catch, Invoquer-AvecReessaiReseau, TimeoutSec) que
    # Verifier-CleEtSolde (Meshy), deja en production sans souci de ce type - le blocage etait tres
    # probablement du a l'ancien endpoint devine (404 ou reponse inattendue mal geree), pas a un
    # defaut structurel de la fonction. Pas de test reseau live possible ici (pas de cle Tripo
    # utilisable a disposition) : a surveiller au tout premier lot Tripo lance apres cette mise a
    # jour - en cas de souci, redesactiver est aussi simple que remettre "ignore" en dur ci-dessous.
    $coutEstime = $fichiersStl.Count * $CREDITS_ESTIMES_PAR_FICHIER
    $coutEstimeTripo = $fichiersStl.Count * $CREDITS_ESTIMES_PAR_FICHIER_TRIPO
    $utiliseMeshyPourCeLot = ($fournisseur -eq "Meshy" -or $caseComparerFournisseurs.Checked)
    $utiliseTripoPourCeLot = ($fournisseur -eq "Tripo" -or $caseComparerFournisseurs.Checked)
    $verifCle = if ($utiliseMeshyPourCeLot) { Verifier-CleEtSolde $txtCleApi.Text } else { @{ Statut = "ignore"; Solde = $null } }
    if ($verifCle.Statut -eq "invalide") {
        Afficher-Boite "La cle API Meshy semble invalide ou expiree. Verifie-la dans le champ correspondant avant de relancer." "Cle API invalide" "OK" "Error" | Out-Null
        return
    }
    $verifCleTripo = if ($utiliseTripoPourCeLot) { Verifier-CleEtSoldeTripo $txtCleApiTripo.Text } else { @{ Statut = "ignore"; Solde = $null } }
    if ($verifCleTripo.Statut -eq "invalide") {
        Afficher-Boite "La cle API Tripo semble invalide ou expiree. Verifie-la dans le champ correspondant avant de relancer." "Cle API invalide" "OK" "Error" | Out-Null
        return
    }
    # Avertissements "solde potentiellement insuffisant" / "verification impossible" regroupes en
    # UNE SEULE boite (mode comparaison : eviter deux popups successives pour le meme lancement).
    $avertissementsPrelancement = @()
    if ($verifCle.Statut -eq "inconnu") {
        $avertissementsPrelancement += "Meshy : impossible de verifier la cle ou le solde pour l'instant (probleme reseau ?)."
    } elseif ($verifCle.Solde -ne $null -and $verifCle.Solde -lt $coutEstime) {
        # 20/10/2026 : detail mensuel/permanent ajoute au message quand Meshy le fournit (voir
        # Verifier-CleEtSolde) - utile ici precisement, puisque c'est le moment ou Tomyn doit decider
        # s'il continue malgre un solde court : savoir qu'une partie va de toute facon expirer au
        # renouvellement (donc "autant s'en servir maintenant") change la decision.
        $detailSolde = ""
        if ($verifCle.CreditsMensuels -ne $null -and $verifCle.CreditsPermanents -ne $null) {
            $detailSolde = " (dont $($verifCle.CreditsMensuels) mensuels, $($verifCle.CreditsPermanents) permanents"
            if ($verifCle.RenouvellementLe) { $detailSolde += ", renouvellement le $($verifCle.RenouvellementLe)" }
            $detailSolde += ")"
        }
        $avertissementsPrelancement += "Meshy : solde actuel $($verifCle.Solde) credits$detailSolde, cout estime ~$coutEstime credits pour ce lot."
    }
    if ($verifCleTripo.Statut -eq "inconnu") {
        $avertissementsPrelancement += "Tripo : impossible de verifier la cle ou le solde pour l'instant (probleme reseau ?)."
    } elseif ($verifCleTripo.Solde -ne $null -and $verifCleTripo.Solde -lt $coutEstimeTripo) {
        $avertissementsPrelancement += "Tripo : solde actuel $($verifCleTripo.Solde) credits, cout estime ~$coutEstimeTripo credits pour ce lot."
    }
    if ($avertissementsPrelancement.Count -gt 0) {
        $texteAvertPrelancement = ($avertissementsPrelancement -join "`n")
        $reponseBoite = Afficher-Boite "$texteAvertPrelancement`n`nContinuer quand meme ?" "Verification du solde avant lancement" "YesNo" "Warning"
        if ($reponseBoite -ne "Yes") { return }
    }

    # --- Avertissement si des resultats existants seraient ecrases / reprise d'un lot interrompu ---
    # Suffixes distincts par fournisseur en mode comparaison (_meshy_colorise / _tripo_colorise, voir
    # Coloriser-UnFichier/Tripo) : il faut verifier les deux pour ne rater aucune collision. Meshy
    # sort un seul fichier .3mf ; Tripo sort desormais un SOUS-DOSSIER (voir Coloriser-UnFichierTripo,
    # export OBJ livre en ZIP) - les deux sont donc verifies differemment (Test-Path fonctionne pour
    # les deux, fichier ou dossier). Calcule maintenant INCONDITIONNELLEMENT (plus seulement dans le
    # cas "dossier deja existant" ci-dessous) car reutilise plus bas dans la boucle de traitement pour
    # la reprise d'un lot interrompu.
    $dossierSortie = $txtDossierSortie.Text
    $suffixesSortieActuels = if ($caseComparerFournisseurs.Checked) {
        # Si l'option .obj experimentale est cochee en meme temps que la comparaison, Meshy sort
        # aussi un sous-dossier (voir Coloriser-UnFichier) au lieu d'un .3mf.
        $suffixeMeshyComparaison = if ($caseMeshyObjExperimental.Checked) { "_meshy_colorise" } else { "_meshy_colorise.3mf" }
        @(@{Suffixe=$suffixeMeshyComparaison}, @{Suffixe="_tripo_colorise"})
    } elseif ($fournisseur -eq "Tripo") {
        @(@{Suffixe="_colorise"})
    } elseif ($fournisseur -eq "Meshy" -and $caseMeshyObjExperimental.Checked) {
        # Variante experimentale : Meshy sort aussi un sous-dossier dans ce cas (voir
        # Coloriser-UnFichier), pas un .3mf.
        @(@{Suffixe="_colorise"})
    } else {
        @(@{Suffixe="_colorise.3mf"})
    }
    # 13/10/2026, Tomyn : sur un dossier de ~250 fichiers (image du collegue dessinateur), si
    # l'appli plante ou est fermee a mi-lot, relancer repartait de zero et redepensait des credits
    # sur des fichiers deja colorises avec succes. $reprendreLot (choix ci-dessous) fait sauter,
    # dans la boucle plus bas, tout fichier dont TOUTES les sorties attendues existent deja -
    # inutile avec l'horodatage actif, puisque chaque nom de sortie est alors forcement unique (donc
    # jamais de collision a detecter, et rien a reprendre).
    $reprendreLot = $false
    if ((-not $caseHorodatage.Checked) -and (Test-Path $dossierSortie)) {
        $collisions = @()
        foreach ($suf in $suffixesSortieActuels) {
            $collisions += @($fichiersStl | Where-Object { Test-Path (Join-Path $dossierSortie ($_.BaseName + $suf.Suffixe)) })
        }
        $collisions = @($collisions | Select-Object -Unique)
        if ($collisions.Count -gt 0) {
            $listeApercu = ($collisions | Select-Object -First 5 | ForEach-Object { $_.BaseName }) -join "`n"
            $suite = if ($collisions.Count -gt 5) { "`n... et $($collisions.Count - 5) autre(s)" } else { "" }
            $reponseBoite = Afficher-Boite "$($collisions.Count) fichier(s) de sortie existent deja dans ce dossier :`n$listeApercu$suite`n`nReprendre un lot interrompu (ignorer ces fichiers deja traites, sans redepenser de credits dessus) ou tout refaire (les ecraser) ?" "Des resultats existants ont ete trouves" "ReprendreTouteAnnuler" "Warning"
            if ($reponseBoite -eq "Yes") { $reprendreLot = $true }
            elseif ($reponseBoite -eq "No") { $reprendreLot = $false }
            else { return }
        }
    }

    if ($txtCleApi.Text) {
        (ConvertTo-SecureString $txtCleApi.Text -AsPlainText -Force) | ConvertFrom-SecureString | Set-Content $CheminCleChiffree
    }
    if ($txtCleApiTripo.Text) {
        (ConvertTo-SecureString $txtCleApiTripo.Text -AsPlainText -Force) | ConvertFrom-SecureString | Set-Content $CheminCleTripoChiffree
    }

    $txtJournal.Clear()
    $galerieResultatsMeshy.Controls.Clear()
    $galerieResultatsTripo.Controls.Clear()
    $btnLancer.Visible = $false
    $btnRelancerEchecs.Visible = $false
    $btnAnnuler.Visible = $true
    $btnAnnuler.Enabled = $true
    $btnAnnuler.Text = "Annuler"
    $script:annulationDemandee = $false

    try {
        $entetes = @{ Authorization = "Bearer $($txtCleApi.Text)" }
        New-Item -ItemType Directory -Force -Path $dossierSortie | Out-Null

        $onglets.SelectedTab = $ongletJournal
        $libelleFournisseur = if ($caseComparerFournisseurs.Checked) { "Meshy + Tripo (comparaison)" } else { $fournisseur }
        Ecrire-Journal "$($fichiersStl.Count) fichier(s) a traiter (via $libelleFournisseur), sortie dans $dossierSortie"

        $script:debutTraitement = Get-Date
        $script:totalFichiersLot = $fichiersStl.Count
        $script:indexFichierCourant = 0

        $barreProgression.Minimum = 0
        $barreProgression.Maximum = $fichiersStl.Count
        $barreProgression.Value = 0
        $barreProgression.Visible = $true
        Afficher-OverlayProgression "Colorisation en cours..."

        $reussites = 0
        $echecsCeLot = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        $interrompu = $false
        $script:creditsReelsLot = 0
        # Nombre de fichiers sautes car deja traites lors d'un lancement precedent (reprise, voir
        # $reprendreLot plus haut) - compte a part pour pouvoir l'afficher clairement dans le bilan
        # final, distinct des vraies reussites de CE lancement.
        $dejaFaits = 0
        # Compteurs par fournisseur, utilises seulement en mode comparaison (pour un bilan qui
        # distingue "Meshy a reussi mais pas Tripo" d'un echec complet sur un fichier donne - voir
        # plus bas, un fichier n'est un vrai echec de lot que si les DEUX ont rate).
        $reussitesMeshy = 0
        $reussitesTripo = 0
        $echecsMeshy = 0
        $echecsTripo = 0
        foreach ($fichier in $fichiersStl) {
            $script:indexFichierCourant++
            $barreProgression.Value = $script:indexFichierCourant - 1  # avant traitement : montre ce qui est deja fini
            $etaOverlayTexte = Obtenir-TexteEtaLot ((Get-Date) - $script:debutTraitement).TotalSeconds ($script:indexFichierCourant - 1) $script:totalFichiersLot
            $creditsOverlayTexte = " - $([Math]::Round($script:creditsReelsLot, 1)) credit(s)"
            Mettre-A-Jour-OverlayProgression ([int](($script:indexFichierCourant - 1) / $script:totalFichiersLot * 100)) "Fichier $($script:indexFichierCourant) / $($script:totalFichiersLot) : $($fichier.Name)$etaOverlayTexte" $creditsOverlayTexte
            if ($script:annulationDemandee) {
                Ecrire-Journal "`n=== Annule par l'utilisateur (fichiers restants non traites) ==="
                $interrompu = $true
                break
            }
            if ($script:pauseDemandeeColoriser) {
                Ecrire-Journal "  (En pause - clique sur Reprendre dans la fenetre de progression pour continuer)"
                while ($script:pauseDemandeeColoriser -and -not $script:annulationDemandee) {
                    Start-Sleep -Milliseconds 200
                    [System.Windows.Forms.Application]::DoEvents()
                }
                if ($script:annulationDemandee) {
                    Ecrire-Journal "`n=== Annule par l'utilisateur (fichiers restants non traites) ==="
                    $interrompu = $true
                    break
                }
                Ecrire-Journal "  (Reprise du lot)"
            }
            if ($reprendreLot) {
                $sortiesAttendues = @($suffixesSortieActuels | ForEach-Object { Join-Path $dossierSortie ($fichier.BaseName + $_.Suffixe) })
                if (@($sortiesAttendues | Where-Object { Test-Path $_ }).Count -eq $sortiesAttendues.Count) {
                    Ecrire-Journal "  - $($fichier.Name) : deja traite (reprise du lot), ignore - 0 credit consomme."
                    $dejaFaits++
                    $reussites++
                    if ($caseComparerFournisseurs.Checked) { $reussitesMeshy++; $reussitesTripo++ }
                    continue
                }
            }
            # Reverification periodique du solde EN COURS de lot (21/10/2026, idee en passant
            # validee "2-4" - jusqu'ici le solde n'etait verifie qu'UNE FOIS avant de lancer tout le
            # lot ; sur un dossier de 250 fichiers payes par le collegue dessinateur de Tomyn, un
            # derapage du cout reel ne se voyait qu'en echouant fichier par fichier une fois le
            # solde epuise, sans prevenir avant). Seulement tous les $INTERVALLE_VERIF_SOLDE_LOT
            # fichiers (pas a chaque fichier - un appel reseau par fichier serait inutile et plus
            # lent). Compare au cout estime des fichiers RESTANTS, pas tout le lot a nouveau - ce
            # qui a deja ete depense est depense.
            # 21/10/2026 (meme session) : etendu a Tripo. Verifier-CleEtSoldeTripo pointait deja
            # vers le bon endpoint documente ("/account/balance", corrige un peu plus tot le meme
            # jour) mais n'etait encore appelee nulle part - le vieux souci de blocage UI au clic sur
            # "Lancer" venait du tout premier endpoint devine (jamais confirme), pas d'un probleme
            # structurel : Verifier-CleEtSoldeTripo partage exactement le meme squelette
            # try/catch + Invoquer-AvecReessaiReseau + TimeoutSec que Verifier-CleEtSolde (Meshy),
            # deja en production sans souci. Pas de test reseau live possible ici (pas de cle Tripo
            # utilisable a disposition) - a surveiller au premier vrai lot Tripo de Tomyn.
            $utiliseMeshyIci = ($fournisseur -eq "Meshy" -or $caseComparerFournisseurs.Checked)
            $utiliseTripoIci = ($fournisseur -eq "Tripo" -or $caseComparerFournisseurs.Checked)
            if (($utiliseMeshyIci -or $utiliseTripoIci) -and $script:indexFichierCourant -gt 1 -and (($script:indexFichierCourant - 1) % $INTERVALLE_VERIF_SOLDE_LOT -eq 0)) {
                $fichiersRestants = $fichiersStl.Count - $script:indexFichierCourant + 1
                $avertissementsSolde = @()
                if ($utiliseMeshyIci) {
                    $verifSoldeEnCours = Verifier-CleEtSolde $txtCleApi.Text
                    if ($verifSoldeEnCours.Statut -eq "valide") {
                        $coutEstimeRestant = $fichiersRestants * $CREDITS_ESTIMES_PAR_FICHIER
                        if ($verifSoldeEnCours.Solde -lt $coutEstimeRestant) {
                            $avertissementsSolde += "Meshy : solde restant $($verifSoldeEnCours.Solde) credits, cout estime ~$coutEstimeRestant credits pour les $fichiersRestants fichier(s) restant(s)."
                        }
                    }
                    # "invalide"/"inconnu" : jamais bloquant ici (voir note plus bas).
                }
                if ($utiliseTripoIci) {
                    $verifSoldeTripoEnCours = Verifier-CleEtSoldeTripo $txtCleApiTripo.Text
                    if ($verifSoldeTripoEnCours.Statut -eq "valide") {
                        $coutEstimeRestantTripo = $fichiersRestants * $CREDITS_ESTIMES_PAR_FICHIER_TRIPO
                        if ($verifSoldeTripoEnCours.Solde -lt $coutEstimeRestantTripo) {
                            $avertissementsSolde += "Tripo : solde restant $($verifSoldeTripoEnCours.Solde) credits, cout estime ~$coutEstimeRestantTripo credits pour les $fichiersRestants fichier(s) restant(s)."
                        }
                    }
                }
                if ($avertissementsSolde.Count -gt 0) {
                    # Overlay masque AVANT la boite - sinon, etant TopMost, il passerait devant et
                    # empecherait de cliquer sur Oui/Non (meme souci deja corrige plus bas pour la
                    # boite d'erreur).
                    Masquer-OverlayProgression
                    $texteAvertissements = ($avertissementsSolde -join "`n")
                    $reponseSoldeEnCours = Afficher-Boite "Apres $($script:indexFichierCourant - 1) fichier(s) :`n$texteAvertissements`n`nContinuer le lot quand meme ?" "Solde potentiellement insuffisant en cours de lot" "YesNo" "Warning"
                    if ($reponseSoldeEnCours -ne "Yes") {
                        Ecrire-Journal "`n=== Annule par l'utilisateur (solde juge insuffisant apres $($script:indexFichierCourant - 1) fichier(s)) ==="
                        $interrompu = $true
                        break
                    }
                    # Reaffiche l'overlay (juste .Show(), pas Afficher-OverlayProgression qui
                    # remettrait le pourcentage et les boutons Pause/Annuler a zero pour rien - on
                    # reprend exactement ou on en etait).
                    $overlayProgression.Show()
                }
                # "invalide"/"inconnu" (cle devenue invalide en cours de route, ou simple souci
                # reseau transitoire malgre le reessai deja tente dans Verifier-CleEtSolde*) : jamais
                # bloquant ici, contrairement a la verification initiale avant lancement -
                # interrompre un lot de 250 fichiers a cause d'UN controle de solde rate serait pire
                # que le probleme que ca essaie d'eviter. Le vrai pipeline s'en apercevra de
                # lui-meme si la cle est vraiment devenue invalide (chaque fichier echouera alors
                # avec un message HTTP clair).
            }
            Afficher-ProgressionEnCours "Retexture en cours..."
            try {
                # 20/10/2026, Tomyn : conversion AVANT l'aiguillage Meshy/Tripo (pas dans
                # Coloriser-UnFichier/-UnFichierTripo directement) pour que les deux beneficient
                # automatiquement, y compris en mode comparaison - voir Convertir-3MFVersSTL.
                # $fichier reassigne au .stl converti (meme BaseName que l'original, garanti par
                # Convertir-3MFVersSTL) : le reste de la boucle n'a besoin d'aucun autre changement,
                # noms de sortie et historique compris.
                if ($fichier.Extension.ToLower() -eq ".3mf") {
                    Ecrire-Journal "  $($fichier.Name) : .3mf non colorise, extraction du maillage et conversion en .stl (Meshy ne l'accepte pas directement en entree)..."
                    $resultatConversion = Convertir-3MFVersSTL $fichier
                    Ecrire-Journal "  -> $($resultatConversion.NbTriangles) triangle(s) extrait(s) depuis $($resultatConversion.NbObjets) objet(s) du .3mf."
                    $fichier = $resultatConversion.Fichier
                }
                if ($caseComparerFournisseurs.Checked) {
                    # Les deux fournisseurs sont lances l'un apres l'autre (pas de vrai parallelisme
                    # reseau ici - garder l'appli mono-thread simple plutot que d'introduire des
                    # runspaces pour gagner du temps d'attente), chacun avec son propre try/catch :
                    # l'echec de l'un ne doit jamais empecher de recuperer le resultat de l'autre.
                    $reussiMeshy = $false
                    $reussiTripo = $false
                    try {
                        $script:creditsReelsLot += Coloriser-UnFichier $fichier $txtPrompt.Text $entetes $dossierSortie ([int]$numCouleurs.Value) $caseHorodatage.Checked $galerieResultatsMeshy "_meshy" $caseMeshyObjExperimental.Checked ([double]$assombrirTexture.Value) ([int]$numTriangles.Value) $caseSmartTopology.Checked (Obtenir-GeometryResolutionChoisie) (Obtenir-TextureResolutionChoisie) $caseReparationParois.Checked ([double]$numTailleImpression.Value)
                        $reussiMeshy = $true
                        $reussitesMeshy++
                    } catch {
                        if ("$_" -eq $script:ANNULATION_MARQUEUR) { throw }
                        Ecrire-Journal "  ECHEC Meshy sur $($fichier.Name) : $_"
                        $echecsMeshy++
                    }
                    try {
                        $script:creditsReelsLot += Coloriser-UnFichierTripo $fichier $txtPrompt.Text $txtCleApiTripo.Text $dossierSortie $caseHorodatage.Checked $galerieResultatsTripo "_tripo" ([int]$numTriangles.Value) ([double]$numTailleImpression.Value)
                        $reussiTripo = $true
                        $reussitesTripo++
                    } catch {
                        if ("$_" -eq $script:ANNULATION_MARQUEUR) { throw }
                        Ecrire-Journal "  ECHEC Tripo sur $($fichier.Name) : $_"
                        $echecsTripo++
                    }
                    if ($reussiMeshy -or $reussiTripo) { $reussites++ } else { $echecsCeLot.Add($fichier) }
                } else {
                    if ($fournisseur -eq "Meshy") {
                        $script:creditsReelsLot += Coloriser-UnFichier $fichier $txtPrompt.Text $entetes $dossierSortie ([int]$numCouleurs.Value) $caseHorodatage.Checked $galerieResultatsMeshy "" $caseMeshyObjExperimental.Checked ([double]$assombrirTexture.Value) ([int]$numTriangles.Value) $caseSmartTopology.Checked (Obtenir-GeometryResolutionChoisie) (Obtenir-TextureResolutionChoisie) $caseReparationParois.Checked ([double]$numTailleImpression.Value)
                    } else {
                        $script:creditsReelsLot += Coloriser-UnFichierTripo $fichier $txtPrompt.Text $txtCleApiTripo.Text $dossierSortie $caseHorodatage.Checked $galerieResultatsTripo "" ([int]$numTriangles.Value) ([double]$numTailleImpression.Value)
                    }
                    $reussites++
                }
            } catch {
                if ("$_" -eq $script:ANNULATION_MARQUEUR) {
                    Ecrire-Journal "`n=== Annule par l'utilisateur (en cours de traitement de $($fichier.Name)) ==="
                    $interrompu = $true
                    break
                }
                Ecrire-Journal "  ECHEC sur $($fichier.Name) : $_"
                $echecsCeLot.Add($fichier)
            }
        }

        $script:dernierLotEchecs = @($echecsCeLot)
        $echecs = $echecsCeLot.Count

        # Barre de progression de l'overlay forcee a 100% puis disparition automatique (16/10/2026,
        # Tomyn, retour sur Melange-Couleurs mais meme recette ici : "il faudrait qu'elle disparaisse
        # au bout d'un certain moment ... au bout de 5 ou 6 secondes des qu'elle est a 100% elle
        # disparait d'elle-meme") - sauf si annule, ou l'overlay doit disparaitre tout de suite.
        if (-not $interrompu) {
            Mettre-A-Jour-OverlayProgression 100
            Masquer-OverlayProgressionApresDelai 5
        } else {
            Masquer-OverlayProgression
        }

        try {
            # En mode comparaison, "fichiers"/"reussites"/"echecs" comptent les deux generations
            # tentees par fichier (2x), pour que la colonne Credits de l'historique reste coherente
            # avec le cumul reellement consomme sur les deux plateformes - le detail par fournisseur
            # reste visible dans le journal de ce lot, pas dans cette ligne recapitulative globale.
            if ($caseComparerFournisseurs.Checked) {
                $ligneHistorique = "$(Get-Date -Format 'dd/MM/yyyy HH:mm');$($fichiersStl.Count * 2);$($reussitesMeshy + $reussitesTripo);$($echecsMeshy + $echecsTripo);$script:creditsReelsLot"
            } else {
                $ligneHistorique = "$(Get-Date -Format 'dd/MM/yyyy HH:mm');$($fichiersStl.Count);$reussites;$echecs;$script:creditsReelsLot"
            }
            Add-Content -Path $CheminHistorique -Value $ligneHistorique
        } catch { }  # pas grave si l'ecriture de l'historique echoue, ca ne doit jamais bloquer le vrai traitement

        # 13/10/2026 : texte de reprise ajoute aux deux bilans ci-dessous seulement si des fichiers
        # ont vraiment ete sautes (reprise d'un lot interrompu) - sinon rien ne change par rapport
        # a avant.
        $texteDejaFaits = if ($dejaFaits -gt 0) { " (dont $dejaFaits deja traite(s) avant, repris sans redepenser de credits)" } else { "" }
        Ecrire-Journal ""
        if ($caseComparerFournisseurs.Checked) {
            Ecrire-Journal "=== Bilan : Meshy $reussitesMeshy/$($fichiersStl.Count) reussite(s), Tripo $reussitesTripo/$($fichiersStl.Count) reussite(s)$texteDejaFaits$(if ($interrompu) { ', traitement interrompu' }) ==="
        } else {
            Ecrire-Journal "=== Bilan : $reussites reussite(s), $echecs echec(s)$texteDejaFaits$(if ($interrompu) { ', traitement interrompu' }) ==="
        }
        $onglets.SelectedTab = $ongletResultats
        $messageFin = if ($caseComparerFournisseurs.Checked) {
            if ($interrompu) { "Annule : Meshy $reussitesMeshy, Tripo $reussitesTripo reussite(s) avant l'arret.$texteDejaFaits" }
            else { "Termine : Meshy $reussitesMeshy/$($fichiersStl.Count), Tripo $reussitesTripo/$($fichiersStl.Count) reussite(s).$texteDejaFaits" }
        } elseif ($interrompu) { "Annule : $reussites reussite(s) avant l'arret.$texteDejaFaits" } else { "Termine : $reussites reussite(s), $echecs echec(s).$texteDejaFaits" }
        try {
            $script:notifIcon.ShowBalloonTip(6000, "Colorisation terminee", $messageFin, [System.Windows.Forms.ToolTipIcon]::Info)
        } catch { }  # la notification n'est qu'un plus, jamais bloquant si elle echoue
        Afficher-Boite $messageFin "Colorisation - fin du traitement" | Out-Null
    } catch {
        Ecrire-Journal "ERREUR : $_"
        # Overlay masque AVANT la boite d'erreur - sinon, etant TopMost, il passerait devant et
        # empecherait de cliquer sur OK (meme souci que celui signale par Tomyn sur l'avertissement
        # de couverture dans Melange-Couleurs, 16/10/2026).
        Masquer-OverlayProgression
        Afficher-Boite "$_" "Erreur" "OK" "Error" | Out-Null
    } finally {
        $btnLancer.Visible = $true
        $btnAnnuler.Visible = $false
        # Le bouton "Relancer les echecs" ne reapparait que s'il y a vraiment eu des echecs -
        # evite de proposer un relancement qui n'aurait rien a faire.
        $btnRelancerEchecs.Visible = ($script:dernierLotEchecs.Count -gt 0)
        $script:annulationDemandee = $false
        $script:debutTraitement = $null
        $barreProgression.Visible = $false
        Masquer-OverlayProgression
        Mettre-A-Jour-Estimation  # restaure l'affichage du cout estime, a la place du temps ecoule
    }
}

$btnHistorique.Add_Click({ Afficher-FenetreHistorique })
$btnHistoriqueFichiers.Add_Click({ Afficher-FenetreHistoriqueFichiers })

$btnAnnuler.Add_Click({
    $script:annulationDemandee = $true
    $btnAnnuler.Enabled = $false
    $btnAnnuler.Text = "Annulation..."
})

$btnLancer.Add_Click({
    # Ne retraite que les fichiers dont la case "Inclure" est cochee - permet d'exclure un
    # fichier precis (ex: une variante en double) sans changer de dossier ni de selection.
    $fichiersInclus = @($script:fichiersAtraiter | Where-Object {
        $case = $script:casesACocher[$_.FullName]
        $case -eq $null -or $case.Checked
    })
    Lancer-Traitement $fichiersInclus
})

$btnRelancerEchecs.Add_Click({
    Lancer-Traitement $script:dernierLotEchecs
})

# ============================== APPLICATION DU THEME ==============================
# Passe finale (10/10/2026) : tous les controles existent deja a ce stade, on les restyle d'un
# coup plutot que d'eparpiller des lignes de couleur partout dans leur code de creation plus haut
# - plus facile a retoucher d'un bloc si Tomyn veut ajuster une teinte plus tard.

# Boutons : un seul role par bouton, voir Rendre-BoutonPlat plus haut pour le detail de chaque role.
Rendre-BoutonPlat $btnVoirCle "secondaire"
Rendre-BoutonPlat $btnVoirCleTripo "secondaire"
Rendre-BoutonPlat $btnParcourir "secondaire"
Rendre-BoutonPlat $btnChoisirFichiers "secondaire"
Rendre-BoutonPlat $btnActualiser "secondaire"
Rendre-BoutonPlat $btnParcourirSortie "secondaire"
Rendre-BoutonPlat $btnOuvrirSortie "secondaire"
Rendre-BoutonPlat $btnToutCocher "secondaire"
Rendre-BoutonPlat $btnToutDecocher "secondaire"
Rendre-BoutonPlat $btnHistorique "discret"
Rendre-BoutonPlat $btnEnregistrerJournal "discret"
Rendre-BoutonPlat $btnLancer "principal"
Rendre-BoutonPlat $btnAnnuler "danger"
Rendre-BoutonPlat $btnRelancerEchecs "chaud"

Definir-CouleurBarreProgression $barreProgression $THEME.AccentPrincipal

# Cases a cocher secondaires : texte plus discret (coherent avec l'app Android)
foreach ($case in @($caseComparerFournisseurs, $caseMeshyObjExperimental, $caseHorodatage)) {
    $case.ForeColor = $THEME.TexteSecondaire
}

# Onglets et panneaux : fond blanc (Surface) plutot que le gris Control par defaut
foreach ($page in @($ongletDepart, $ongletResultats, $ongletJournal)) {
    $page.BackColor = $THEME.Surface
}

# Niveau 1 du relookage (10/10/2026) : les trois widgets restes 100% natifs Windows malgre la
# bannerie et les boutons plats - ComboBox (listes), TabControl (onglets), NumericUpDown (compteurs).
Rendre-ComboBoxPlate $menuFournisseur
Rendre-ComboBoxPlate $menuCategorie
Rendre-ComboBoxPlate $menuPrompt
Rendre-OngletsPlats $onglets
$barreOutilsDepart.BackColor = $THEME.Surface
$galerieDepart.BackColor = $THEME.Surface
$galerieResultatsMeshy.BackColor = $THEME.Surface
$galerieResultatsTripo.BackColor = $THEME.Surface
$txtJournal.BackColor = $THEME.Surface
$txtJournal.ForeColor = $THEME.Texte

# En-tetes de colonnes resultats (Meshy / Tripo) : bande violette au lieu du gris SystemColors
# ControlLight d'origine - repris en comptant que Creer-ColonneResultats cree $entete en premier
# enfant de $panneauColonne (voir plus haut), donc toujours accessible via .Controls[0].
foreach ($colonne in @($colonneMeshy, $colonneTripo)) {
    $entete = $colonne.Panneau.Controls[0]
    $entete.BackColor = $THEME.AccentPrincipal
    $entete.ForeColor = [System.Drawing.Color]::White
}

# Ferme l'ecran de lancement juste avant d'afficher le formulaire principal - tout le travail de
# construction des controles ci-dessus a eu le temps de se faire pendant que le splash etait
# affiche, donc la transition se fait sans trou visible entre les deux fenetres.
try { $splash.Close(); $splash.Dispose() } catch { }

# Mode sombre : applique la preference enregistree (16/10/2026) - APRES la construction complete
# de l'interface (tous les controles existent, y compris $overlayProgression) mais avant
# d'afficher la fenetre, pour que Tomyn ne voie jamais un "flash" clair avant le bascule.
try {
    $cheminPrefModeSombre = Obtenir-CheminPreferenceModeSombre
    if (Test-Path $cheminPrefModeSombre) {
        $prefModeSombre = Get-Content $cheminPrefModeSombre -Raw | ConvertFrom-Json
        if ($prefModeSombre.ModeSombre) { Basculer-ModeSombre $true }
    }
} catch { }

# Correctif du 10/10/2026, troisieme essai (signale par Tomyn, captures a l'appui : la fenetre
# sortait de l'ecran par le bas - "on voit pas tout", et pendant la colorisation "on voit les
# premieres lignes d'avancement mais pas la suite"). Les deux essais precedents calculaient une
# taille "sur mesure" a partir de la zone de travail de l'ecran (Screen.WorkingArea) puis
# l'appliquaient a la fenetre a differents moments du script - sans succes ("toujours pareil"
# d'apres Tomyn au 2e essai), tres probablement a cause de la mise a l'echelle DPI de Windows (un
# ecran regle a 125%/150% par exemple) qui peut re-agrandir une taille de fenetre fixee a la main
# apres coup, ou fausser le calcul de la zone utile reelle - sujet casse-tete classique en WinForms
# et difficile a diagnostiquer a l'aveugle, sans Windows sous la main pour voir ce qui se passe
# vraiment.
#
# Plutot que de continuer a deviner une taille "a la main", la fenetre demarre maintenant carrement
# maximisee : c'est Windows lui-meme qui calcule alors la bonne taille/position (barre des taches,
# mise a l'echelle DPI, tout est deja gere nativement par l'OS pour une maximisation, contrairement
# a un calcul fait depuis le script) - la meme mecanique fiable que n'importe quelle appli Windows
# qui s'ouvre en plein ecran. La fenetre reste redimensionnable ensuite (bouton "Restaurer" dans la
# barre de titre, ou double-clic dessus) si Tomyn préfère une fenetre plus petite ensuite ;
# $onglets.Anchor (juste au-dessus) etait deja prevu pour suivre ce genre de redimensionnement.
# Raccourcis clavier (16/10/2026, demande de Tomyn) : Ctrl+Entree pour lancer directement sans
# aller chercher le bouton a la souris, et Echap pour annuler un traitement en cours. On ne
# declenche que si le bouton vise est reellement visible et actif - sinon KeyPreview ferait
# "sauter" sur un bouton cache/desactive sans effet utile ni retour visuel pour Tomyn.
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        if ($btnLancer.Visible -and $btnLancer.Enabled) {
            $e.Handled = $true
            $btnLancer.PerformClick()
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        if ($btnAnnuler.Visible -and $btnAnnuler.Enabled) {
            $e.Handled = $true
            $btnAnnuler.PerformClick()
        } elseif ($overlayProgression.Visible -and $btnAnnulerOverlay.Visible -and $btnAnnulerOverlay.Enabled) {
            $e.Handled = $true
            $btnAnnulerOverlay.PerformClick()
        }
    }
}.GetNewClosure())

$form.WindowState = "Maximized"

[void]$form.ShowDialog()
