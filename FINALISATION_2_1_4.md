# GesApp 2.1.4+35 — finalisation de l'audit

- Gardes d'écriture administrateur corrigées et conservées dans les corps de méthodes.
- Synchronisation concurrente : snapshot versionné, contrôle optimiste de révision, suppression du candidat perdant, puis nettoyage de l'ancien snapshot.
- Vérification SHA-256 avant restauration.
- Migration Supabase consolidée et reproductible : organizations, organization_members, devices, sync_metadata, RLS, helpers privés, RPC et bucket privé unique `gesapp-backups`.
- Création d'établissement interdite tant que l'e-mail administrateur n'est pas confirmé côté serveur.
- Windows : la confirmation e-mail se termine dans le navigateur, puis l'utilisateur revient dans GesApp et se connecte avec son e-mail et son mot de passe ; aucune dépendance à un protocole URI Windows n'est requise.
- Android/iOS/macOS : le callback applicatif peut être utilisé.

## Certification encore externe à cet environnement
Le SDK Flutter/Dart n'est pas installé ici. Exécuter sur une machine Flutter :
`flutter clean`, `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, `flutter build apk --release`, `flutter build windows --release`.
