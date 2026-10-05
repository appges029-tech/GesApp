# GesApp 2.1.6+37 — Passe de responsivité

Cette version améliore la responsivité sans modifier le système de synchronisation Supabase.

## Corrections
- Ajout de `ResponsiveDialogContent` : largeur calculée selon l'écran, avec largeur maximale desktop.
- Dialogues Patrimoine adaptés : détail, configuration, inventaire, maintenance.
- Dialogue Dépenses récurrentes adapté.
- Dialogues Finance adaptés : fournisseurs et rapprochement bancaire.
- Dialogues RH adaptés : employé, congés et paie.
- Dialogue de gestion des cycles adapté.
- Ajout de `ResponsiveDataTable` : cartes verticales sous 600 px, DataTable sur tablette/desktop.
- Comptabilité générale : affichage mobile sans défilement horizontal obligatoire.
- Rapports : affichage mobile en cartes lisibles.
- Rapprochement bancaire : hauteur adaptée aux petits écrans.
- Les breakpoints existants 600 / 900 / 1200 / 1600 restent la source de vérité.

## Synchronisation Supabase
Les fichiers suivants sont volontairement inchangés :
- `cloud_snapshot_service.dart`
- `cloud_snapshot_service_io.dart`
- `cloud_snapshot_service_stub.dart`
- `tenant_cloud_service.dart`

## Validation
Contrôles statiques effectués sur les fichiers modifiés et intégrité ZIP vérifiée.
Flutter/Dart n'étant pas disponibles dans l'environnement de consolidation, `flutter analyze`, `flutter test` et les builds release restent à exécuter sur une machine équipée du SDK Flutter.
