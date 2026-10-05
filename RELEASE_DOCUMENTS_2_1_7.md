# Release GesApp 2.1.7+38 — Documents professionnels

Base : GesApp_FINAL_2.1.6_RESPONSIVE.

## Consolidation
- identité documentaire commune avec logo, coordonnées, agrément et année scolaire ;
- pied de page avec référence, opérateur, horodatage et pagination ;
- références stables/séquentielles stockées dans `app_settings` sans migration SQLite ;
- empreinte SHA-256 locale pour les documents consolidés ;
- vérification locale étendue aux références documentaires ;
- reçus, factures, avis, fiche élève, paie, bilan, RH, patrimoine, comptabilité et appels à paiement renforcés ;
- appels à paiement restent à 8 par page A4 ;
- rapports tabulaires segmentés par blocs de 400 lignes pour limiter la charge de composition PDF.

## Supabase
Aucun fichier de synchronisation Supabase/cloud snapshot n'a été modifié par cette release.

## Validation disponible
Contrôles statiques effectués : imports relatifs, délimiteurs, usages des signatures et intégrité ZIP.
Le SDK Flutter/Dart n'étant pas disponible dans l'environnement, `flutter analyze`, `flutter test` et les builds Android/Windows restent à exécuter sur une machine Flutter.
