# Release Windows Fluent — GesApp 2.1.7+38

## Portée
Refonte de la couche présentation Windows selon la spécification `docs/design/GesApp_Windows_Fluent_SPEC.md`.

## Fichiers métier protégés
Les répertoires suivants sont identiques au ZIP source :
- `lib/data/repositories/`
- `lib/services/`
- `lib/core/db/`

`pubspec.yaml` est également inchangé : aucune dépendance n'a été ajoutée.

## Nouveaux composants
- `lib/core/windows/windows_ui.dart`
- `lib/core/windows/windows_page_scaffold.dart`
- `lib/core/windows/windows_panels.dart`
- `lib/core/windows/windows_filter_panel.dart`

## Écrans principaux migrés
- Shell principal
- Tableau de bord
- Élèves
- Formulaire élève
- Finances
- Encaissements
- Dépenses
- RH
- Patrimoine
- Rapports
- Réglages

## Validation
Le conteneur de génération ne contient pas Flutter/Dart. `flutter analyze`, `flutter test` et `flutter build windows` n'ont donc pas pu être exécutés ici.
Les contrôles statiques et d'intégrité du ZIP ont été exécutés ; voir `WINDOWS_FLUENT_IMPLEMENTATION.md`.
