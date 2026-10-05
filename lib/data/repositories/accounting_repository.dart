import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import 'cash_rules.dart';

class AccountingRepository {
  AccountingRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<String> _setting(DatabaseExecutor db, String key, String fallback) async {
    final rows = await db.query('accounting_settings', columns: ['value'], where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? fallback : '${rows.first['value']}';
  }

  Future<void> synchronize() => _database.db.transaction((txn) async {
        final receivable = await _setting(txn, 'student_receivable_account', '411100');
        final revenue = await _setting(txn, 'school_revenue_account', '706100');
        final payable = await _setting(txn, 'supplier_payable_account', '401100');

        // 1) La facturation crée la créance : débit famille/élève, crédit produit.
        final dues = await txn.rawQuery('''
          SELECT d.*,f.name fee_name,s.last_name||' '||s.first_name student_name
          FROM dues d JOIN fee_categories f ON f.id=d.fee_id
          JOIN students s ON s.id=d.student_id
        ''');
        for (final row in dues) {
          final amount = (row['amount_due'] as num).toInt();
          await _post(txn,
              sourceType: 'due', sourceId: '${row['id']}', journalCode: 'VE',
              date: '${row['created_at']}', reference: 'ECH-${row['period_key']}',
              description: '${row['fee_name']} — ${row['student_name']}',
              debitAccount: receivable, creditAccount: revenue, amount: amount);
        }

        // 2) Le règlement solde la créance. Un paiement sans échéance reste
        // comptabilisé directement en produit (cas exceptionnel/avance libre).
        final payments = await txn.rawQuery('''
          SELECT p.*,ca.type account_type,
            COALESCE(s.last_name||' '||s.first_name,f.name,'Paiement scolaire') beneficiary,
            COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa WHERE pa.payment_id=p.id),0) allocated_amount
          FROM payments p LEFT JOIN cash_accounts ca ON ca.id=p.cash_account_id
          LEFT JOIN students s ON s.id=p.student_id LEFT JOIN families f ON f.id=p.family_id
        ''');
        for (final row in payments) {
          final amount = (row['amount'] as num).toInt();
          final allocated = (row['allocated_amount'] as num?)?.toInt() ?? 0;
          final treasury = _treasuryAccount(row['account_type'] as String?);
          final credit = allocated > 0 ? receivable : revenue;
          await _post(txn,
              sourceType: 'payment', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
              date: '${row['paid_at']}', reference: '${row['receipt_number']}',
              description: 'Encaissement — ${row['beneficiary']}', debitAccount: treasury,
              creditAccount: credit, amount: amount);
          if (row['status'] != 'posted' && row['cancelled_at'] != null) {
            await _post(txn,
                sourceType: 'payment_cancel', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
                date: '${row['cancelled_at']}', reference: 'ANN-${row['receipt_number']}',
                description: 'Contre-passation — ${row['cancel_reason'] ?? row['beneficiary']}',
                debitAccount: credit, creditAccount: treasury, amount: amount);
          }
        }

        final refunds = await txn.rawQuery('''
          SELECT r.*,p.receipt_number,p.cash_account_id,ca.type account_type,
            COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa WHERE pa.payment_id=p.id),0) allocated_amount
          FROM payment_refunds r JOIN payments p ON p.id=r.payment_id
          LEFT JOIN cash_accounts ca ON ca.id=COALESCE(r.cash_account_id,p.cash_account_id)
        ''');
        for (final row in refunds) {
          final amount = (row['amount'] as num).toInt();
          final allocated = (row['allocated_amount'] as num?)?.toInt() ?? 0;
          final treasury = _treasuryAccount(row['account_type'] as String?);
          await _post(txn,
              sourceType: 'refund', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
              date: '${row['refunded_at']}', reference: 'R-${row['receipt_number']}',
              description: 'Remboursement — ${row['reason']}',
              debitAccount: allocated > 0 ? receivable : revenue, creditAccount: treasury, amount: amount);
        }

        // Dépenses payées immédiatement.
        final expenses = await txn.rawQuery('''
          SELECT e.*,ec.name category,ca.type account_type FROM expenses e
          JOIN expense_categories ec ON ec.id=e.category_id
          LEFT JOIN cash_accounts ca ON ca.id=e.cash_account_id
          WHERE e.approval_status='approved'
        ''');
        for (final row in expenses) {
          final amount = (row['amount'] as num).toInt();
          final charge = _expenseAccount('${row['category']}');
          final treasury = _treasuryAccount(row['account_type'] as String?);
          await _post(txn,
              sourceType: 'expense', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
              date: '${row['spent_at']}', reference: '${row['expense_number'] ?? row['id']}',
              description: '${row['category']} — ${row['description'] ?? row['beneficiary'] ?? ''}',
              debitAccount: charge, creditAccount: treasury, amount: amount);
          if (row['status'] != 'posted') {
            await _post(txn,
                sourceType: 'expense_cancel', sourceId: '${row['id']}', journalCode: 'OD',
                date: '${row['reviewed_at'] ?? row['created_at']}', reference: 'ANN-${row['expense_number'] ?? row['id']}',
                description: 'Contre-passation de dépense', debitAccount: treasury,
                creditAccount: charge, amount: amount);
          }
        }

        // Factures fournisseurs : dette à la réception, règlement séparé.
        final supplierInvoices = await txn.query('supplier_invoices');
        for (final row in supplierInvoices) {
          await _post(txn,
              sourceType: 'supplier_invoice', sourceId: '${row['id']}', journalCode: 'AC',
              date: '${row['invoice_date']}', reference: '${row['invoice_number']}',
              description: '${row['supplier_name']} — ${row['description']}',
              debitAccount: '${row['expense_account_code']}', creditAccount: payable,
              amount: (row['amount'] as num).toInt());
        }
        final supplierPayments = await txn.rawQuery('''
          SELECT sp.*,si.invoice_number,si.supplier_name,ca.type account_type
          FROM supplier_payments sp JOIN supplier_invoices si ON si.id=sp.supplier_invoice_id
          JOIN cash_accounts ca ON ca.id=sp.cash_account_id
        ''');
        for (final row in supplierPayments) {
          await _post(txn,
              sourceType: 'supplier_payment', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
              date: '${row['paid_at']}', reference: '${row['reference'] ?? row['invoice_number']}',
              description: 'Règlement fournisseur — ${row['supplier_name']}', debitAccount: payable,
              creditAccount: _treasuryAccount(row['account_type'] as String?), amount: (row['amount'] as num).toInt());
        }

        final transfers = await txn.rawQuery('''
          SELECT t.*,fa.type from_type,ta.type to_type,fa.name from_name,ta.name to_name
          FROM cash_transfers t JOIN cash_accounts fa ON fa.id=t.from_account_id
          JOIN cash_accounts ta ON ta.id=t.to_account_id WHERE t.status='posted'
        ''');
        for (final row in transfers) {
          await _post(txn, sourceType: 'transfer', sourceId: '${row['id']}', journalCode: 'TR',
              date: '${row['transferred_at']}', reference: '${row['reference'] ?? row['id']}',
              description: 'Transfert ${row['from_name']} → ${row['to_name']}',
              debitAccount: _treasuryAccount(row['to_type'] as String?),
              creditAccount: _treasuryAccount(row['from_type'] as String?), amount: (row['amount'] as num).toInt());
        }

        final assetSales = await txn.rawQuery('''
          SELECT ad.*,a.asset_number,a.name asset_name,ca.type account_type
          FROM asset_disposals ad JOIN assets a ON a.id=ad.asset_id
          JOIN cash_accounts ca ON ca.id=ad.cash_account_id
          WHERE ad.disposal_type='sale' AND ad.sale_amount>0
        ''');
        for (final row in assetSales) {
          await _post(txn, sourceType: 'asset_sale', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
              date: '${row['disposal_date']}', reference: '${row['reference'] ?? 'CESS-${row['asset_number']}'}',
              description: 'Cession patrimoine — ${row['asset_number']} · ${row['asset_name']}',
              debitAccount: _treasuryAccount(row['account_type'] as String?), creditAccount: '775100', amount: (row['sale_amount'] as num).toInt());
        }

        final advances = await txn.rawQuery('''
          SELECT a.*,ca.type account_type,e.last_name||' '||e.first_name employee
          FROM salary_advances a JOIN employees e ON e.id=a.employee_id
          LEFT JOIN cash_accounts ca ON ca.id=a.cash_account_id WHERE a.status!='annule'
        ''');
        for (final row in advances) {
          await _post(txn, sourceType: 'salary_advance', sourceId: '${row['id']}', journalCode: _journal(row['account_type'] as String?),
              date: '${row['granted_at']}', reference: 'AV-${row['id']}', description: 'Avance au personnel — ${row['employee']}',
              debitAccount: '421200', creditAccount: _treasuryAccount(row['account_type'] as String?), amount: (row['amount'] as num).toInt());
        }
      });

  Future<void> _post(DatabaseExecutor db, {required String sourceType, required String sourceId,
      required String journalCode, required String date, required String reference,
      required String description, required String debitAccount, required String creditAccount,
      required int amount}) async {
    if (amount <= 0) return;
    final id = '$sourceType:$sourceId';
    final existing = await db.query('accounting_entries', columns: ['id'], where: 'id=?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty) return;
    final now = DateTime.now().toIso8601String();
    await db.insert('accounting_entries', {'id': id, 'journal_code': journalCode, 'entry_date': date,
      'reference': reference, 'description': description, 'source_type': sourceType, 'source_id': sourceId,
      'status': 'posted', 'created_at': now});
    await db.insert('accounting_entry_lines', {'id': _uuid.v4(), 'entry_id': id, 'account_code': debitAccount,
      'label': description, 'debit': amount, 'credit': 0, 'line_order': 1});
    await db.insert('accounting_entry_lines', {'id': _uuid.v4(), 'entry_id': id, 'account_code': creditAccount,
      'label': description, 'debit': 0, 'credit': amount, 'line_order': 2});
  }

  String _treasuryAccount(String? type) => switch (type) {'bank' => '521000', 'mobile' => '531000', _ => '571000'};
  String _journal(String? type) => switch (type) {'bank' => 'BQ', 'mobile' => 'MM', _ => 'CA'};
  String _expenseAccount(String category) { final value = category.toLowerCase(); if (value.contains('salaire')) return '661000'; if (value.contains('fourniture')) return '601000'; if (value.contains('électricité') || value.contains('eau') || value.contains('energie')) return '605000'; if (value.contains('entretien') || value.contains('maintenance')) return '624000'; if (value.contains('transport')) return '625000'; return '658000'; }

  Future<List<Map<String, Object?>>> accounts() => _database.db.query('accounting_accounts', where: 'active=1', orderBy: 'code');
  Future<List<Map<String, Object?>>> expenseAccounts() => _database.db.query('accounting_accounts', where: "active=1 AND account_type='expense'", orderBy: 'code');
  Future<List<Map<String, Object?>>> cashAccounts() => _database.db.query('cash_accounts', where: "active=1", orderBy: 'name');

  Future<List<Map<String, Object?>>> journal({required DateTime start, required DateTime end}) async {
    await synchronize();
    return _database.db.rawQuery('''SELECT e.id,e.entry_date,e.journal_code,e.reference,e.description,e.source_type,l.account_code,a.name account_name,l.debit,l.credit FROM accounting_entries e JOIN accounting_entry_lines l ON l.entry_id=e.id JOIN accounting_accounts a ON a.code=l.account_code WHERE e.status='posted' AND e.entry_date>=? AND e.entry_date<? ORDER BY e.entry_date,e.id,l.line_order''', [start.toIso8601String(), end.toIso8601String()]);
  }

  Future<List<Map<String, Object?>>> trialBalance({required DateTime start, required DateTime end}) async {
    await synchronize();
    return _database.db.rawQuery('''SELECT a.code,a.name,COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit ELSE 0 END),0) debit,COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.credit ELSE 0 END),0) credit,COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit-l.credit ELSE 0 END),0) balance FROM accounting_accounts a LEFT JOIN accounting_entry_lines l ON l.account_code=a.code LEFT JOIN accounting_entries e ON e.id=l.entry_id AND e.status='posted' AND e.entry_date>=? AND e.entry_date<? WHERE a.active=1 GROUP BY a.code,a.name HAVING debit<>0 OR credit<>0 ORDER BY a.code''', [start.toIso8601String(), end.toIso8601String()]);
  }

  Future<List<Map<String, Object?>>> generalLedger({required DateTime start, required DateTime end}) async {
    final rows = await journal(start: start, end: end);
    rows.sort((a, b) { final account = '${a['account_code']}'.compareTo('${b['account_code']}'); return account != 0 ? account : '${a['entry_date']}'.compareTo('${b['entry_date']}'); });
    final balances = <String, int>{};
    return rows.map((row) { final code = '${row['account_code']}'; final next = (balances[code] ?? 0) + ((row['debit'] as num).toInt()) - ((row['credit'] as num).toInt()); balances[code] = next; return {...row, 'balance': next}; }).toList();
  }

  Future<void> createManualEntry({
    required DateTime date, required String journalCode, required String reference,
      required String description, required List<Map<String, Object?>> lines}) async {
        BusinessWriteGuard.ensureAllowed('createManualEntry');
        
    if (description.trim().isEmpty || reference.trim().isEmpty) throw ArgumentError('Référence et description obligatoires.');
    if (lines.length < 2) throw ArgumentError('Une écriture doit comporter au moins deux lignes.');
    final debit = lines.fold<int>(0, (s, l) => s + ((l['debit'] as num?)?.toInt() ?? 0));
    final credit = lines.fold<int>(0, (s, l) => s + ((l['credit'] as num?)?.toInt() ?? 0));
    if (debit <= 0 || debit != credit) throw StateError('Écriture non équilibrée : total débit = $debit, crédit = $credit.');
    for (final line in lines) {
      final d = (line['debit'] as num?)?.toInt() ?? 0, c = (line['credit'] as num?)?.toInt() ?? 0;
      if ((d > 0) == (c > 0)) throw StateError('Chaque ligne doit être exclusivement au débit ou au crédit.');
    }
    final id = _uuid.v4(), now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('accounting_entries', {'id': id, 'journal_code': journalCode, 'entry_date': date.toIso8601String(),
        'reference': reference.trim(), 'description': description.trim(), 'source_type': 'manual', 'source_id': id,
        'status': 'posted', 'created_at': now});
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        await txn.insert('accounting_entry_lines', {'id': _uuid.v4(), 'entry_id': id, 'account_code': line['account_code'],
          'label': '${line['label'] ?? description}', 'debit': (line['debit'] as num?)?.toInt() ?? 0,
          'credit': (line['credit'] as num?)?.toInt() ?? 0, 'line_order': i + 1});
      }
      await txn.insert('audit_log', {'entity_type': 'accounting_entry', 'entity_id': id, 'action': 'manual_post',
        'new_value': '$journalCode/$reference/$debit', 'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId, 'operator_role': OperatorSession.role, 'created_at': now});
    });
  }

  Future<List<Map<String, Object?>>> supplierInvoices() => _database.db.rawQuery('''SELECT si.*,a.name expense_account_name FROM supplier_invoices si JOIN accounting_accounts a ON a.code=si.expense_account_code ORDER BY CASE si.status WHEN 'open' THEN 0 WHEN 'partial' THEN 1 ELSE 2 END,si.due_date,si.invoice_date DESC''');

  Future<void> addSupplierInvoice({
    required String invoiceNumber, required String supplierName, required DateTime invoiceDate,
      DateTime? dueDate, required String description, required String expenseAccountCode, required int amount}) async {
        BusinessWriteGuard.ensureAllowed('addSupplierInvoice');
        
    if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
    final now = DateTime.now().toIso8601String();
    await _database.db.insert('supplier_invoices', {'id': _uuid.v4(), 'invoice_number': invoiceNumber.trim(),
      'supplier_name': supplierName.trim(), 'invoice_date': invoiceDate.toIso8601String(), 'due_date': dueDate?.toIso8601String(),
      'description': description.trim(), 'expense_account_code': expenseAccountCode, 'amount': amount, 'amount_paid': 0,
      'status': 'open', 'created_at': now, 'updated_at': now});
    await synchronize();
  }

  Future<void> paySupplierInvoice({
    required String invoiceId, required String cashAccountId, required int amount,
      required DateTime paidAt, String? reference, String? note}) async {
        BusinessWriteGuard.ensureAllowed('paySupplierInvoice');
        
    if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
    await _database.db.transaction((txn) async {
      await ensureCashMovementAllowed(txn, cashAccountId);
      final available = await availableTreasuryBalance(txn, cashAccountId);
      if (available < amount) {
        throw StateError('Solde insuffisant sur le compte sélectionné. Disponible : $available FCFA.');
      }
      final rows = await txn.query('supplier_invoices', where: 'id=?', whereArgs: [invoiceId], limit: 1);
      if (rows.isEmpty) throw StateError('Facture fournisseur introuvable.');
      final total = (rows.first['amount'] as num).toInt(), paid = (rows.first['amount_paid'] as num).toInt();
      if (paid + amount > total) throw StateError('Le règlement dépasse le solde fournisseur.');
      final id = _uuid.v4(), now = DateTime.now().toIso8601String(), newPaid = paid + amount;
      await txn.insert('supplier_payments', {'id': id, 'supplier_invoice_id': invoiceId, 'cash_account_id': cashAccountId,
        'amount': amount, 'paid_at': paidAt.toIso8601String(), 'reference': reference?.trim(), 'note': note?.trim(), 'created_at': now});
      await txn.update('supplier_invoices', {'amount_paid': newPaid, 'status': newPaid == total ? 'paid' : 'partial', 'updated_at': now}, where: 'id=?', whereArgs: [invoiceId]);
    });
    await synchronize();
  }

  Future<Map<String, String>> settings() async {
    final rows = await _database.db.query('accounting_settings', orderBy: 'key');
    return {for (final r in rows) '${r['key']}': '${r['value']}'};
  }

  Future<void> updateSetting(String key, String value) async {
    BusinessWriteGuard.ensureAllowed('updateSetting');
    final exists = await _database.db.query('accounting_accounts', columns: ['code'], where: 'code=? AND active=1', whereArgs: [value], limit: 1);
    if (exists.isEmpty) throw StateError('Le compte $value n’existe pas ou est désactivé.');
    await _database.db.insert('accounting_settings', {'key': key, 'value': value, 'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> reconciliations() => _database.db.rawQuery('''SELECT br.*,ca.name account_name FROM bank_reconciliations br JOIN cash_accounts ca ON ca.id=br.cash_account_id ORDER BY br.period_end DESC''');

  Future<String> createReconciliation({
    required String cashAccountId, required DateTime start, required DateTime end,
      required int statementBalance, String? note}) async {
        BusinessWriteGuard.ensureAllowed('createReconciliation');
        
    await synchronize();
    final accounts = await _database.db.query('cash_accounts', where: 'id=?', whereArgs: [cashAccountId], limit: 1);
    if (accounts.isEmpty) throw StateError('Compte de trésorerie introuvable.');
    final accountCode = _treasuryAccount(accounts.first['type'] as String?);
    final balanceRows = await _database.db.rawQuery('''SELECT COALESCE(SUM(l.debit-l.credit),0) balance FROM accounting_entry_lines l JOIN accounting_entries e ON e.id=l.entry_id WHERE e.status='posted' AND l.account_code=? AND e.entry_date<=?''', [accountCode, end.toIso8601String()]);
    final bookBalance = (balanceRows.first['balance'] as num?)?.toInt() ?? 0;
    final id = _uuid.v4(), now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('bank_reconciliations', {'id': id, 'cash_account_id': cashAccountId, 'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(), 'statement_balance': statementBalance, 'book_balance': bookBalance,
        'difference': statementBalance - bookBalance, 'note': note?.trim(), 'status': 'draft', 'created_at': now});
      final entries = await txn.rawQuery('''SELECT DISTINCT e.id FROM accounting_entries e JOIN accounting_entry_lines l ON l.entry_id=e.id WHERE e.status='posted' AND l.account_code=? AND e.entry_date>=? AND e.entry_date<=?''', [accountCode, start.toIso8601String(), end.toIso8601String()]);
      for (final e in entries) {
        await txn.insert('bank_reconciliation_items', {'id': _uuid.v4(), 'reconciliation_id': id, 'accounting_entry_id': e['id'], 'cleared': 0});
      }
    });
    return id;
  }

  Future<List<Map<String, Object?>>> reconciliationItems(String reconciliationId) => _database.db.rawQuery('''SELECT bri.*,e.entry_date,e.reference,e.description,COALESCE(SUM(l.debit),0) debit,COALESCE(SUM(l.credit),0) credit FROM bank_reconciliation_items bri JOIN accounting_entries e ON e.id=bri.accounting_entry_id JOIN accounting_entry_lines l ON l.entry_id=e.id WHERE bri.reconciliation_id=? GROUP BY bri.id,e.id ORDER BY e.entry_date,e.reference''', [reconciliationId]);

  Future<void> setReconciled(String itemId, bool cleared) async {
    BusinessWriteGuard.ensureAllowed('Modifier un rapprochement bancaire');
    await _database.db.update('bank_reconciliation_items', {'cleared': cleared ? 1 : 0}, where: 'id=?', whereArgs: [itemId]);
  }

  Future<void> completeReconciliation(String reconciliationId) async {
    BusinessWriteGuard.ensureAllowed('completeReconciliation');
    final pending = await _database.db.rawQuery('SELECT COUNT(*) n FROM bank_reconciliation_items WHERE reconciliation_id=? AND cleared=0', [reconciliationId]);
    if (((pending.first['n'] as num?)?.toInt() ?? 0) > 0) throw StateError('Toutes les écritures doivent être pointées avant validation.');
    await _database.db.update('bank_reconciliations', {'status': 'completed', 'completed_at': DateTime.now().toIso8601String()}, where: 'id=?', whereArgs: [reconciliationId]);
  }
}
