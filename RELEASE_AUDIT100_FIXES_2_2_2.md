# GesApp 2.2.2+43 — Corrections Audit 100 %

Date : 2 octobre 2026

Cette version part de GesApp 2.2.1+42 et corrige les cinq constats du dernier quart de l'audit, portant la couverture cumulée à 100 % des 172 fichiers Dart de `lib`.

## Corrections

1. **Restauration JSON complète**
   - les exports ajoutent désormais un `table_manifest` couvert par le checksum SHA-256 ;
   - une restauration du schéma courant exige les 70 tables portables attendues ;
   - l'absence d'une table n'est plus interprétée comme une table vide ;
   - un export d'un schéma SQLite différent est refusé tant qu'une migration JSON sûre et versionnée n'existe pas ;
   - les chemins Desktop/Android et Web utilisent la même règle de complétude.

2. **ResponsiveDataTable**
   - passage en `StatefulWidget` ;
   - `ScrollController` horizontal partagé entre `Scrollbar` et `SingleChildScrollView` ;
   - libération du contrôleur dans `dispose()`.

3. **Écran RH**
   - distinction entre chargement, erreur et absence de données ;
   - message d'erreur visible ;
   - bouton `Réessayer` au lieu d'un spinner infini.

4. **Synchronisation Web**
   - bouton de synchronisation désactivé quand le service indique `unsupported` ;
   - message explicite sur le stockage local navigateur et l'usage des sauvegardes JSON.

5. **CI Web**
   - ajout de `.github/workflows/build-web.yml` ;
   - génération du scaffold Web lorsqu'il est absent ;
   - installation du runtime SQLite Web ;
   - analyse, tests, build release, artifact et déploiement `gh-pages` sur `main` ;
   - documentation Web alignée sur le workflow réel.

## Tests ajoutés

`test/audit100_regression_test.dart` couvre :
- export complet accepté ;
- export incomplet refusé ;
- ancien schéma refusé ;
- tableau responsive sans exception de scrollbar ;
- erreur RH visible et récupérable ;
- bouton cloud désactivé en état `unsupported`.

## Validation effectuée pendant la correction

- validateur de manifeste exécuté avec Dart 3.13.2 : PASS ;
- scénario de scrollbar avec contrôleur partagé exécuté par `flutter test` sur Flutter 3.47.2 : PASS ;
- 70/70 tables portables retrouvées dans le schéma SQLite V29 : PASS ;
- 4 workflows GitHub Actions analysés comme YAML valide : PASS ;
- 172 fichiers Dart toujours présents dans `lib` : PASS ;
- structure lexicale des 7 fichiers Dart modifiés/ajoutés : PASS.

## Limite de certification

L'archive complète 2.2.2+43 n'était pas présente sur la machine Flutter connectée pendant cette correction. En conséquence, il n'est **pas revendiqué** que `flutter analyze`, `flutter test`, `flutter test integration_test`, `flutter build windows`, `flutter build apk` et `flutter build web` ont été exécutés sur l'archive complète exacte. Les workflows nécessaires sont présents pour réaliser cette certification sur le dépôt source.
