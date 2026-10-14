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
$TailleMiniature = 220
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
# Rectifie le 07/10/2026 : premiere lecture du tableau de bord Meshy par Tomyn mal interpretee
# (25+15+16 = 56), le vrai detail confirme juste apres est Retexture = 10 credits et Multi-Color
# Print = 10 credits, soit 20 au total - l'estimation d'origine etait donc la bonne.
$CREDITS_ESTIMES_PAR_FICHIER = 20
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
$EXTENSIONS_IMAGES = @(".jpg", ".jpeg", ".png")
$EXTENSIONS_SUPPORTEES = $EXTENSIONS_MODELES_3D + $EXTENSIONS_IMAGES
# Cout de l'etape Image to 3D en maillage seul (should_texture=false, modele par defaut
# meshy-7.1/meshy-6) - confirme sur la doc tarifaire officielle Meshy le 08/10/2026. S'ajoute
# AVANT les credits de colorisation habituels (Retexture +/- Multi-Color Print) quand la source
# est une image plutot qu'un modele 3D deja existant.
$CREDITS_ESTIMES_IMAGE_VERS_3D = 20

# ============================== THEME "ATELIER" ==============================
# Ajoute le 10/10/2026 (demande de Tomyn : l'appli "faisait trop fenetre Windows", trop grise et
# austere). Palette violette reprise de l'appli Android ColoriserSTL (meme outil, deux
# plateformes) pour une identite visuelle coherente entre les deux. PAS TESTE PAR CLAUDE (meme
# limite que le reste du fichier, voir l'en-tete) : aucun Windows/PowerShell disponible ici pour
# verifier le rendu reel (notamment Creer-IconeSpool et le SendMessage de la barre de
# progression, les deux morceaux les plus a risque de ce theme).

$THEME = @{
    FondApp            = [System.Drawing.Color]::FromArgb(0xEE, 0xF1, 0xF3)   # gris-bleu clair (plan de travail)
    FondBanniere       = [System.Drawing.Color]::FromArgb(0x45, 0x27, 0xA0)   # violet fonce (accent_violet_fonce, cote Android)
    Surface            = [System.Drawing.Color]::White
    AccentPrincipal    = [System.Drawing.Color]::FromArgb(0x7C, 0x4D, 0xFF)   # violet (accent_violet, cote Android)
    AccentPrincipalTxt = [System.Drawing.Color]::White
    AccentDanger       = [System.Drawing.Color]::FromArgb(0xD3, 0x2F, 0x2F)
    AccentChaud        = [System.Drawing.Color]::FromArgb(0xFF, 0x5A, 0x1F)   # orange nozzle - relance/alerte douce
    Texte              = [System.Drawing.Color]::FromArgb(0x1A, 0x1A, 0x1A)
    TexteSecondaire    = [System.Drawing.Color]::FromArgb(0x5C, 0x5C, 0x5C)
    Bordure            = [System.Drawing.Color]::FromArgb(0xD8, 0xDA, 0xDD)
    HauteurBanniere    = 56
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

function Definir-CouleurBarreProgression($barre, [System.Drawing.Color]$couleur) {
    try {
        $bgr = [IntPtr]($couleur.B -shl 16 -bor $couleur.G -shl 8 -bor $couleur.R)
        [void][NativeMethodsTheme]::SendMessage($barre.Handle, 0x409, [IntPtr]0, $bgr)   # PBM_SETBARCOLOR
        [void][NativeMethodsTheme]::SendMessage($barre.Handle, 0x2001, [IntPtr]0, $bgr)  # PBM_SETBKCOLOR (fond sombre -> clair, sinon la barre garde un fond vert/bleu derriere l'accent)
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
            $bouton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xF1, 0xEC, 0xFF)
        }
    }
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

    $rayon = 10
    $diametre = $rayon * 2
    $largeurCarte = $panneau.Width
    $hauteurCarte = $panneau.Height
    $cheminArrondi = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cheminArrondi.AddArc(0, 0, $diametre, $diametre, 180, 90)
    $cheminArrondi.AddArc(($largeurCarte - $diametre - 1), 0, $diametre, $diametre, 270, 90)
    $cheminArrondi.AddArc(($largeurCarte - $diametre - 1), ($hauteurCarte - $diametre - 1), $diametre, $diametre, 0, 90)
    $cheminArrondi.AddArc(0, ($hauteurCarte - $diametre - 1), $diametre, $diametre, 90, 90)
    $cheminArrondi.CloseFigure()
    $panneau.Region = New-Object System.Drawing.Region($cheminArrondi)

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
    return $fenetre.ShowDialog($form)
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
$form.Size = New-Object System.Drawing.Size(1000, (1080 + $THEME.HauteurBanniere))
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
Ajouter-Label "Triangles vises (image uniquement, 100-300000) :" 15 ($yActuel + 32)
$numTriangles = Creer-SelecteurNumerique 90 24
$numTriangles.Location = New-Object System.Drawing.Point(400, ($yActuel + 28))
$numTriangles.Minimum = 100
$numTriangles.Maximum = 300000
$numTriangles.Increment = 1000
$numTriangles.Value = 30000
$form.Controls.Add($numTriangles)
$yActuel += 30

# +44 avant l'en-tete (et pas directement a $yActuel) : a ce stade $yActuel ne vaut que +30 par
# rapport a la ligne "Nombre de couleurs", alors que le champ "Triangles vises" juste au-dessus
# occupe jusqu'a +52 sur cette meme base (champ a +28, hauteur 24). Les +24 initiaux evitaient
# juste que l'en-tete "Lancement" chevauche ce champ ; portes a +44 (14/10/2026) pour laisser
# aussi la place au panneau de fond de la section "Style et couleurs" (voir Ajouter-PanneauSection
# plus bas) de se refermer proprement sous ce champ avant que celui de "Lancement" ne commence -
# sans cette marge supplementaire, les deux panneaux de fond se chevaucheraient legerement.
$yActuel += 44
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

$btnEnregistrerJournal = New-Object System.Windows.Forms.Button
$btnEnregistrerJournal.Text = "Enreg. journal"
$btnEnregistrerJournal.Location = New-Object System.Drawing.Point(805, ($yActuel - 2))
$btnEnregistrerJournal.Size = New-Object System.Drawing.Size(85, 22)
$form.Controls.Add($btnEnregistrerJournal)
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
$yActuel += 22

$barreProgression = New-Object System.Windows.Forms.ProgressBar
$barreProgression.Location = New-Object System.Drawing.Point(15, $yActuel)
$barreProgression.Size = New-Object System.Drawing.Size(875, 12)
$barreProgression.Style = "Continuous"
$barreProgression.Visible = $false
$form.Controls.Add($barreProgression)
$yActuel += 17
$yFinBlocLancement = $yActuel

# Panneaux de fond "carte" derriere chaque section : essayes le 14/10/2026, retires le meme jour
# suite au retour de Tomyn ("c'est encore pire, toujours ces rectangles blancs sur un fond gris" -
# 2e avis negatif de suite sur cette piste, pas la peine d'insister). Ajouter-PanneauSection et
# Obtenir-BasReelSection restent definies plus haut mais ne sont plus appelees ici - fond uni du
# formulaire (THEME.FondApp) derriere les sections, seuls les bandeaux d'en-tete (accent + titre)
# restent comme marqueurs visuels de section.

# --- Onglets : galerie de depart / galerie de resultats / avancement ---
$onglets = New-Object System.Windows.Forms.TabControl
$onglets.Location = New-Object System.Drawing.Point(15, $yActuel)
$onglets.Size = New-Object System.Drawing.Size(955, 640)
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

function Ajouter-Vignette($galerie, $cheminFichier, $imageDejaFournie = $null, $avecCaseACocher = $false, [string]$texteDescription = "") {
    # 13/10/2026 : carte plus haute seulement quand une description MakerWorld est fournie (voir
    # Generer-DescriptionMakerWorld plus haut), pour garder la galerie de depart (pas de
    # description) a sa taille habituelle.
    $hauteurBoutonDescription = if ($texteDescription) { 26 } else { 0 }
    $panneau = New-Object System.Windows.Forms.Panel
    $panneau.Size = New-Object System.Drawing.Size(($TailleMiniature + 16), ($TailleMiniature + 84 + $hauteurBoutonDescription))
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
    $rayon = 10
    $cheminArrondi = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diametre = $rayon * 2
    $largeurCarte = $TailleMiniature + 16
    $hauteurCarte = $TailleMiniature + 84 + $hauteurBoutonDescription
    $cheminArrondi.AddArc(0, 0, $diametre, $diametre, 180, 90)
    $cheminArrondi.AddArc(($largeurCarte - $diametre - 1), 0, $diametre, $diametre, 270, 90)
    $cheminArrondi.AddArc(($largeurCarte - $diametre - 1), ($hauteurCarte - $diametre - 1), $diametre, $diametre, 0, 90)
    $cheminArrondi.AddArc(0, ($hauteurCarte - $diametre - 1), $diametre, $diametre, 90, 90)
    $cheminArrondi.CloseFigure()
    $panneau.Region = New-Object System.Drawing.Region($cheminArrondi)

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
    if ($texteDescription) {
        $btnCopierDescription = New-Object System.Windows.Forms.Button
        $btnCopierDescription.Text = "Copier description"
        $btnCopierDescription.Size = New-Object System.Drawing.Size(($TailleMiniature + 6), 22)
        $btnCopierDescription.Location = New-Object System.Drawing.Point(5, ($TailleMiniature + 32 + 36))
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
    $texteSurcoutImages = if ($nbImages -gt 0) { " + ~$($nbImages * $CREDITS_ESTIMES_IMAGE_VERS_3D) credits Meshy pour generer le maillage des $nbImages image(s) avant colorisation" } else { "" }

    if ($inclus.Count -eq 0) {
        $txtEstimationCout.Text = ""
    } elseif ($caseComparerFournisseurs.Checked) {
        # Chiffre Tripo desormais confirme (voir $CREDITS_ESTIMES_PAR_FICHIER_TRIPO) - echelle de
        # credits separee de celle de Meshy, donc on les additionne mais sans pretendre que c'est
        # la meme "unite" de credit d'un fournisseur a l'autre.
        $totalTripo = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER_TRIPO
        if ($caseMeshyObjExperimental.Checked) {
            $totalMeshyObj = $inclus.Count * $CREDITS_ESTIMES_RETEXTURE_SEULE
            $txtEstimationCout.Text = "Cout estime : ~$totalMeshyObj credits Meshy (Retexture seule, sans Multi-Color Print) + ~$totalTripo credits Tripo ($($inclus.Count) fichier(s) chacun, deux echelles de credits differentes)$texteSurcoutImages"
        } else {
            $totalMeshy = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER
            $txtEstimationCout.Text = "Cout estime : ~$totalMeshy credits Meshy + ~$totalTripo credits Tripo ($($inclus.Count) fichier(s) chacun, deux echelles de credits differentes)$texteSurcoutImages"
        }
    } elseif ($menuFournisseur.SelectedItem -eq "Meshy" -and $caseMeshyObjExperimental.Checked) {
        # Une seule etape facturee (Retexture) au lieu de deux (Retexture + Multi-Color Print) -
        # economise le cout du Multi-Color Print (confirme a 10 credits le 07/10/2026).
        $totalMeshyObj = $inclus.Count * $CREDITS_ESTIMES_RETEXTURE_SEULE
        $txtEstimationCout.Text = "Cout estime : ~$totalMeshyObj credits ($($inclus.Count) fichier(s) x $CREDITS_ESTIMES_RETEXTURE_SEULE, Retexture seule - sans Multi-Color Print)$texteSurcoutImages"
    } elseif ($menuFournisseur.SelectedItem -eq "Tripo") {
        $totalTripo = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER_TRIPO
        $txtEstimationCout.Text = "Cout estime : ~$totalTripo credits Tripo ($($inclus.Count) fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER_TRIPO)$(if ($nbImages -gt 0) { ' - ATTENTION : les images ne sont pas prises en charge par Tripo, elles echoueront' })"
    } else {
        $total = $inclus.Count * $CREDITS_ESTIMES_PAR_FICHIER
        $txtEstimationCout.Text = "Cout estime : ~$total credits ($($inclus.Count) fichier(s) x $CREDITS_ESTIMES_PAR_FICHIER, estimation empirique)$texteSurcoutImages"
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
    $dialogue.Filter = "Fichiers 3D et images (*.stl;*.obj;*.fbx;*.glb;*.gltf;*.jpg;*.jpeg;*.png)|*.stl;*.obj;*.fbx;*.glb;*.gltf;*.jpg;*.jpeg;*.png"
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

function Afficher-ProgressionEnCours($etapeTexte) {
    if ($script:debutTraitement -eq $null) { return }
    $ecoule = (Get-Date) - $script:debutTraitement
    $ecouleTexte = "{0:00}:{1:00}" -f [int]$ecoule.TotalMinutes, $ecoule.Seconds
    $txtEstimationCout.Text = "Fichier $($script:indexFichierCourant)/$($script:totalFichiersLot) - ecoule : $ecouleTexte - $etapeTexte"
}

function Attendre-Tache($UrlTache, $Entetes, $Libelle) {
    $debut = Get-Date
    while ($true) {
        if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
        if (((Get-Date) - $debut).TotalSeconds -gt $TimeoutTacheSecondes) {
            throw "$Libelle : pas de reponse apres $($TimeoutTacheSecondes / 60) min"
        }
        $tache = Invoke-RestMethod -Uri $UrlTache -Headers $Entetes -Method Get
        switch ($tache.status) {
            "SUCCEEDED" { return $tache }
            "FAILED"    { throw "$Libelle a echoue : $($tache.task_error.message)" }
            "CANCELED"  { throw "$Libelle a ete annulee" }
            default     { Ecrire-Journal "    $Libelle : $($tache.status) ($($tache.progress)%)..." }
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
        $reponse = Invoke-RestMethod -Uri $UrlTache -Headers $Entetes -Method Get -TimeoutSec 15
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
        }
        for ($i = 0; $i -lt $IntervallePollSecondes; $i++) {
            if ($script:annulationDemandee) { throw $script:ANNULATION_MARQUEUR }
            Afficher-ProgressionEnCours "$Libelle en cours..."
            Start-Sleep -Seconds 1
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Coloriser-UnFichierTripo($FichierStl, $Prompt, $CleApi, $DossierSortie, $AvecHorodatage, $GalerieCible, $SuffixeFournisseur = "") {
    Ecrire-Journal ""
    Ecrire-Journal "=== $($FichierStl.Name) (via Tripo) ==="

    # Image -> STL (08/10/2026) : pas encore pris en charge cote Tripo dans cette version, Meshy
    # seulement pour le moment - erreur explicite plutot que de laisser Tripo echouer sur un type
    # de fichier qu'il ne comprend pas avec un message API confus.
    if ($FichierStl.Extension.ToLower() -in $EXTENSIONS_IMAGES) {
        throw "les images ne sont pas encore prises en charge cote Tripo dans cette version - utilise Meshy pour une image, ou fournis directement un fichier 3D pour Tripo"
    }

    $tailleMo = $FichierStl.Length / 1MB
    if ($tailleMo -gt 50) {
        throw "fichier de $([math]::Round($tailleMo,1)) Mo, trop volumineux - non envoye"
    }

    $entetes = @{ Authorization = "Bearer $CleApi" }
    $extension = $FichierStl.Extension.TrimStart(".").ToLower()

    # --- Etape 1 : reserver une URL d'upload ---
    Ecrire-Journal "  Reservation d'un upload (Tripo)..."
    $corps = @{ format = $extension } | ConvertTo-Json
    $reponsePresign = Invoke-RestMethod -Uri "$BaseUrlTripo/files/presign" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30
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
        $clientWeb = New-Object System.Net.WebClient
        $clientWeb.Headers.Add("Content-Type", "application/octet-stream")
        $clientWeb.UploadData($urlPresignee, "PUT", $octets) | Out-Null
        $clientWeb.Dispose()
    } catch {
        throw "echec de l'envoi du fichier vers l'URL presignee : $_"
    }
    Ecrire-Journal "  Fichier envoye."

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
    $corps = @{ type = "import_model"; file = @{ file_token = $jetonFichier } } | ConvertTo-Json
    $reponseImport = Invoke-RestMethod -Uri "$BaseUrlTripo/models/import" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30
    $idImportReponse = if ($reponseImport.data) { $reponseImport.data } else { $reponseImport }
    $idImport = $idImportReponse.task_id

    $tacheImport = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idImport" $entetes "Import"
    Ecrire-Journal "  Import termine."
    # Corrige le 07/10/2026 : contrairement a ce qu'on pensait ("0 observe partout dans le
    # tableau de bord"), Tomyn a confirme que l'import N'EST PAS gratuit (5 credits observes) -
    # ce chiffre n'etait simplement jamais ajoute au total renvoye jusqu'ici, qui sous-comptait
    # donc le cout reel de chaque generation Tripo de 5 credits.
    $creditsImport = [double]($tacheImport.credits_consumed)

    # --- Etape 4 : texturation (a partir du resultat de l'import, pas du jeton de fichier brut) ---
    # Champs corriges d'apres la vraie doc officielle (platform.tripo3d.ai/docs/texture, trouvee
    # par Tomyn) : le champ s'appelle "original_model_task_id", pas "input" comme envoye jusqu'ici
    # depuis le debut - "input" etait silencieusement ignore par leur API, qui tournait alors sans
    # jamais avoir de vraie reference de modele, d'ou l'echec systematique en cours de route quel
    # que soit le fichier. Le prompt texte est imbrique dans "texture_prompt.text", pas un champ
    # "prompt" a plat.
    Ecrire-Journal "  Envoi a l'API Texture (Tripo)..."
    $corps = @{ original_model_task_id = $idImport; texture_prompt = @{ text = $Prompt } } | ConvertTo-Json
    $reponseTexture = Invoke-RestMethod -Uri "$BaseUrlTripo/models/texture" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30
    $idTextureReponse = if ($reponseTexture.data) { $reponseTexture.data } else { $reponseTexture }
    $idTexture = $idTextureReponse.task_id

    $tacheTexture = Attendre-TacheTripo "$BaseUrlTripo/tasks/$idTexture" $entetes "Texturation"
    Ecrire-Journal "  Texturation terminee."

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
    $reponseConvert = Invoke-RestMethod -Uri "$BaseUrlTripo/models/convert" -Headers $entetes -Method Post -ContentType "application/json" -Body $corps -TimeoutSec 30
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
    # dur - ce commentaire sert juste de reference).
    $creditsTexture = [double]($tacheTexture.credits_consumed)

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
    Invoke-WebRequest -Uri $urlSortie -OutFile $cheminZip -TimeoutSec 60
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
    Ecrire-Journal "  -> Enregistre : $dossierResultat (ouvrir le fichier $($fichierObj.Name) dans Bambu Studio)"

    # 13/10/2026 : titre + description prets a coller dans le formulaire de depot MakerWorld (voir
    # Generer-DescriptionMakerWorld) - fichier texte a cote du resultat, et bouton "Copier
    # description" sur la vignette correspondante.
    $descriptionGeneree = Generer-DescriptionMakerWorld $FichierStl.BaseName $Prompt
    try { Set-Content -Path (Join-Path $dossierResultat "description_makerworld.txt") -Value $descriptionGeneree.Texte -Encoding UTF8 } catch { }

    Ajouter-Vignette $GalerieCible $fichierObj.FullName $null -texteDescription $descriptionGeneree.Texte
    [System.Windows.Forms.Application]::DoEvents()

    # Credits reellement consommes sur les TROIS etapes facturees : import (5), texturation (10)
    # et conversion (confirmes par Tomyn le 07/10/2026 - l'import n'est pas gratuit, contrairement
    # a ce qui etait suppose avant).
    $creditsTotal = $creditsImport + $creditsTexture + $creditsConvert
    Enregistrer-HistoriqueFichier $FichierStl.Name "Tripo" $creditsTotal $fichierObj.FullName
    return $creditsTotal
}

function Lancer-Image3D($FichierImage, $Entetes, [int]$TargetPolycount = 30000) {
    # Image -> maillage (ajoute le 08/10/2026) : "Image to 3D" de Meshy, maillage seul
    # (should_texture=false) - la texture est refaite juste apres par la Retexture habituelle avec
    # LE PROMPT choisi par l'utilisateur, pas celle (generique) que ferait Image to 3D elle-meme.
    # Payer la texturation deux fois (une ici, une a la Retexture) n'aurait aucun sens.
    $extension = $FichierImage.Extension.ToLower()
    $mime = if ($extension -in @(".jpg", ".jpeg")) { "image/jpeg" } else { "image/png" }
    $octets = [System.IO.File]::ReadAllBytes($FichierImage.FullName)
    $base64 = [Convert]::ToBase64String($octets)
    $dataUri = "data:$mime;base64,$base64"

    # 13/10/2026, Tomyn : "ca sort un truc tres low poly, sur le site Meshy tu peux dire combien
    # de triangles tu veux" - "target_polycount" existe bien dans l'API, mais Meshy l'ignore si
    # "should_remesh" n'est pas explicitement a true (false par defaut pour Meshy 6/7, donc AUCUN
    # remaillage avant ce correctif - d'ou le maillage brut, parfois clairseme, de la generation).
    Ecrire-Journal "  Image detectee - envoi a l'API Image to 3D (maillage seul, $TargetPolycount triangle(s) vises)..."
    $corps = @{ image_url = $dataUri; should_texture = $false; should_remesh = $true; target_polycount = $TargetPolycount } | ConvertTo-Json
    $reponse = Invoke-RestMethod -Uri "$BaseUrl/image-to-3d" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps
    $tache = Attendre-Tache "$BaseUrl/image-to-3d/$($reponse.result)" $Entetes "Image to 3D"
    Ecrire-Journal "  Maillage genere depuis l'image ($($tache.consumed_credits) credits)."
    return $tache
}

function Coloriser-UnFichier($FichierStl, $Prompt, $Entetes, $DossierSortie, $MaxCouleurs, $AvecHorodatage, $GalerieCible, $SuffixeFournisseur = "", $ExperimentalObj = $false, [double]$AssombrirPourcent = 0, [int]$TargetPolycount = 30000) {
    Ecrire-Journal ""
    Ecrire-Journal "=== $($FichierStl.Name) ==="

    $estUneImage = $FichierStl.Extension.ToLower() -in $EXTENSIONS_IMAGES
    $creditsImage3D = 0

    if (-not $estUneImage) {
        $tailleMo = $FichierStl.Length / 1MB
        if ($tailleMo -gt 50) {
            # Bloque AVANT l'envoi plutot que d'avertir apres coup : inutile de gaspiller un appel
            # API (et potentiellement des credits) voue a l'echec sur un fichier trop gros.
            throw "fichier de $([math]::Round($tailleMo,1)) Mo, limite Meshy = 50 Mo - non envoye"
        }
    }

    if ($estUneImage) {
        $tacheImage3D = Lancer-Image3D $FichierStl $Entetes $TargetPolycount
        $creditsImage3D = [int]$tacheImage3D.consumed_credits
        Ecrire-Journal "  Envoi a l'API Retexture (a partir du maillage genere)..."
        $corps = @{ input_task_id = $tacheImage3D.id; text_style_prompt = $Prompt; enable_original_uv = $false } | ConvertTo-Json
    } else {
        $octets = [System.IO.File]::ReadAllBytes($FichierStl.FullName)
        $base64 = [Convert]::ToBase64String($octets)
        $dataUri = "data:application/octet-stream;base64,$base64"

        Ecrire-Journal "  Envoi a l'API Retexture..."
        $corps = @{ model_url = $dataUri; text_style_prompt = $Prompt; enable_original_uv = $false } | ConvertTo-Json
    }
    $reponse = Invoke-RestMethod -Uri "$BaseUrl/retexture" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps
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
            Invoke-WebRequest -Uri $url -OutFile $cheminTelecharge -TimeoutSec 60

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
        $creditsTotal = $creditsImage3D + [int]$tacheRetexture.consumed_credits
        Enregistrer-HistoriqueFichier $FichierStl.Name "Meshy (.obj)" $creditsTotal $cheminObjFinal
        return $creditsTotal
    }

    Ecrire-Journal "  Envoi a l'API Multi-Color Print..."
    $corps = @{ input_task_id = $idRetexture; max_colors = $MaxCouleurs; style = "cartoon"; printer_brand = "bambu" } | ConvertTo-Json
    $reponse = Invoke-RestMethod -Uri "$BaseUrl/print/multi-color" -Headers $Entetes -Method Post -ContentType "application/json" -Body $corps
    $idImpression = $reponse.result

    $tacheImpression = Attendre-Tache "$BaseUrl/print/multi-color/$idImpression" $Entetes "Multi-Color Print"
    Ecrire-Journal "  Multi-Color Print terminee ($($tacheImpression.consumed_credits) credits)."

    $cheminSortie = Join-Path $DossierSortie ($FichierStl.BaseName + $suffixe + ".3mf")
    Invoke-WebRequest -Uri $tacheImpression.model_urls.'3mf' -OutFile $cheminSortie
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
    $creditsTotal = $creditsImage3D + [int]$tacheRetexture.consumed_credits + [int]$tacheImpression.consumed_credits
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

# Verifie la cle ET recupere le solde en un seul appel (meme endpoint) :
#   statut "valide"   -> $solde contient le vrai solde
#   statut "invalide" -> cle refusee par Meshy (HTTP 401/403), bloquant
#   statut "inconnu"  -> echec pour une autre raison (reseau, timeout...), pas bloquant en soi,
#                        on ne peut juste pas confirmer - a l'utilisateur de decider s'il continue
function Verifier-CleEtSolde($cleApi) {
    try {
        $reponse = Invoke-RestMethod -Uri "$BaseUrl/balance" -Headers @{ Authorization = "Bearer $cleApi" } -Method Get
        return @{ Statut = "valide"; Solde = [int]$reponse.balance }
    } catch {
        $codeHttp = $null
        try { $codeHttp = [int]$_.Exception.Response.StatusCode.value__ } catch { }
        if ($codeHttp -eq 401 -or $codeHttp -eq 403) {
            return @{ Statut = "invalide"; Solde = $null }
        }
        return @{ Statut = "inconnu"; Solde = $null }
    }
}

# Endpoint de solde Tripo non confirme avec certitude (contrairement a Meshy) - meme logique de
# repli "inconnu" en cas d'echec, donc une mauvaise URL ici se traduit par un avertissement
# "impossible de verifier" plutot qu'un plantage.
function Verifier-CleEtSoldeTripo($cleApi) {
    try {
        $reponse = Invoke-RestMethod -Uri "$BaseUrlTripo/user/balance" -Headers @{ Authorization = "Bearer $cleApi" } -Method Get -TimeoutSec 15
        $donnees = if ($reponse.data) { $reponse.data } else { $reponse }
        $solde = if ($donnees.balance -ne $null) { [int]$donnees.balance } else { $null }
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
    if (-not $txtPrompt.Text) {
        Afficher-Boite "Le style/couleurs voulues est vide." "Erreur" "OK" "Error" | Out-Null
        return
    }
    if (-not $txtDossierSortie.Text) {
        Afficher-Boite "Dossier de sortie vide." "Erreur" "OK" "Error" | Out-Null
        return
    }

    # --- Verification de la cle API et du solde avant de lancer, selon le fournisseur choisi ---
    # Cote Tripo : desactivee pour l'instant. L'endpoint devine (/user/balance, jamais confirme)
    # provoquait un blocage de l'appli des le clic sur Lancer - rien d'essentiel perdu (ce n'etait
    # qu'un avertissement avant coup), le vrai pipeline (upload/texture/convert) n'est pas touche.
    # A reactiver une fois le bon endpoint confirme.
    $coutEstime = $fichiersStl.Count * $CREDITS_ESTIMES_PAR_FICHIER
    # Meshy est verifie des qu'il va etre utilise (fournisseur unique "Meshy", ou mode comparaison
    # ou les deux sont utilises) - Tripo reste non verifie avant lancement (voir Verifier-CleEtSoldeTripo).
    $verifCle = if ($fournisseur -eq "Meshy" -or $caseComparerFournisseurs.Checked) { Verifier-CleEtSolde $txtCleApi.Text } else { @{ Statut = "ignore"; Solde = $null } }
    if ($verifCle.Statut -eq "invalide") {
        Afficher-Boite "La cle API $fournisseur semble invalide ou expiree. Verifie-la dans le champ correspondant avant de relancer." "Cle API invalide" "OK" "Error" | Out-Null
        return
    }
    if ($verifCle.Statut -eq "inconnu") {
        $reponseBoite = Afficher-Boite "Impossible de verifier la cle API $fournisseur ou le solde pour l'instant (probleme reseau ?). Continuer quand meme, sans cette verification ?" "Verification impossible" "YesNo" "Warning"
        if ($reponseBoite -ne "Yes") { return }
    } elseif ($verifCle.Solde -ne $null -and $verifCle.Solde -lt $coutEstime) {
        $reponseBoite = Afficher-Boite "Solde actuel : $($verifCle.Solde) credits. Cout estime pour ce lot : ~$coutEstime credits (pourrait depasser ton solde).`n`nContinuer quand meme ?" "Solde potentiellement insuffisant" "YesNo" "Warning"
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

        $reussites = 0
        $echecsCeLot = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        $interrompu = $false
        $creditsReelsLot = 0
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
            if ($script:annulationDemandee) {
                Ecrire-Journal "`n=== Annule par l'utilisateur (fichiers restants non traites) ==="
                $interrompu = $true
                break
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
            Afficher-ProgressionEnCours "Retexture en cours..."
            try {
                if ($caseComparerFournisseurs.Checked) {
                    # Les deux fournisseurs sont lances l'un apres l'autre (pas de vrai parallelisme
                    # reseau ici - garder l'appli mono-thread simple plutot que d'introduire des
                    # runspaces pour gagner du temps d'attente), chacun avec son propre try/catch :
                    # l'echec de l'un ne doit jamais empecher de recuperer le resultat de l'autre.
                    $reussiMeshy = $false
                    $reussiTripo = $false
                    try {
                        $creditsReelsLot += Coloriser-UnFichier $fichier $txtPrompt.Text $entetes $dossierSortie ([int]$numCouleurs.Value) $caseHorodatage.Checked $galerieResultatsMeshy "_meshy" $caseMeshyObjExperimental.Checked ([double]$assombrirTexture.Value) ([int]$numTriangles.Value)
                        $reussiMeshy = $true
                        $reussitesMeshy++
                    } catch {
                        if ("$_" -eq $script:ANNULATION_MARQUEUR) { throw }
                        Ecrire-Journal "  ECHEC Meshy sur $($fichier.Name) : $_"
                        $echecsMeshy++
                    }
                    try {
                        $creditsReelsLot += Coloriser-UnFichierTripo $fichier $txtPrompt.Text $txtCleApiTripo.Text $dossierSortie $caseHorodatage.Checked $galerieResultatsTripo "_tripo"
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
                        $creditsReelsLot += Coloriser-UnFichier $fichier $txtPrompt.Text $entetes $dossierSortie ([int]$numCouleurs.Value) $caseHorodatage.Checked $galerieResultatsMeshy "" $caseMeshyObjExperimental.Checked ([double]$assombrirTexture.Value) ([int]$numTriangles.Value)
                    } else {
                        $creditsReelsLot += Coloriser-UnFichierTripo $fichier $txtPrompt.Text $txtCleApiTripo.Text $dossierSortie $caseHorodatage.Checked $galerieResultatsTripo
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

        try {
            # En mode comparaison, "fichiers"/"reussites"/"echecs" comptent les deux generations
            # tentees par fichier (2x), pour que la colonne Credits de l'historique reste coherente
            # avec le cumul reellement consomme sur les deux plateformes - le detail par fournisseur
            # reste visible dans le journal de ce lot, pas dans cette ligne recapitulative globale.
            if ($caseComparerFournisseurs.Checked) {
                $ligneHistorique = "$(Get-Date -Format 'dd/MM/yyyy HH:mm');$($fichiersStl.Count * 2);$($reussitesMeshy + $reussitesTripo);$($echecsMeshy + $echecsTripo);$creditsReelsLot"
            } else {
                $ligneHistorique = "$(Get-Date -Format 'dd/MM/yyyy HH:mm');$($fichiersStl.Count);$reussites;$echecs;$creditsReelsLot"
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
        Mettre-A-Jour-Estimation  # restaure l'affichage du cout estime, a la place du temps ecoule
    }
}

$btnHistorique.Add_Click({ Afficher-FenetreHistorique })

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
$form.WindowState = "Maximized"

[void]$form.ShowDialog()
