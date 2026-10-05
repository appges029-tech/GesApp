# Finalisation des fonctionnalités restées partielles

Cette passe termine les trois éléments déclarés partiels après la consolidation 1–10.

## 1. Import massif CSV / Excel

- Nouvel écran **Élèves > Importer CSV/Excel**.
- Formats acceptés : `.csv` et `.xlsx`.
- Colonnes obligatoires : `nom`, `prenom`, `classe`.
- Colonnes facultatives : `sexe`, `date_naissance`, `lieu_naissance`, `responsable`, `telephone`, `famille`, `nationalite`, `adresse`, `ecole_origine`.
- Les classes sont reconnues par identifiant, nom simple ou `Cycle + Classe`.
- Aperçu avant import.
- Détection des doublons probables.
- Contrôle de la capacité des classes.
- Création automatique d'une famille lorsqu'une famille nommée n'existe pas encore.
- Les lignes invalides sont ignorées et reportées sans bloquer tout le lot.
- L'opération est inscrite au journal d'audit.
- Modèle : `docs/student_import_template.csv`.

## 2. Remboursement partiel

- Action **Remboursement partiel** dans le menu de chaque encaissement actif.
- Affichage du montant encore remboursable.
- Montant et motif obligatoires.
- Réduction cohérente des avoirs puis des affectations aux échéances.
- Historique dans `payment_refunds` et dans le journal d'audit.
- Affichage du total remboursé et du montant net sur la liste des encaissements.
- Une annulation totale est refusée après un remboursement partiel pour éviter une double contre-passation.
- Tableau de bord, journal de caisse, bilan financier et caisse théorique utilisent désormais les recettes nettes des remboursements.
- Le diagnostic d'intégrité tient compte des remboursements et des avoirs.

## 3. Workflow d'approbation des dépenses

Cycle opérationnel :

`Nouvelle demande -> En attente -> Approuvée -> éventuellement Annulée`

ou :

`Nouvelle demande -> En attente -> Rejetée -> Resoumise -> En attente`.

Une dépense en attente ou rejetée n'entre pas dans le tableau de bord, les rapports financiers ni la trésorerie. Elle devient comptabilisée uniquement après l'action **Approuver**.

La base passe en version **11** avec les métadonnées de soumission et de décision : `submitted_by`, `submitted_at`, `reviewed_by`, `reviewed_at`, `approval_note`.

GesApp conserve son principe d'**interface unique Gestionnaire** : l'approbation est une étape explicite de contrôle de saisie, pas un rôle Directeur/Caissier séparé.

## Validation attendue en CI

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build web --release
```

Les nouvelles dépendances de parsing sont `csv` et `excel`, toutes deux utilisées sans `dart:io` dans l'écran d'import afin de rester compatibles Web.
