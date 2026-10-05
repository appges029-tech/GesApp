# Correction générale — Phase 01/15

## Objet
Rendre la chaîne **Année scolaire → Échéances → Paiements → Rapports** réellement multi-années, sans mélanger les exercices scolaires.

## Changements
- Base SQLite portée en **V12**.
- Ajout de `school_year_id` sur `dues` et `payments`.
- Migration automatique des anciennes écritures : rattachement par date, puis par allocations de paiement, puis année active en dernier recours.
- Nouveaux index `idx_dues_school_year` et `idx_payments_school_year`.
- Génération des échéances fondée sur `student_enrollments` de l'année concernée et non sur la classe courante de `students`.
- Les échéances générées mémorisent l'année scolaire.
- Les encaissements individuels/familiaux sont limités à l'année active et mémorisent cette année.
- Les allocations ne peuvent plus sélectionner silencieusement des échéances d'une autre année.
- Dashboard : attendu, encaissé, impayés et montants futurs isolés sur l'année active.
- Fiches élèves/familles : situation financière courante isolée sur l'année active.
- Rapports : ajout d'un filtre Année scolaire ; les classes historiques viennent de `student_enrollments`.
- Journal, bilan, dépenses et remboursements utilisent l'année sélectionnée ou active.
- Alertes d'impayés et de capacité utilisent l'année active et la classe historique correcte.
- Diagnostic : nouveaux contrôles des écritures sans année et des allocations inter-années.
- Import JSON V11 : backfill automatique des nouveaux rattachements lors de l'import dans une base V12.

## Compatibilité
Les colonnes V12 restent nullable au niveau SQLite afin de pouvoir restaurer un ancien export JSON V11 avant normalisation. Les écritures produites par GesApp V12 renseignent systématiquement l'année scolaire.

## Validation effectuée dans l'environnement de correction
- Vérification statique des délimiteurs Dart des fichiers modifiés.
- Simulation SQLite de la migration V11 → V12 : rattachement d'une échéance et d'un paiement à 2025-2026, `PRAGMA integrity_check = ok`.
- Flutter SDK indisponible dans l'environnement : `flutter analyze`, `flutter test` et le build doivent être exécutés par GitHub Actions.

## Étape suivante
Phase 02 : finaliser le moteur d'avoirs et permettre l'utilisation réelle d'un crédit disponible sur de nouvelles échéances.
