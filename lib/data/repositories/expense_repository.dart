import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import 'cash_rules.dart';
import '../models/expense.dart';

class ExpenseRepository {
  ExpenseRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<List<ExpenseItem>> list({String? approvalStatus,String query='',String? categoryId,DateTime? from,DateTime? to,int? limit,int? offset}) async {
    final where=<String>["e.status != 'annule'"];final args=<Object?>[];
    if(approvalStatus!=null){where.add('e.approval_status=?');args.add(approvalStatus);}final q=query.trim();if(q.isNotEmpty){where.add('(e.expense_number LIKE ? OR e.description LIKE ? OR e.beneficiary LIKE ? OR e.external_reference LIKE ?)');args.addAll(List.filled(4,'%$q%'));}if(categoryId!=null){where.add('e.category_id=?');args.add(categoryId);}if(from!=null){where.add('e.spent_at>=?');args.add(from.toIso8601String());}if(to!=null){where.add('e.spent_at<=?');args.add(to.toIso8601String());}
    final sql=StringBuffer("SELECT e.*,c.name category_name FROM expenses e JOIN expense_categories c ON c.id=e.category_id WHERE ${where.join(' AND ')} ORDER BY CASE e.approval_status WHEN 'pending' THEN 0 WHEN 'rejected' THEN 1 ELSE 2 END,e.spent_at DESC");if(limit!=null){sql.write(' LIMIT ?');args.add(limit);if(offset!=null){sql.write(' OFFSET ?');args.add(offset);}}
    final rows=await _database.db.rawQuery(sql.toString(),args);return rows.map(_fromRow).toList();
  }

  ExpenseItem _fromRow(Map<String, Object?> row) => ExpenseItem(
        id: row['id'] as String,
        categoryName: row['category_name'] as String,
        amount: row['amount'] as int,
        spentAt: DateTime.parse(row['spent_at'] as String),
        description: row['description'] as String?,
        expenseNumber: row['expense_number'] as String?,
        beneficiary: row['beneficiary'] as String?,
        paymentMethod: row['payment_method'] as String?,
        cashAccountId: row['cash_account_id'] as String?,
        externalReference: row['external_reference'] as String?,
        proofPath: row['proof_path'] as String?,
        status: row['status'] as String,
        approvalStatus: (row['approval_status'] as String?) ?? 'approved',
        submittedBy: row['submitted_by'] as String?,
        submittedAt: row['submitted_at'] == null ? null : DateTime.tryParse(row['submitted_at'] as String),
        reviewedBy: row['reviewed_by'] as String?,
        reviewedAt: row['reviewed_at'] == null ? null : DateTime.tryParse(row['reviewed_at'] as String),
        approvalNote: row['approval_note'] as String?,
      );

  Future<List<ExpenseCategory>> categories() async {
    final rows = await _database.db.query('expense_categories', where: 'active = 1', orderBy: 'name');
    return rows.map((row) => ExpenseCategory(id: row['id'] as String, name: row['name'] as String)).toList();
  }

  Future<ExpenseCategory> addCategory(String name) async {
    _requireExpensePermission();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom de catégorie est obligatoire.');
    final existing = await _database.db.rawQuery('SELECT id, name FROM expense_categories WHERE lower(name) = lower(?) LIMIT 1', [trimmed]);
    if (existing.isNotEmpty) {
      final row = existing.first;
      await _database.db.update('expense_categories', {'active': 1}, where: 'id = ?', whereArgs: [row['id']]);
      return ExpenseCategory(id: row['id'] as String, name: row['name'] as String);
    }
    final id = _uuid.v4();
    await _database.db.insert('expense_categories', {'id': id, 'name': trimmed, 'active': 1});
    await _audit('expense_category', id, 'create', trimmed);
    return ExpenseCategory(id: id, name: trimmed);
  }

  /// Compatibilité interne : crée une dépense déjà approuvée.
  Future<void> add({
    required String categoryId,
    required int amount,
    required String description,
    DateTime? spentAt,
    String? beneficiary,
    String? paymentMethod,
    String? cashAccountId,
    String? externalReference,
    String? proofPath,
  }) => _create(
        categoryId: categoryId,
        amount: amount,
        description: description,
        spentAt: spentAt,
        beneficiary: beneficiary,
        paymentMethod: paymentMethod,
        cashAccountId: cashAccountId,
        externalReference: externalReference,
        proofPath: proofPath,
        submitOnly: false,
      );

  /// Flux normal UI : la dépense est soumise puis doit être approuvée avant
  /// d'entrer dans la trésorerie et les rapports.
  Future<void> submitForApproval({
    required String categoryId,
    required int amount,
    required String description,
    DateTime? spentAt,
    String? beneficiary,
    String? paymentMethod,
    String? cashAccountId,
    String? externalReference,
    String? proofPath,
  }) => _create(
        categoryId: categoryId,
        amount: amount,
        description: description,
        spentAt: spentAt,
        beneficiary: beneficiary,
        paymentMethod: paymentMethod,
        cashAccountId: cashAccountId,
        externalReference: externalReference,
        proofPath: proofPath,
        submitOnly: true,
      );

  Future<void> _create({
    required String categoryId,
    required int amount,
    required String description,
    required bool submitOnly,
    DateTime? spentAt,
    String? beneficiary,
    String? paymentMethod,
    String? cashAccountId,
    String? externalReference,
    String? proofPath,
  }) async {
    _requireExpensePermission();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Le montant doit être positif');
    final id = _uuid.v4();
    final now = DateTime.now();
    final count = firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM expenses WHERE strftime("%Y",created_at)=?', [now.year.toString()])) ?? 0;
    final expenseNumber = 'DEP-${now.year}-${(count + 1).toString().padLeft(6, '0')}';
    await _database.db.transaction((txn) async {
      if (paymentMethod != null && paymentMethod.trim().isNotEmpty) {
        await ensurePaymentMethodMatchesAccount(txn, paymentMethod, cashAccountId);
        if (await paymentMethodRequiresReference(txn, paymentMethod) && (externalReference ?? '').trim().isEmpty) {
          throw StateError('Une référence externe est obligatoire pour « $paymentMethod ».');
        }
      }
      if (!submitOnly) {
        await ensureCashMovementAllowed(txn, cashAccountId);
      }
      await txn.insert('expenses', {
        'id': id,
        'category_id': categoryId,
        'amount': amount,
        'spent_at': (spentAt ?? now).toIso8601String(),
        'description': description.trim(),
        'expense_number': expenseNumber,
        'beneficiary': beneficiary?.trim(),
        'payment_method': paymentMethod,
        'cash_account_id': cashAccountId,
        'external_reference': externalReference?.trim(),
        'proof_path': proofPath,
        'approval_status': submitOnly ? 'pending' : 'approved',
        'submitted_by': OperatorSession.userId,
        'submitted_at': now.toIso8601String(),
        'reviewed_by': submitOnly ? null : OperatorSession.userId,
        'reviewed_at': submitOnly ? null : now.toIso8601String(),
        'status': submitOnly ? 'pending' : 'posted',
        'created_at': now.toIso8601String(),
      });
      await txn.insert('audit_log', {
        'entity_type': 'expense', 'entity_id': id,
        'action': submitOnly ? 'submit' : 'create_approved',
        'new_value': '$amount/$expenseNumber',
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': now.toIso8601String(),
      });
    });
  }

  Future<void> approveExpense({
    required String expenseId, String? note}) async {
      BusinessWriteGuard.ensureAllowed('approveExpense');
      
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('expenses', where: 'id=?', whereArgs: [expenseId], limit: 1);
      if (rows.isEmpty) throw StateError('Dépense introuvable.');
      if (rows.first['approval_status'] != 'pending') throw StateError('Cette dépense n’est plus en attente.');
      final method = rows.first['payment_method'] as String?;
      if (method != null && method.trim().isNotEmpty) {
        await ensurePaymentMethodMatchesAccount(txn, method, rows.first['cash_account_id'] as String?);
        if (await paymentMethodRequiresReference(txn, method) && ((rows.first['external_reference'] as String?) ?? '').trim().isEmpty) {
          throw StateError('Une référence externe est obligatoire pour « $method ».');
        }
      }
      await ensureCashMovementAllowed(txn, rows.first['cash_account_id'] as String?);
      await txn.update('expenses', {
        'approval_status': 'approved', 'status': 'posted', 'reviewed_by': OperatorSession.userId,
        'reviewed_at': now, 'approval_note': note?.trim(),
      }, where: 'id=?', whereArgs: [expenseId]);
      await txn.insert('audit_log', {
        'entity_type': 'expense', 'entity_id': expenseId, 'action': 'approve', 'new_value': note?.trim() ?? 'approved',
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': now,
      });
    });
  }

  Future<void> resubmitExpense({
    required String expenseId, String? note}) async {
      BusinessWriteGuard.ensureAllowed('resubmitExpense');
      
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('expenses', where: 'id=?', whereArgs: [expenseId], limit: 1);
      if (rows.isEmpty) throw StateError('Dépense introuvable.');
      if (rows.first['approval_status'] != 'rejected') throw StateError('Seule une dépense rejetée peut être resoumise.');
      await txn.update('expenses', {
        'approval_status': 'pending', 'status': 'pending', 'submitted_by': OperatorSession.userId,
        'submitted_at': now, 'reviewed_by': null, 'reviewed_at': null, 'approval_note': note?.trim(),
      }, where: 'id=?', whereArgs: [expenseId]);
      await txn.insert('audit_log', {
        'entity_type': 'expense', 'entity_id': expenseId, 'action': 'resubmit', 'new_value': note?.trim() ?? 'pending',
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': now,
      });
    });
  }

  Future<void> rejectExpense({
    required String expenseId, required String reason}) async {
      BusinessWriteGuard.ensureAllowed('rejectExpense');
      
    if (reason.trim().isEmpty) throw ArgumentError('Le motif de rejet est obligatoire.');
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('expenses', where: 'id=?', whereArgs: [expenseId], limit: 1);
      if (rows.isEmpty) throw StateError('Dépense introuvable.');
      if (rows.first['approval_status'] != 'pending') throw StateError('Cette dépense n’est plus en attente.');
      await txn.update('expenses', {
        'approval_status': 'rejected', 'status': 'rejected', 'reviewed_by': OperatorSession.userId,
        'reviewed_at': now, 'approval_note': reason.trim(),
      }, where: 'id=?', whereArgs: [expenseId]);
      await txn.insert('audit_log', {
        'entity_type': 'expense', 'entity_id': expenseId, 'action': 'reject', 'new_value': reason.trim(),
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': now,
      });
    });
  }

  Future<void> cancelExpense({
    required String expenseId, required String reason}) async {
      BusinessWriteGuard.ensureAllowed('cancelExpense');
      
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw ArgumentError('Un motif d’annulation est obligatoire.');
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('expenses', where: 'id = ?', whereArgs: [expenseId], limit: 1);
      if (rows.isEmpty) throw StateError('Dépense introuvable.');
      final expense = rows.first;
      if (expense['status'] != 'posted' || expense['approval_status'] != 'approved') {
        throw StateError('Seule une dépense approuvée peut être annulée.');
      }
      await ensureCashMovementAllowed(txn, expense['cash_account_id'] as String?);
      await txn.update('expenses', {'status': 'annule'}, where: 'id = ?', whereArgs: [expenseId]);
      await txn.insert('audit_log', {
        'entity_type': 'expense', 'entity_id': expenseId, 'action': 'cancel',
        'old_value': '${expense['amount']}/${expense['description'] ?? ''}', 'new_value': trimmed,
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': now,
      });
    });
  }

  Future<void> _audit(String entityType, String entityId, String action, String value) => _database.db.insert('audit_log', {
        'entity_type': entityType, 'entity_id': entityId, 'action': action, 'new_value': value,
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': DateTime.now().toIso8601String(),
      });

  Future<List<Map<String, Object?>>> recurringTemplates({bool includeInactive = false}) => _database.db.rawQuery('''
    SELECT t.*, c.name category_name, a.name account_name
    FROM recurring_expense_templates t
    JOIN expense_categories c ON c.id=t.category_id
    LEFT JOIN cash_accounts a ON a.id=t.cash_account_id
    ${includeInactive ? '' : 'WHERE t.active=1'}
    ORDER BY t.active DESC,t.next_due_at,t.name COLLATE NOCASE
  ''');

  Future<void> saveRecurringTemplate({
    String? id,
    required String name,
    required String categoryId,
    required int amount,
    String? beneficiary,
    String? description,
    String? paymentMethod,
    String? cashAccountId,
    String frequency = 'monthly',
    int dayOfMonth = 1,
    DateTime? nextDueAt,
    bool? active,
  }) async {
    BusinessWriteGuard.ensureAllowed('saveRecurringTemplate');
    if (name.trim().isEmpty || amount <= 0) throw ArgumentError('Nom et montant obligatoires.');
    if (!const {'monthly','quarterly','annual'}.contains(frequency)) throw ArgumentError('Fréquence invalide.');
    if (dayOfMonth < 1 || dayOfMonth > 28) throw ArgumentError('Le jour doit être compris entre 1 et 28.');
    final now = DateTime.now();
    final templateId = id ?? _uuid.v4();
    await _database.db.transaction((txn) async {
      Map<String, Object?>? existing;
      if (id != null) {
        final rows = await txn.query('recurring_expense_templates', where: 'id=?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) throw StateError('Modèle récurrent introuvable.');
        existing = rows.first;
      }
      if ((paymentMethod ?? '').trim().isNotEmpty) {
        await ensurePaymentMethodMatchesAccount(txn, paymentMethod!, cashAccountId);
      }
      final effectiveActive = active ?? ((existing?['active'] as int? ?? 1) == 1);
      final scheduleChanged = existing != null &&
          (existing['frequency'] != frequency || (existing['day_of_month'] as int? ?? 1) != dayOfMonth);
      DateTime effectiveDue;
      if (nextDueAt != null && !scheduleChanged) {
        effectiveDue = nextDueAt;
      } else {
        final anchor = existing?['next_due_at'] == null ? null : DateTime.tryParse(existing!['next_due_at'] as String);
        effectiveDue = _nextDueFromNow(now, frequency, dayOfMonth, anchor: anchor);
      }
      final values = <String,Object?>{
        'id': templateId,
        'name': name.trim(),
        'category_id': categoryId,
        'amount': amount,
        'beneficiary': beneficiary?.trim(),
        'description': description?.trim(),
        'payment_method': paymentMethod,
        'cash_account_id': cashAccountId,
        'frequency': frequency,
        'day_of_month': dayOfMonth,
        'next_due_at': effectiveDue.toIso8601String(),
        'active': effectiveActive ? 1 : 0,
        'updated_at': now.toIso8601String(),
        if (id == null) 'created_at': now.toIso8601String(),
      };
      if (id == null) {
        await txn.insert('recurring_expense_templates', values);
      } else {
        await txn.update('recurring_expense_templates', values, where: 'id=?', whereArgs: [id]);
      }
      await txn.insert('audit_log', {
        'entity_type':'recurring_expense','entity_id':templateId,
        'action':id==null?'create':'update','new_value':'${name.trim()}/$amount/$frequency',
        'operator_name':OperatorSession.current,'operator_id':OperatorSession.userId,
        'operator_role':OperatorSession.role,'created_at':now.toIso8601String(),
      });
    });
  }

  Future<void> setRecurringTemplateActive(String id, bool active) async {
    BusinessWriteGuard.ensureAllowed('setRecurringTemplateActive');
    final now = DateTime.now().toIso8601String();
    await _database.db.update('recurring_expense_templates', {'active':active?1:0,'updated_at':now}, where:'id=?', whereArgs:[id]);
    await _audit('recurring_expense', id, active ? 'activate' : 'deactivate', active ? 'active' : 'inactive');
  }

  DateTime _nextDueFromNow(DateTime now, String frequency, int day, {DateTime? anchor}) {
    final step = switch (frequency) {'quarterly' => 3, 'annual' => 12, _ => 1};
    var candidate = DateTime(
      (anchor ?? now).year,
      (anchor ?? now).month,
      day.clamp(1, 28).toInt(),
    );
    while (!candidate.isAfter(now)) {
      var year = candidate.year;
      var month = candidate.month + step;
      while (month > 12) {
        month -= 12;
        year++;
      }
      candidate = DateTime(year, month, day.clamp(1, 28).toInt());
    }
    return candidate;
  }

  DateTime _nextRecurringDate(DateTime current, String frequency, int day) {
    final months = switch (frequency) {'quarterly' => 3, 'annual' => 12, _ => 1};
    var year = current.year;
    var month = current.month + months;
    while (month > 12) { month -= 12; year++; }
    return DateTime(year, month, day.clamp(1, 28).toInt());
  }

  Future<void> createExpenseFromRecurringTemplate(String templateId) async {
    BusinessWriteGuard.ensureAllowed('createExpenseFromRecurringTemplate');
    final rows = await _database.db.query('recurring_expense_templates', where:'id=? AND active=1', whereArgs:[templateId], limit:1);
    if (rows.isEmpty) throw StateError('Modèle récurrent introuvable ou désactivé.');
    final row = rows.first;
    final due = DateTime.parse(row['next_due_at'] as String);
    await submitForApproval(
      categoryId: row['category_id'] as String,
      amount: row['amount'] as int,
      description: (row['description'] as String?) ?? 'Dépense récurrente · ${row['name']}',
      spentAt: due,
      beneficiary: row['beneficiary'] as String?,
      paymentMethod: row['payment_method'] as String?,
      cashAccountId: row['cash_account_id'] as String?,
    );
    final next = _nextRecurringDate(due, row['frequency'] as String, row['day_of_month'] as int);
    await _database.db.update('recurring_expense_templates', {'next_due_at':next.toIso8601String(),'updated_at':DateTime.now().toIso8601String()}, where:'id=?', whereArgs:[templateId]);
    await _audit('recurring_expense', templateId, 'generate_request', next.toIso8601String());
  }

  void _requireExpensePermission() {
    BusinessWriteGuard.ensureAllowed('expenses.create');
    if (OperatorSession.isAuthenticated && !OperatorSession.hasPermission('expenses.create')) {
      throw StateError('Votre compte n’autorise pas la saisie des dépenses.');
    }
  }
}
