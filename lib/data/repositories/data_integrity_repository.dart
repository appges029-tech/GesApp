import 'package:sqflite_common/utils/utils.dart';

import '../../core/db/app_database.dart';

class IntegrityCheckResult {
  const IntegrityCheckResult({
    required this.label,
    required this.passed,
    required this.detail,
  });

  final String label;
  final bool passed;
  final String detail;
}

class DataIntegrityReport {
  const DataIntegrityReport({
    required this.generatedAt,
    required this.checks,
  });

  final DateTime generatedAt;
  final List<IntegrityCheckResult> checks;

  bool get healthy => checks.every((check) => check.passed);
  int get failureCount => checks.where((check) => !check.passed).length;
}

/// Contrôles de cohérence destinés à la release terrain.
///
/// Ils sont volontairement en lecture seule : ce module n'essaie jamais de
/// "réparer" silencieusement des écritures comptables. Une anomalie doit être
/// comprise avant toute correction des données.
class DataIntegrityRepository {
  DataIntegrityRepository(this._database);
  final AppDatabase _database;

  Future<int> _scalar(String sql, [List<Object?>? args]) async =>
      firstIntValue(await _database.db.rawQuery(sql, args)) ?? 0;

  Future<DataIntegrityReport> run() async {
    final db = _database.db;
    final checks = <IntegrityCheckResult>[];

    final integrityRows = await db.rawQuery('PRAGMA integrity_check');
    final integrityMessages = integrityRows
        .expand((row) => row.values)
        .whereType<Object>()
        .map((value) => value.toString())
        .toList();
    final sqliteOk = integrityMessages.length == 1 &&
        integrityMessages.first.toLowerCase() == 'ok';
    checks.add(IntegrityCheckResult(
      label: 'Intégrité SQLite',
      passed: sqliteOk,
      detail: sqliteOk
          ? 'La base SQLite répond « ok ».'
          : integrityMessages.join(' · '),
    ));

    final foreignKeyRows = await db.rawQuery('PRAGMA foreign_key_check');
    checks.add(IntegrityCheckResult(
      label: 'Clés étrangères',
      passed: foreignKeyRows.isEmpty,
      detail: foreignKeyRows.isEmpty
          ? 'Aucune référence orpheline détectée.'
          : '${foreignKeyRows.length} référence(s) orpheline(s) détectée(s).',
    ));

    final invalidDueAmounts = await _scalar('''
      SELECT COUNT(*) FROM dues
      WHERE amount_due <= 0 OR amount_paid < 0 OR amount_paid > amount_due
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Montants des échéances',
      passed: invalidDueAmounts == 0,
      detail: invalidDueAmounts == 0
          ? 'Aucune échéance négative ou surpayée.'
          : '$invalidDueAmounts échéance(s) ont un montant incohérent.',
    ));

    final invalidDueStatuses = await _scalar('''
      SELECT COUNT(*) FROM dues
      WHERE (amount_paid = 0 AND status != 'unpaid')
         OR (amount_paid > 0 AND amount_paid < amount_due AND status != 'partial')
         OR (amount_paid >= amount_due AND status != 'paid')
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Statut des échéances',
      passed: invalidDueStatuses == 0,
      detail: invalidDueStatuses == 0
          ? 'Les statuts unpaid/partial/paid correspondent aux montants.'
          : '$invalidDueStatuses échéance(s) ont un statut incohérent.',
    ));

    final paymentAllocationMismatches = await _scalar('''
      SELECT COUNT(*) FROM payments p
      WHERE p.status = 'posted'
        AND (
          COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa WHERE pa.payment_id=p.id),0)
          + COALESCE((SELECT SUM(pc.amount) FROM payer_credits pc WHERE pc.source_payment_id=p.id AND pc.status='available'),0)
          + COALESCE((SELECT SUM(pca.amount) FROM payer_credit_allocations pca JOIN payer_credits pc ON pc.id=pca.credit_id WHERE pc.source_payment_id=p.id),0)
        ) != (
          p.amount - COALESCE((SELECT SUM(pr.amount) FROM payment_refunds pr WHERE pr.payment_id=p.id),0)
        )
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Affectation des paiements',
      passed: paymentAllocationMismatches == 0,
      detail: paymentAllocationMismatches == 0
          ? 'Chaque paiement actif net est justifié par ses affectations ou son avoir disponible.'
          : '$paymentAllocationMismatches paiement(s) ne correspondent pas à leurs affectations/avoirs/remboursements.',
    ));

    final dueAllocationMismatches = await _scalar('''
      SELECT COUNT(*) FROM (
        SELECT d.id, d.amount_paid,
               COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa JOIN payments p ON p.id=pa.payment_id WHERE pa.due_id=d.id AND p.status='posted'),0)
               + COALESCE((SELECT SUM(pca.amount) FROM payer_credit_allocations pca WHERE pca.due_id=d.id),0) allocated
        FROM dues d
        GROUP BY d.id, d.amount_paid
        HAVING allocated != d.amount_paid
      ) x
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Solde payé des échéances',
      passed: dueAllocationMismatches == 0,
      detail: dueAllocationMismatches == 0
          ? 'Les montants payés correspondent aux affectations actives.'
          : '$dueAllocationMismatches échéance(s) diffèrent de leurs affectations.',
    ));

    final orphanSchoolYearFinance = await _scalar('''
      SELECT
        (SELECT COUNT(*) FROM dues d
          WHERE d.school_year_id IS NULL
             OR NOT EXISTS (SELECT 1 FROM school_years sy WHERE sy.id=d.school_year_id))
        +
        (SELECT COUNT(*) FROM payments p
          WHERE p.school_year_id IS NULL
             OR NOT EXISTS (SELECT 1 FROM school_years sy WHERE sy.id=p.school_year_id))
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Années scolaires financières',
      passed: orphanSchoolYearFinance == 0,
      detail: orphanSchoolYearFinance == 0
          ? 'Toutes les échéances et tous les paiements sont rattachés à une année scolaire.'
          : '$orphanSchoolYearFinance écriture(s) financière(s) sans année scolaire valide.',
    ));

    final crossYearAllocations = await _scalar('''
      SELECT COUNT(*)
      FROM payment_allocations pa
      JOIN payments p ON p.id=pa.payment_id
      JOIN dues d ON d.id=pa.due_id
      WHERE p.school_year_id IS NOT NULL
        AND d.school_year_id IS NOT NULL
        AND p.school_year_id != d.school_year_id
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Affectations inter-années',
      passed: crossYearAllocations == 0,
      detail: crossYearAllocations == 0
          ? 'Aucun paiement n’est affecté à une échéance d’une autre année scolaire.'
          : '$crossYearAllocations affectation(s) mélangent deux années scolaires.',
    ));

    final duplicateGrids = await _scalar('''
      SELECT COUNT(*) FROM (
        SELECT fee_id, COALESCE(classroom_id, ''), COALESCE(cycle_id, ''), COUNT(*) n
        FROM fee_grid
        WHERE valid_to IS NULL
        GROUP BY fee_id, COALESCE(classroom_id, ''), COALESCE(cycle_id, '')
        HAVING n > 1
      ) x
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Grille tarifaire active',
      passed: duplicateGrids == 0,
      detail: duplicateGrids == 0
          ? 'Un seul tarif actif par rubrique et cible.'
          : '$duplicateGrids doublon(s) de tarifs actifs détecté(s).',
    ));

    final duplicatePackages = await _scalar('''
      SELECT COUNT(*) FROM (
        SELECT type, fee_id,
               COALESCE(student_id, ''), COALESCE(family_id, ''), COUNT(*) n
        FROM packages
        WHERE active = 1
        GROUP BY type, fee_id, COALESCE(student_id, ''), COALESCE(family_id, '')
        HAVING n > 1
      ) x
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Forfaits actifs',
      passed: duplicatePackages == 0,
      detail: duplicatePackages == 0
          ? 'Aucun forfait actif dupliqué pour une même cible et rubrique.'
          : '$duplicatePackages doublon(s) de forfaits actifs détecté(s).',
    ));

    final familyPackageWithoutFamily = await _scalar('''
      SELECT COUNT(*) FROM dues d
      JOIN packages p ON p.id = d.package_id
      WHERE p.type = 'family' AND d.family_id IS NULL
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Échéances forfait familial',
      passed: familyPackageWithoutFamily == 0,
      detail: familyPackageWithoutFamily == 0
          ? 'Toutes les échéances de forfait familial sont rattachées à une famille.'
          : '$familyPackageWithoutFamily échéance(s) familiale(s) sont mal rattachées.',
    ));

    final classesOverCapacity = await _scalar('''
      SELECT COUNT(*) FROM (
        SELECT c.id, c.capacity, COUNT(se.student_id) students_count
        FROM classrooms c
        LEFT JOIN student_enrollments se ON se.classroom_id = c.id
          AND se.school_year_id = (SELECT id FROM school_years WHERE is_active=1 LIMIT 1)
          AND se.status = 'active'
        WHERE c.active = 1 AND c.capacity IS NOT NULL
        GROUP BY c.id, c.capacity
        HAVING students_count > c.capacity
      ) x
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Capacité des classes',
      passed: classesOverCapacity == 0,
      detail: classesOverCapacity == 0
          ? 'Aucune classe active ne dépasse sa capacité.'
          : '$classesOverCapacity classe(s) dépassent leur capacité.',
    ));

    final missingRegistrationNumbers = await _scalar('''
      SELECT COUNT(*) FROM students
      WHERE registration_number IS NULL OR trim(registration_number) = ''
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Matricules élèves',
      passed: missingRegistrationNumbers == 0,
      detail: missingRegistrationNumbers == 0
          ? 'Tous les élèves ont un matricule.'
          : '$missingRegistrationNumbers élève(s) sans matricule.',
    ));

    final invalidCreditAllocations = await _scalar('''
      SELECT COUNT(*) FROM payer_credit_allocations pca
      LEFT JOIN payer_credits pc ON pc.id=pca.credit_id
      LEFT JOIN dues d ON d.id=pca.due_id
      WHERE pca.amount <= 0 OR pc.id IS NULL OR d.id IS NULL
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Affectations des avoirs',
      passed: invalidCreditAllocations == 0,
      detail: invalidCreditAllocations == 0
          ? 'Toutes les utilisations d’avoirs sont positives et rattachées à une échéance valide.'
          : '$invalidCreditAllocations affectation(s) d’avoir incohérente(s).',
    ));

    final invalidTransfers = await _scalar('''
      SELECT COUNT(*) FROM cash_transfers
      WHERE amount <= 0 OR from_account_id = to_account_id OR status NOT IN ('posted','annule')
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Transferts de trésorerie',
      passed: invalidTransfers == 0,
      detail: invalidTransfers == 0
          ? 'Les transferts internes sont cohérents.'
          : '$invalidTransfers transfert(s) interne(s) incohérent(s).',
    ));

    final invalidPaymentConfiguration = await _scalar('''
      SELECT COUNT(*) FROM payment_methods
      WHERE account_type IS NULL OR account_type NOT IN ('cash','mobile','bank')
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Configuration des moyens de paiement',
      passed: invalidPaymentConfiguration == 0,
      detail: invalidPaymentConfiguration == 0
          ? 'Chaque moyen de paiement cible un type de compte valide.'
          : '$invalidPaymentConfiguration moyen(s) de paiement ont une configuration invalide.',
    ));

    final invalidBillingBatches = await _scalar('''
      SELECT COUNT(*) FROM billing_batches b
      WHERE b.status='posted' AND (
        b.generated_count != (SELECT COUNT(*) FROM dues d WHERE d.billing_batch_id=b.id)
        OR b.total_amount != COALESCE((SELECT SUM(d.amount_due) FROM dues d WHERE d.billing_batch_id=b.id),0)
      )
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Lots de facturation',
      passed: invalidBillingBatches == 0,
      detail: invalidBillingBatches == 0
          ? 'Les totaux des lots correspondent aux échéances générées.'
          : '$invalidBillingBatches lot(s) ne correspondent pas à leurs échéances.',
    ));

    final invalidRecoveryActions = await _scalar('''
      SELECT COUNT(*) FROM recovery_actions ra
      JOIN dues d ON d.id=ra.due_id
      WHERE ra.promise_amount IS NOT NULL
        AND (ra.promise_amount <= 0 OR ra.promise_amount > d.amount_due)
    ''');
    checks.add(IntegrityCheckResult(
      label: 'Actions de recouvrement',
      passed: invalidRecoveryActions == 0,
      detail: invalidRecoveryActions == 0
          ? 'Les promesses de paiement enregistrées sont cohérentes.'
          : '$invalidRecoveryActions action(s) de recouvrement ont un montant incohérent.',
    ));

    final duplicateOpenCashSessions = await _scalar('''
      SELECT COUNT(*) FROM (
        SELECT cash_account_id,COUNT(*) n FROM cash_sessions WHERE status='open'
        GROUP BY cash_account_id HAVING n>1
      ) x
    ''');
    checks.add(IntegrityCheckResult(label:'Sessions de caisse ouvertes',passed:duplicateOpenCashSessions==0,detail:duplicateOpenCashSessions==0?'Une seule session ouverte au maximum par caisse.':'$duplicateOpenCashSessions caisse(s) possèdent plusieurs sessions ouvertes.'));

    final invalidApprovedExpenses = await _scalar("SELECT COUNT(*) FROM expenses WHERE approval_status='approved' AND status NOT IN ('posted','annule')");
    checks.add(IntegrityCheckResult(label:'Dépenses approuvées',passed:invalidApprovedExpenses==0,detail:invalidApprovedExpenses==0?'Toutes les dépenses approuvées ont un état comptable cohérent.':'$invalidApprovedExpenses dépense(s) approuvée(s) ont un état incohérent.'));

    final orphanEnrollments = await _scalar('''SELECT COUNT(*) FROM student_enrollments se LEFT JOIN students s ON s.id=se.student_id LEFT JOIN school_years sy ON sy.id=se.school_year_id LEFT JOIN classrooms c ON c.id=se.classroom_id WHERE s.id IS NULL OR sy.id IS NULL OR c.id IS NULL''');
    checks.add(IntegrityCheckResult(label:'Inscriptions annuelles',passed:orphanEnrollments==0,detail:orphanEnrollments==0?'Toutes les inscriptions annuelles pointent vers un élève, une année et une classe valides.':'$orphanEnrollments inscription(s) annuelle(s) orpheline(s).'));

    final staleLegacyPins = await _scalar("SELECT COUNT(*) FROM app_users WHERE active=1 AND COALESCE(pin_algorithm,'sha256-legacy')!='pbkdf2-sha256'");
    checks.add(IntegrityCheckResult(label:'Protection des PIN',passed:staleLegacyPins==0,detail:staleLegacyPins==0?'Tous les PIN actifs utilisent PBKDF2-SHA256.':'$staleLegacyPins compte(s) utilisent encore le hash historique ; reconnectez-vous une fois avec ces comptes pour les renforcer automatiquement.'));

    final incompleteFiles = await _scalar('''
      SELECT COUNT(*) FROM students s
      WHERE EXISTS (
        SELECT 1 FROM document_requirements dr
        WHERE dr.active=1 AND dr.required=1
          AND NOT EXISTS (SELECT 1 FROM student_documents sd WHERE sd.student_id=s.id AND lower(trim(sd.document_type))=lower(trim(dr.name)))
      )
    ''');
    checks.add(IntegrityCheckResult(label:'Complétude documentaire',passed:incompleteFiles==0,detail:incompleteFiles==0?'Tous les dossiers contiennent les pièces obligatoires configurées.':'$incompleteFiles élève(s) ont au moins une pièce obligatoire manquante.'));

    final invalidRefundTreasury = await _scalar('''
      SELECT COUNT(*) FROM payment_refunds r
      LEFT JOIN cash_accounts a ON a.id=r.cash_account_id
      WHERE r.amount<=0 OR r.cash_account_id IS NULL OR a.id IS NULL
    ''');
    checks.add(IntegrityCheckResult(label:'Remboursements et trésorerie',passed:invalidRefundTreasury==0,detail:invalidRefundTreasury==0?'Tous les remboursements récents sont rattachés à une caisse ou un compte valide.':'$invalidRefundTreasury remboursement(s) sans mouvement de trésorerie correctement identifié.'));

    final invalidRecurringTemplates = await _scalar('''
      SELECT COUNT(*) FROM recurring_expense_templates t
      LEFT JOIN expense_categories c ON c.id=t.category_id
      WHERE t.amount<=0 OR t.day_of_month<1 OR t.day_of_month>28 OR t.frequency NOT IN ('monthly','quarterly','annual') OR c.id IS NULL
    ''');
    checks.add(IntegrityCheckResult(label:'Dépenses récurrentes',passed:invalidRecurringTemplates==0,detail:invalidRecurringTemplates==0?'Tous les modèles récurrents sont cohérents.':'$invalidRecurringTemplates modèle(s) de dépense récurrente incohérent(s).'));

    final activeEmployeesWithoutContract = await _scalar("SELECT COUNT(*) FROM employees e WHERE e.status='active' AND NOT EXISTS(SELECT 1 FROM employment_contracts c WHERE c.employee_id=e.id AND c.status='active' AND c.start_date<=datetime('now') AND (c.end_date IS NULL OR c.end_date>=datetime('now')))");
    checks.add(IntegrityCheckResult(label:'RH — contrats actifs',passed:activeEmployeesWithoutContract==0,detail:activeEmployeesWithoutContract==0?'Chaque employé actif possède un contrat actif.':'$activeEmployeesWithoutContract employé(s) actif(s) sans contrat actif.'));

    final invalidPayrollEntries = await _scalar('''SELECT COUNT(*) FROM payroll_entries WHERE base_salary<0 OR gross_salary<0 OR total_deductions<0 OR net_salary<0 OR net_salary != CASE WHEN gross_salary-total_deductions<0 THEN 0 ELSE gross_salary-total_deductions END''');
    checks.add(IntegrityCheckResult(label:'RH — calculs de paie',passed:invalidPayrollEntries==0,detail:invalidPayrollEntries==0?'Les montants de paie sont cohérents.':'$invalidPayrollEntries bulletin(s) de paie ont un calcul incohérent.'));

    final orphanPayrollExpenses = await _scalar("SELECT COUNT(*) FROM payroll_entries pe LEFT JOIN expenses e ON e.id=pe.expense_id WHERE pe.status='paid' AND (pe.expense_id IS NULL OR e.id IS NULL)");
    checks.add(IntegrityCheckResult(label:'RH — paie / dépenses',passed:orphanPayrollExpenses==0,detail:orphanPayrollExpenses==0?'Chaque paie payée est reliée à une dépense GesApp.':'$orphanPayrollExpenses paie(s) payée(s) ne sont pas reliées à une dépense.'));

    final invalidAdvances = await _scalar("SELECT COUNT(*) FROM salary_advances WHERE amount<=0 OR balance<0 OR balance>amount");
    checks.add(IntegrityCheckResult(label:'RH — avances sur salaire',passed:invalidAdvances==0,detail:invalidAdvances==0?'Les avances et leurs soldes sont cohérents.':'$invalidAdvances avance(s) présentent un solde incohérent.'));

    final orphanAssets = await _scalar('''SELECT COUNT(*) FROM assets a LEFT JOIN asset_categories c ON c.id=a.category_id LEFT JOIN asset_locations l ON l.id=a.current_location_id LEFT JOIN employees e ON e.id=a.current_employee_id WHERE c.id IS NULL OR (a.current_location_id IS NOT NULL AND l.id IS NULL) OR (a.current_employee_id IS NOT NULL AND e.id IS NULL)''');
    checks.add(IntegrityCheckResult(label:'Patrimoine — rattachements',passed:orphanAssets==0,detail:orphanAssets==0?'Tous les biens sont rattachés à des catégories, localisations et responsables valides.':'$orphanAssets bien(s) ont un rattachement patrimonial incohérent.'));

    final invalidAssetValues = await _scalar("SELECT COUNT(*) FROM assets WHERE acquisition_value<0 OR condition NOT IN ('new','good','fair','repair','broken') OR status NOT IN ('in_service','stock','maintenance','out_of_service','missing','disposed')");
    checks.add(IntegrityCheckResult(label:'Patrimoine — état des biens',passed:invalidAssetValues==0,detail:invalidAssetValues==0?'Les valeurs, états et statuts patrimoniaux sont cohérents.':'$invalidAssetValues bien(s) présentent une valeur, un état ou un statut invalide.'));

    final invalidInventory = await _scalar("SELECT COUNT(*) FROM asset_inventory_items WHERE result NOT IN ('not_checked','found','missing','moved','damaged')");
    checks.add(IntegrityCheckResult(label:'Patrimoine — inventaires',passed:invalidInventory==0,detail:invalidInventory==0?'Les résultats des campagnes d’inventaire sont cohérents.':'$invalidInventory ligne(s) d’inventaire ont un résultat invalide.'));

    final invalidMaintenance = await _scalar("SELECT COUNT(*) FROM asset_maintenance m LEFT JOIN assets a ON a.id=m.asset_id WHERE a.id IS NULL OR m.cost<0 OR m.status NOT IN ('planned','in_progress','completed','cancelled')");
    checks.add(IntegrityCheckResult(label:'Patrimoine — maintenance',passed:invalidMaintenance==0,detail:invalidMaintenance==0?'Toutes les interventions patrimoniales sont cohérentes.':'$invalidMaintenance intervention(s) de maintenance sont incohérentes.'));

    return DataIntegrityReport(
      generatedAt: DateTime.now(),
      checks: checks,
    );
  }
}
