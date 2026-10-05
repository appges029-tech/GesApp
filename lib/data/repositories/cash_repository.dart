import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import 'cash_rules.dart';

class CashRepository {
  CashRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<Map<String, Object?>>> accounts() =>
      _db.db.query('cash_accounts', where: 'active=1', orderBy: 'name');

  Future<Map<String, Object?>?> openSession(String accountId) async {
    final rows = await _db.db.query(
      'cash_sessions',
      where: "cash_account_id=? AND status='open'",
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> open({
    required String accountId, required int openingAmount}) async {
      BusinessWriteGuard.ensureAllowed('open');
      
    if (openingAmount < 0) throw ArgumentError('Fond initial invalide');
    if (await openSession(accountId) != null) {
      throw StateError('Cette caisse est déjà ouverte.');
    }
    final account = await _db.db.query(
      'cash_accounts',
      columns: ['type', 'active'],
      where: 'id=?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (account.isEmpty) throw StateError('Caisse / compte introuvable.');
    if (account.first['type'] != 'cash') {
      throw StateError('Seules les caisses physiques nécessitent une ouverture/clôture.');
    }
    final now = DateTime.now().toIso8601String();
    await _db.db.insert('cash_sessions', {
      'id': _uuid.v4(),
      'cash_account_id': accountId,
      'opened_by': OperatorSession.userId,
      'opened_at': now,
      'opening_amount': openingAmount,
      'status': 'open',
    });
  }

  Future<int> theoretical(String sessionId) async {
    final sessionRows = await _db.db.query(
      'cash_sessions',
      where: 'id=?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) throw StateError('Session de caisse introuvable.');
    final session = sessionRows.first;
    final from = session['opened_at'] as String;
    final account = session['cash_account_id'] as String;
    final opening = session['opening_amount'] as int;
    final income = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) FROM payments WHERE status='posted' AND cash_account_id=? AND paid_at>=?",
          [account, from],
        )) ??
        0;
    final refunds = firstIntValue(await _db.db.rawQuery(
          'SELECT COALESCE(SUM(r.amount),0) FROM payment_refunds r JOIN payments p ON p.id=r.payment_id WHERE COALESCE(r.cash_account_id,p.cash_account_id)=? AND r.refunded_at>=?',
          [account, from],
        )) ??
        0;
    final expenses = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE status='posted' AND approval_status='approved' AND cash_account_id=? AND spent_at>=?",
          [account, from],
        )) ??
        0;
    final salaryAdvances = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) FROM salary_advances WHERE cash_account_id=? AND granted_at>=? AND status!='annule'",
          [account, from],
        )) ??
        0;
    final supplierPayments = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) FROM supplier_payments WHERE cash_account_id=? AND paid_at>=?",
          [account, from],
        )) ??
        0;
    final assetSales = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(sale_amount),0) FROM asset_disposals WHERE disposal_type='sale' AND cash_account_id=? AND disposal_date>=?",
          [account, from],
        )) ??
        0;
    final incomingTransfers = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) FROM cash_transfers WHERE status='posted' AND to_account_id=? AND transferred_at>=?",
          [account, from],
        )) ??
        0;
    final outgoingTransfers = firstIntValue(await _db.db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) FROM cash_transfers WHERE status='posted' AND from_account_id=? AND transferred_at>=?",
          [account, from],
        )) ??
        0;
    return opening + income + assetSales - refunds - expenses - salaryAdvances - supplierPayments + incomingTransfers - outgoingTransfers;
  }

  Future<void> close({
    required String sessionId, required int physicalAmount}) async {
      BusinessWriteGuard.ensureAllowed('close');
      
    if (physicalAmount < 0) throw ArgumentError('Comptage physique invalide.');
    final theoreticalAmount = await theoretical(sessionId);
    final now = DateTime.now().toIso8601String();
    await _db.db.update(
      'cash_sessions',
      {
        'closed_by': OperatorSession.userId,
        'closed_at': now,
        'theoretical_amount': theoreticalAmount,
        'physical_amount': physicalAmount,
        'variance': physicalAmount - theoreticalAmount,
        'status': 'closed',
      },
      where: "id=? AND status='open'",
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, Object?>>> transfers({int limit = 100}) {
    return _db.db.rawQuery('''
      SELECT t.*, f.name from_name, d.name to_name
      FROM cash_transfers t
      JOIN cash_accounts f ON f.id=t.from_account_id
      JOIN cash_accounts d ON d.id=t.to_account_id
      WHERE t.status='posted'
      ORDER BY t.transferred_at DESC
      LIMIT ?
    ''', [limit]);
  }


  Future<int> _availableBalance(DatabaseExecutor db, String accountId) =>
      availableTreasuryBalance(db, accountId);

  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int amount,
    String? reference,
    String? note,
  }) async {
    BusinessWriteGuard.ensureAllowed('transfer');
    if (fromAccountId == toAccountId) {
      throw StateError('Le compte source et le compte destination doivent être différents.');
    }
    if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
    final now = DateTime.now().toIso8601String();
    await _db.db.transaction((txn) async {
      // Si une caisse physique participe au transfert, elle doit être ouverte.
      await ensureCashMovementAllowed(txn, fromAccountId);
      await ensureCashMovementAllowed(txn, toAccountId);
      final available = await _availableBalance(txn, fromAccountId);
      if (available < amount) {
        throw StateError('Solde insuffisant sur le compte source. Disponible : $available FCFA.');
      }
      await txn.insert('cash_transfers', {
        'id': _uuid.v4(),
        'from_account_id': fromAccountId,
        'to_account_id': toAccountId,
        'amount': amount,
        'transferred_at': now,
        'reference': reference?.trim().isEmpty == true ? null : reference?.trim(),
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'operator_id': OperatorSession.userId,
        'status': 'posted',
        'created_at': now,
      });
      await txn.insert('audit_log', {
        'entity_type': 'cash_transfer',
        'entity_id': '${fromAccountId}_$toAccountId',
        'action': 'transfer',
        'new_value': '$amount/$fromAccountId/$toAccountId',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }
}
