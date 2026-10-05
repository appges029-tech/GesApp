# Durcissement de production — GesApp 1.5.0+17

Cette version corrige les principaux blocages trouvés pendant l’audit de
production du 8 septembre 2026.

## Changements appliqués

- L’accès libre lors de la première installation est supprimé.
- La création du premier compte gestionnaire est maintenant obligatoire avant
  l’ouverture de l’application.
- Le premier compte est automatiquement authentifié après sa création.
- L’écran d’erreur de démarrage ne montre plus immédiatement le stack trace;
  les détails restent accessibles dans une section repliée pour le support.
- Une release Android n’est plus signée avec la clé publique de débogage.
- La configuration d’une keystore privée est prise en charge par
  `android/key.properties`, exclu du dépôt.
- La CI Windows échoue maintenant si `flutter analyze` ou `flutter test`
  échoue.
- Les deux workflows Android ne se déclenchent plus automatiquement en double.
- La CI Android exige une keystore via secrets et ne publie qu’un APK signé,
  donc installable.
- Quatre tests supplémentaires couvrent le hachage du PIN, le verrouillage
  anti-force-brute, l’historique RH et les mouvements de patrimoine.

## Signature Android officielle

1. Créer une keystore privée et la conserver hors du dépôt.
2. Copier `android/key.properties.example` vers `android/key.properties`.
3. Remplacer les quatre valeurs d’exemple.
4. Exécuter `tool/preflight_release.sh` sous Linux/macOS ou
   `tool/preflight_release.ps1` sous Windows.
5. Ne distribuer que `build/app/outputs/flutter-apk/app-release.apk`.

Sans `android/key.properties`, le build release échoue explicitement afin
d’éviter la production d’un APK non installable.

## Validation obligatoire

La livraison source a été préparée dans un environnement sans SDK Flutter.
Avant diffusion, une machine Flutter doit obtenir les résultats suivants :

```text
flutter pub get       -> succès
flutter analyze       -> zéro erreur
flutter test          -> 13 tests réussis
flutter build apk --release -> app-release.apk signé
flutter build windows --release -> succès
```

Le premier `flutter pub get` génère `pubspec.lock`. Ce fichier doit être ajouté
au dépôt afin de rendre les versions suivantes reproductibles.
