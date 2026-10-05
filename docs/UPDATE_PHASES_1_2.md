# GesApp — Mise à jour chantiers 1 et 2

## Chantier 1 — Socle données et années scolaires

- Base SQLite portée en version 6 avec migration progressive V4 → V5 → V6.
- Nouvelle table `school_years` avec une seule année active à la fois.
- Nouvelle table `student_enrollments` : une inscription par élève et par année scolaire, classe, type d'inscription, statut, dates d'effet et observations.
- Migration automatique des élèves existants vers l'année scolaire configurée lors de la mise à niveau.
- Le statut historique `reinscrit` est normalisé vers `active`; la réinscription devient un `enrollment_type = re_enrollment`.
- Réinscription annuelle et changement de classe sont désormais deux opérations métier distinctes.
- La fiche élève affiche un bloc « Parcours scolaire ».
- Nouveau paramètre « Années scolaires » permettant de créer, consulter et activer une année sans supprimer l'historique.
- Les colonnes courantes `students.classroom_id` et `students.status` sont conservées comme cache de compatibilité pour éviter une régression brutale des modules existants.

## Chantier 2 — Sécurité, utilisateurs et permissions

- Nouvelle table `app_users` avec identifiant unique, nom affiché, rôle, PIN haché/salé, état actif, compteur d'échecs et verrouillage persistant.
- Rôles initiaux : `director`, `manager`, `cashier`.
- Migration automatique de l'ancien PIN global vers un premier compte Directeur lorsque ce PIN existe.
- Écran de connexion multi-utilisateurs avec sélection du compte et PIN individuel.
- Anti-brute-force désormais persistant en SQLite : fermer/réouvrir l'application ne réinitialise plus les tentatives.
- L'opérateur du journal d'audit provient du compte authentifié ; ajout de `operator_id` et `operator_role` dans `audit_log`.
- Écran « Sécurité et utilisateurs » : création de comptes, changement de rôle, activation/désactivation et réinitialisation de PIN.
- Le premier compte créé sur une installation sans compte doit être Directeur.
- Navigation filtrée par rôle : le Caissier accède au tableau de bord, encaissements/impayés et dépenses ; le Gestionnaire accède en plus aux élèves et rapports ; le Directeur conserve tout.
- Les configurations financières sont réservées au Directeur ; les encaissements restent autorisés aux rôles habilités.
- Annulation de paiement et de dépense réservée au Directeur au niveau repository, et pas seulement dans l'interface.

## Compatibilité / validation

- Les tables historiques sont conservées pour éviter de casser les modules qui n'ont pas encore été migrés vers le nouveau socle.
- Le SQL du schéma complet a été exécuté avec succès dans SQLite lors du contrôle structurel.
- Un contrôle syntaxique structurel des fichiers Dart modifiés a été effectué.
- `flutter analyze` et `flutter test` ne peuvent pas être exécutés dans l'environnement de travail actuel car le SDK Flutter/Dart n'y est pas installé. Ils restent obligatoires dans la CI ou sur le poste de développement avant fusion/release.

## À ne pas confondre avec les phases suivantes

La double validation avec saisie du PIN d'un second superviseur lors d'une annulation financière n'est pas encore implémentée ici. Le chantier 2 fournit désormais les comptes/rôles authentifiés nécessaires ; l'intégration de cette double validation doit être faite avec le chantier 4/5 lors de la refonte des flux financiers et de caisse.
