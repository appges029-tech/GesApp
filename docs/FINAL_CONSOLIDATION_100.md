# GesApp 2.0.0 — Consolidation finale 100 %

Cette livraison consolide les phases précédentes dans une seule base source. Le terme **100 %** désigne ici le périmètre fonctionnel V1/V2 défini pour GesApp : gestion administrative scolaire, finances/comptabilité, dépenses, RH, patrimoine, rapports, sécurité, sauvegardes et fonctionnement multi-plateforme prévu par le dépôt.

## Scolarité

- Élèves, matricules, recherche, filtres avancés, capacités de classe et historique des statuts.
- Familles et responsables multiples.
- Import massif CSV/Excel avec prévisualisation.
- Réinscription annuelle et historique des inscriptions/changements de classe.
- Photo et dossier documentaire élève.
- Pièces obligatoires configurables et indicateur de complétude.
- Référence publique `DOC-…` pour chaque pièce, recherche d’authenticité et statut valide/invalidé.
- Fiche élève et données financières associées.

## Finances et recouvrement

- Rubriques, grilles tarifaires, forfaits, facturation et lots de génération.
- Échéances par année scolaire, paiements partiels, affectations, avances/avoirs.
- Reçus PDF et vérification d’authenticité par numéro.
- Remboursements partiels, annulations contrôlées et contre-passations.
- Appels à paiement : 8 avis par page A4 avec date limite de paiement.
- Caisse, comptes banque/Mobile Money, transferts internes et clôture.
- Impayés, relances, promesses et suivi du recouvrement.

## Comptabilité

- Comptabilité d’engagement : créances scolaires et dettes fournisseurs.
- Plan comptable simplifié, journaux, livre-journal, grand-livre et balance.
- Factures/règlements fournisseurs.
- Écritures manuelles équilibrées.
- Rapprochement banque/Mobile Money.
- Paramétrage des comptes de créances, produits, fournisseurs et trésorerie.
- Bilan financier global sur plage de dates, PDF, graphiques et indicateurs.

## Dépenses

- Demandes, justificatifs, dépenses récurrentes et recherche.
- Workflow soumission → approbation/rejet → comptabilisation.
- Annulation auditée.
- Validation renforcée des approbations/annulations sensibles.

## RH

- Personnel, services/postes, contrats, affectations et dossier RH.
- Présences, congés, évaluations, paie, avances et remboursements.
- Documents RH, bulletins PDF et rapports.

## Patrimoine

- Registre des biens, catégories, localisations, responsables.
- Affectations/transferts, maintenance, inventaires et sorties.
- Documents et justificatifs, historique complet et rapports.

## Sécurité, audit et résilience

- Comptes Gestionnaire individuels avec PIN PBKDF2-SHA256 et récupération.
- Anti-brute-force et verrouillage temporaire.
- Journal d’audit avec opérateur.
- Pour une opération financière sensible, si plusieurs gestionnaires sont actifs, un autre gestionnaire doit autoriser l’action avec son identifiant et son PIN.
- Diagnostic de cohérence SQLite/comptable.
- Sauvegarde chiffrée `.gesbk`, sauvegarde automatique locale, restauration sûre et export/import JSON complet avec médias.
- Le sélecteur système permet de copier une sauvegarde vers un dossier synchronisé/cloud disponible sur la plateforme. L’intégration OAuth Google Drive automatique n’est pas embarquée car elle nécessite les identifiants OAuth propres à l’établissement et une configuration externe ; elle ne fait pas partie du chemin critique offline.

## Migration finale

- Version application : `2.0.0+30`.
- Version SQLite : `27`.
- Migration V26 → V27 : ajout des références d’authenticité aux pièces existantes, sans perte des fichiers.

## Certification obligatoire avant diffusion terrain

Exécuter sur une machine disposant du SDK Flutter :

```bash
flutter clean
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

Le dépôt de génération utilisé pour la consolidation ne dispose pas du SDK Flutter/Dart ; la structure et la cohérence statique peuvent être contrôlées ici, mais la certification binaire doit être effectuée par CI ou sur le poste Flutter avant installation en production.
