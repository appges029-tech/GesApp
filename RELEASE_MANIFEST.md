# Release manifest — GesApp 2.2.2+43

- Base : GesApp 2.2.1+42.
- Schéma SQLite : V29.
- Source Flutter : Android, Windows et Web.
- Audit cumulatif : **100 % des 172 fichiers Dart de `lib` audités**.
- Corrections Audit 25 % : intégrées depuis 2.1.9+40.
- Corrections Audit 50 % : intégrées depuis 2.2.0+41.
- Corrections Audit 75 % : intégrées depuis 2.2.1+42.
- Corrections Audit 100 % : intégrées dans 2.2.2+43.
- Nouveau test : `test/audit100_regression_test.dart`.
- CI Web : `.github/workflows/build-web.yml`.
- Restauration JSON : manifeste complet signé + refus des exports incomplets/schémas incompatibles.

## État de validation de cette archive

Validé pendant la correction :
- 172 fichiers Dart dans `lib` ;
- 70 tables métier portables cohérentes avec le schéma SQLite V29 ;
- validation Dart ciblée du manifeste : PASS ;
- test Flutter ciblé de scrollbar : PASS ;
- syntaxe YAML des quatre workflows : PASS ;
- contrôles statiques Audit 100 : PASS.

À exécuter sur la source complète dans un environnement Flutter :
- `flutter analyze` ;
- `flutter test` ;
- `flutter test integration_test` ;
- builds Android, Windows et Web.
