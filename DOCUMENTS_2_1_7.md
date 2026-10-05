# GesApp 2.1.7 — Consolidation documentaire

Cette version consolide la génération des documents sans modifier le système de synchronisation Supabase.

## Charte documentaire commune
- identité de l’établissement centralisée : logo, nom, adresse, téléphone, e-mail, agrément et année scolaire ;
- pied de page commun avec référence, opérateur, date/heure et pagination ;
- rapports génériques traités par blocs de 400 lignes pour réduire la pression mémoire du moteur PDF.

## Références pérennes
Les références sont stockées dans `app_settings`, table déjà existante, afin de ne pas ajouter de schéma lié au cloud :
- `FAC-AAAA-000001` : facture ;
- `ECH-AAAA-000001` : avis d’échéance ;
- `BP-AAAA-000001` : bulletin de paie ;
- `FEL-AAAA-000001` : fiche élève ;
- `BIL-AAAA-000001` : bilan financier ;
- `RAP`, `RHR`, `RPA`, `JRN`, `GL`, `BAL`, `PCA`, `APP` : rapports et lots officiels.

Chaque PDF consolidé enregistre aussi son empreinte SHA-256 dans `app_settings`. Les reçus conservent leur numéro métier existant.

## Vérification
L’écran Finance > Vérifier un document accepte désormais un numéro de reçu ou une référence documentaire. Pour les documents consolidés, il affiche le type, la date d’enregistrement et l’empreinte SHA-256 disponible.

## Documents renforcés
- reçus : identité complète, logo, opérateur, référence transactionnelle facultative, indication de vérification ;
- factures/avis : référence stable et charte commune ;
- fiches élèves : identité complète et codes/statuts de vérification des pièces ;
- bulletins de paie : matricule, fonction, service, référence, paiement, signatures et identité complète ;
- bilan financier : charte commune, référence et traçabilité ;
- rapports RH, patrimoine et comptabilité : identité, référence, période, pagination et empreinte ;
- appels à paiement : 8/A4 conservé, agrément/e-mail et référence de lot ajoutés.

## Certification
Le SDK Flutter/Dart n’est pas disponible dans l’environnement de génération. Exécuter avant publication :
`flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, puis les builds Android/Windows.
