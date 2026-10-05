# Correctifs CI / flutter analyze — 26 août 2026

Cette passe corrige les erreurs remontées par GitHub Actions après la consolidation finale.

## Correctifs bloquants

- Remplacement de `Sqflite.firstIntValue` par `firstIntValue` depuis `sqflite_common/utils/utils.dart` dans `AppDatabase` et `FinanceRepository`.
- Correction des callbacks asynchrones du menu des paiements avec `unawaited`, afin de respecter la signature `void Function(String)` de `PopupMenuButton.onSelected`.
- `BackupService` utilise maintenant `platformDatabaseFactory.openDatabase` au lieu d'un `openDatabase` natif non importé, ce qui conserve l'abstraction multiplateforme.
- Résolution du conflit de symbole `Hmac` entre `crypto` et `cryptography`.
- Mise à jour Workmanager : `NetworkType.not_required` -> `NetworkType.notRequired`.

## Nettoyage analyseur

- Suppression du champ `_hasUsers` devenu inutile.
- Suppression d'un import SQLite inutilisé et d'un cast inutile dans `SecurityRepository`.
- Suppression d'une variable locale inutilisée dans les paramètres.
- Suppression d'une comparaison à `null` impossible dans l'import Excel.
- Suppression d'assertions `!` inutiles dans les services de sauvegarde/JSON.
- Ajout d'accolades dans les boucles/branches signalées par le linter.
- Réécriture de l'écran Caisse pour éviter les usages de `BuildContext` après des gaps async et simplifier l'état.
- Correction du même risque dans l'écran de test des notifications.

## Validation attendue en CI

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --release`
5. `flutter build web --release --base-href=...`
