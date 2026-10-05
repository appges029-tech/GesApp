import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';

/// Règles communes de mouvements de trésorerie.
///
/// Seuls les comptes de type `cash` exigent une session ouverte. Les comptes
/// bancaires et Mobile Money peuvent recevoir des mouvements sans ouverture de
/// caisse physique.
Future<void> ensureCashMovementAllowed(
  DatabaseExecutor db,
  String? cashAccountId,
) async {
  if (cashAccountId == null || cashAccountId.trim().isEmpty) return;
  final accounts = await db.query(
    'cash_accounts',
    columns: ['id', 'name', 'type', 'active'],
    where: 'id = ?',
    whereArgs: [cashAccountId],
    limit: 1,
  );
  if (accounts.isEmpty) {
    throw StateError('Caisse / compte introuvable.');
  }
  final account = accounts.first;
  if ((account['active'] as int? ?? 0) != 1) {
    throw StateError('Cette caisse / ce compte est désactivé.');
  }
  if (account['type'] != 'cash') return;

  final sessions = await db.query(
    'cash_sessions',
    columns: ['id'],
    where: "cash_account_id = ? AND status = 'open'",
    whereArgs: [cashAccountId],
    limit: 1,
  );
  if (sessions.isEmpty) {
    throw StateError(
      'La caisse physique « ${account['name']} » est fermée. Ouvrez-la avant d’enregistrer ce mouvement.',
    );
  }
}

/// Valide l'association moyen de paiement ↔ type de compte.
///
/// Depuis V15, cette règle ne dépend plus du texte « Espèces », « Mobile
/// Money », etc. Le gestionnaire peut créer ses propres moyens et leur associer
/// explicitement un type de compte : cash, mobile ou bank.
Future<void> ensurePaymentMethodMatchesAccount(
  DatabaseExecutor db,
  String paymentMethod,
  String? cashAccountId,
) async {
  if (cashAccountId == null || cashAccountId.trim().isEmpty) {
    throw StateError('Sélectionnez la caisse / le compte utilisé pour ce mouvement.');
  }

  final methodRows = await db.query(
    'payment_methods',
    columns: ['name', 'account_type', 'active'],
    where: 'lower(name) = lower(?)',
    whereArgs: [paymentMethod.trim()],
    limit: 1,
  );
  if (methodRows.isEmpty) {
    throw StateError('Le moyen de paiement « $paymentMethod » n’est pas configuré.');
  }
  final method = methodRows.first;
  if ((method['active'] as int? ?? 0) != 1) {
    throw StateError('Le moyen de paiement « ${method['name']} » est désactivé.');
  }

  final accountRows = await db.query(
    'cash_accounts',
    columns: ['name', 'type', 'active'],
    where: 'id = ?',
    whereArgs: [cashAccountId],
    limit: 1,
  );
  if (accountRows.isEmpty) throw StateError('Caisse / compte introuvable.');
  final account = accountRows.first;
  if ((account['active'] as int? ?? 0) != 1) {
    throw StateError('La caisse / le compte « ${account['name']} » est désactivé.');
  }

  final expected = (method['account_type'] as String? ?? 'cash').toLowerCase();
  final actual = (account['type'] as String? ?? '').toLowerCase();
  if (expected != actual) {
    throw StateError(
      'Le moyen de paiement « ${method['name']} » exige un compte de type $expected, '
      'mais « ${account['name']} » est de type $actual.',
    );
  }
}

Future<bool> paymentMethodRequiresReference(
  DatabaseExecutor db,
  String paymentMethod,
) async {
  final rows = await db.query(
    'payment_methods',
    columns: ['requires_reference'],
    where: 'lower(name) = lower(?) AND active = 1',
    whereArgs: [paymentMethod.trim()],
    limit: 1,
  );
  return rows.isNotEmpty && (rows.first['requires_reference'] as int? ?? 0) == 1;
}


/// Solde de trésorerie réellement disponible sur un compte.
///
/// Pour une caisse physique, le calcul part de la session ouverte. Pour un
/// compte bancaire/mobile, il part du solde d'ouverture. Toutes les sorties
/// connues, y compris les règlements fournisseurs, sont déduites.
Future<int> availableTreasuryBalance(
  DatabaseExecutor db,
  String accountId,
) async {
  final accountRows = await db.query(
    'cash_accounts',
    columns: ['type', 'opening_balance', 'active'],
    where: 'id = ?',
    whereArgs: [accountId],
    limit: 1,
  );
  if (accountRows.isEmpty) throw StateError('Compte source introuvable.');
  final account = accountRows.first;
  if ((account['active'] as int? ?? 0) != 1) {
    throw StateError('Cette caisse / ce compte est désactivé.');
  }

  final isCash = account['type'] == 'cash';
  String? from;
  int opening;
  if (isCash) {
    final sessions = await db.query(
      'cash_sessions',
      columns: ['opened_at', 'opening_amount'],
      where: "cash_account_id = ? AND status = 'open'",
      whereArgs: [accountId],
      limit: 1,
    );
    if (sessions.isEmpty) throw StateError('La caisse source est fermée.');
    from = sessions.first['opened_at'] as String;
    opening = sessions.first['opening_amount'] as int;
  } else {
    opening = account['opening_balance'] as int? ?? 0;
  }

  String dateFilter(String column) => from == null ? '' : ' AND $column >= ?';
  List<Object?> args() => from == null ? <Object?>[accountId] : <Object?>[accountId, from];

  final income = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) FROM payments WHERE status='posted' AND cash_account_id=?${dateFilter('paid_at')}",
        args(),
      )) ??
      0;
  final refunds = firstIntValue(await db.rawQuery(
        'SELECT COALESCE(SUM(r.amount),0) FROM payment_refunds r JOIN payments p ON p.id=r.payment_id '
        'WHERE COALESCE(r.cash_account_id,p.cash_account_id)=?${dateFilter('r.refunded_at')}',
        args(),
      )) ??
      0;
  final expenses = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE status='posted' AND approval_status='approved' AND cash_account_id=?${dateFilter('spent_at')}",
        args(),
      )) ??
      0;
  final salaryAdvances = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) FROM salary_advances WHERE cash_account_id=? AND status!='annule'${dateFilter('granted_at')}",
        args(),
      )) ??
      0;
  final supplierPayments = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) FROM supplier_payments WHERE cash_account_id=?${dateFilter('paid_at')}",
        args(),
      )) ??
      0;
  final assetSales = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(sale_amount),0) FROM asset_disposals WHERE disposal_type='sale' AND cash_account_id=?${dateFilter('disposal_date')}",
        args(),
      )) ??
      0;
  final incoming = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) FROM cash_transfers WHERE status='posted' AND to_account_id=?${dateFilter('transferred_at')}",
        args(),
      )) ??
      0;
  final outgoing = firstIntValue(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) FROM cash_transfers WHERE status='posted' AND from_account_id=?${dateFilter('transferred_at')}",
        args(),
      )) ??
      0;

  return opening + income + assetSales - refunds - expenses - salaryAdvances - supplierPayments + incoming - outgoing;
}
