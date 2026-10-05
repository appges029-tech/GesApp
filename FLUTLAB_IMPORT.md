# Import GesApp dans FlutLab

Cette archive place directement `android/`, `ios/`, `lib/` et `pubspec.yaml` à la racine, conformément aux contrôles d'import Flutter de FlutLab.

## Dans FlutLab
1. Importer le ZIP comme projet Flutter.
2. Exécuter Pub Get.
3. Lancer d'abord la cible Android/Web proposée par FlutLab.
4. En cas d'erreur de dépendance ou de compilation, conserver le log complet pour correction.

## Plateformes
- Android : structure Gradle incluse.
- iOS : structure Xcode/Podfile incluse pour satisfaire l'import et préparer la cible iOS.
- Windows : racine de plateforme incluse; pour un build Windows de production, régénérer les fichiers runner avec le SDK Flutter sur Windows.
- Web/Linux/macOS : racines présentes pour préserver la stratégie multiplateforme.

Le code métier Flutter reste partagé dans `lib/`.
