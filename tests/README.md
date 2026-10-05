# Tests — ColoriseurSTL

## Limite importante à connaître

Contrairement aux décodeurs des quatre lecteurs RFID (Kotlin pur, sans dépendance Android,
donc réellement exécutables et testés ici), `RenduStl.kt` appelle de vraies classes
`android.graphics.*` (Bitmap, Canvas, Paint, Path). Ces classes ne sont que des **déclarations**
dans le jar Android utilisé pour la compilation locale — elles lèvent une exception si on essaie
de vraiment les exécuter hors d'un appareil ou d'un émulateur Android réel. Impossible donc de
générer et d'inspecter une vraie image ici.

Deux vérifications indépendantes ont quand même été faites avant la livraison :

1. **La lecture du fichier STL** (binaire/ASCII, sans aucune dépendance `android.graphics`) a été
   extraite et réellement exécutée sur un cube de test synthétique (`cube_test.stl`, 12 triangles,
   10×10×10, centré sur l'origine) : 12 triangles chargés, boîte englobante exacte.
2. **Les calculs de rotation/projection/ombrage** ont été reproduits fidèlement en Python
   (exécutable, contrairement au Kotlin+Canvas) et appliqués au même cube : intensités d'ombrage
   cohérentes (3 niveaux distincts pour les 6 faces du cube, logique vu les paires de faces
   opposées), profondeurs cohérentes pour le tri du peintre.

C'est cette seconde vérification qui a permis de trouver et corriger un vrai bug avant la
livraison : l'échelle se basait sur la boîte englobante *avant* rotation, ce qui coupait les
coins du rendu sur des formes anguleuses (jusqu'à 19% hors cadre mesuré sur ce cube). Corrigé en
calculant l'échelle sur l'étendue *après* rotation (voir le commentaire dans `RenduStl.kt`).

**Donc : la logique est vérifiée aussi rigoureusement que possible sans appareil réel, mais le
rendu visuel final (le dessin effectif à l'écran) n'a jamais été vu.** Premier vrai test à faire
sur un téléphone.

## Contenu

- **`cube_test.stl`** — cube binaire synthétique, 12 triangles, utilisé pour les deux
  vérifications ci-dessus.

## Pour tester la lecture seule (sans Android)

```
kotlinc TestParsing.kt -include-runtime -d test.jar
java -jar test.jar
```

(Le fichier `TestParsing.kt` reproduit la logique de `charger()`/`chargerBinaire()` de
`RenduStl.kt` sans dépendance Android, pour pouvoir l'exécuter ici.)
