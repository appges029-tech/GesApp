# GesApp RC48H P3 — état d'implémentation

Cette RC étend P2 sans retirer les correctifs de fiabilité comptable et d'analyse Flutter.

## Implémenté dans P3

- Filtres élèves combinables : recherche nom/matricule, cycle, classe, famille, statut administratif et situation de paiement.
- Situation paiement calculée : à jour, partiel, impayé, en retard, aucune échéance, forfait.
- Fiche élève enrichie avec identité, famille, situation financière, échéances, paiements et historique des statuts.
- Photo élève locale via sélecteur de fichier, copiée dans l'espace GesApp.
- Pièces du dossier élève : ajout, stockage local, marquage obligatoire, consultation des images, suppression auditée.
- Réinscription/changement de classe avec contrôle de capacité.
- Rattachement/changement/détachement d'une famille depuis la fiche élève.
- Fiche élève PDF complète : identité, situation financière, pièces, échéances, paiements, historique.
- Filtres rapports : cycle, classe, famille et période.
- Liste des impayés enrichie.
- Avis d'échéance PDF et facture détaillée PDF par échéance.
- Grand livre : recettes/dépenses, débit, crédit et solde progressif.
- Export Excel-compatible `.xls` des tableaux de rapports et du grand livre.

## Validation encore obligatoire

Exécuter sur GitHub Actions :

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --release`

Le SDK Flutter n'est pas disponible dans l'environnement ayant généré cette archive : la validation de compilation reste donc le verrou de livraison.
