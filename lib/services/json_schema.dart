/// Tables métier portables de GesApp.
///
/// Cette liste est volontairement indépendante du moteur SQLite. Les tables
/// techniques comme `android_metadata`, `sqlite_sequence` ou les métadonnées
/// du moteur Web ne font jamais partie d'un export/import GesApp.
const List<String> gesAppPortableTables = [
  'establishments',
  'cycles',
  'classrooms',
  'families',
  'students',
  'student_status_history',
  'student_documents',
  'document_requirements',
  'fee_categories',
  'fee_targets',
  'fee_grid',
  'packages',
  'school_years',
  'student_enrollments',
  'student_class_movements',
  'app_users',
  'payment_methods',
  'cash_accounts',
  'dues',
  'payments',
  'payment_allocations',
  'payer_credits',
  'payer_credit_allocations',
  'payment_refunds',
  'cash_sessions',
  'cash_transfers',
  'billing_batches',
  'recovery_actions',
  'expense_categories',
  'expenses',
  'recurring_expense_templates',
  'student_guardians',
  'alerts',
  'audit_log',
  'hr_departments',
  'hr_positions',
  'employees',
  'employee_status_history',
  'employee_assignments',
  'employment_contracts',
  'attendance_records',
  'leave_types',
  'leave_requests',
  'salary_components',
  'employee_salary_components',
  'payroll_periods',
  'payroll_entries',
  'payroll_items',
  'salary_advances',
  'salary_advance_repayments',
  'employee_documents',
  'asset_categories',
  'asset_locations',
  'assets',
  'asset_assignments',
  'asset_movements',
  'asset_maintenance',
  'asset_inventory_sessions',
  'asset_inventory_items',
  'asset_documents',
  'asset_disposals',
  'accounting_accounts',
  'accounting_entries',
  'accounting_entry_lines',
  'accounting_settings',
  'supplier_invoices',
  'supplier_payments',
  'bank_reconciliations',
  'bank_reconciliation_items',
  'app_settings',
];

/// Valide qu'un document déclaré « export complet » contient réellement toutes
/// les tables portables du schéma actuellement ouvert.
///
/// Les anciens exports JSON sans `table_manifest` restent acceptés uniquement
/// s'ils proviennent du même schéma et contiennent déjà l'ensemble exact des
/// tables attendues. Les exports d'un schéma plus ancien sont refusés : sans
/// manifeste versionné historique, GesApp ne peut pas prouver qu'une table
/// absente signifiait « inexistante » plutôt que « perdue pendant l'export ».
void validateCompletePortableExport({
  required int sourceSchemaVersion,
  required int currentSchemaVersion,
  required Iterable<String> currentPortableTables,
  required Map<String, dynamic> sourceTables,
  Object? tableManifest,
}) {
  if (sourceSchemaVersion != currentSchemaVersion) {
    throw FormatException(
      'Version de schéma JSON incompatible : $sourceSchemaVersion au lieu de '
      '$currentSchemaVersion. Réexportez la sauvegarde avec la version actuelle de GesApp.',
    );
  }

  final expected = currentPortableTables.toSet();
  final provided = sourceTables.keys.toSet();
  final missing = expected.difference(provided).toList()..sort();
  final unexpected = provided.difference(expected).toList()..sort();
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    final details = <String>[
      if (missing.isNotEmpty) 'manquantes : ${missing.join(', ')}',
      if (unexpected.isNotEmpty) 'inattendues : ${unexpected.join(', ')}',
    ].join(' ; ');
    throw FormatException('Export GesApp incomplet ou incompatible ($details).');
  }

  // Les exports 2.2.2+43 et suivants embarquent explicitement ce manifeste.
  // Pour un export legacy de même schéma, l'ensemble exact des clés de tables
  // ci-dessus suffit à prouver la complétude.
  if (tableManifest == null) return;
  if (tableManifest is! List || tableManifest.any((value) => value is! String)) {
    throw const FormatException('Manifeste des tables JSON invalide.');
  }

  final manifest = tableManifest.cast<String>().toSet();
  final duplicateCount = tableManifest.length - manifest.length;
  if (duplicateCount != 0 || manifest.length != expected.length || !manifest.containsAll(expected)) {
    throw const FormatException('Manifeste des tables JSON incomplet ou incohérent.');
  }
  if (manifest.length != provided.length || !manifest.containsAll(provided)) {
    throw const FormatException('Le manifeste JSON ne correspond pas aux tables réellement exportées.');
  }
}
