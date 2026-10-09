import 'package:sqflite_common/utils/utils.dart';

import '../../core/db/app_database.dart';
import '../models/dashboard_summary.dart';

class DashboardRepository {
  DashboardRepository(this._database);
  final AppDatabase _database;

  Future<DashboardSummary> load() async {
    final db = _database.db;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final todayIso = DateTime(now.year, now.month, now.day).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final nextMonth = DateTime(now.year, now.month + 1, 1).toIso8601String();

    Future<int> scalar(String sql, [List<Object?>? args]) async =>
        firstIntValue(await db.rawQuery(sql, args)) ?? 0;

    final activeYear = await db.query(
      'school_years',
      columns: ['id', 'start_date', 'end_date'],
      where: 'is_active = 1',
      limit: 1,
    );
    final yearId = activeYear.isEmpty ? null : activeYear.first['id'] as String;

    final studentCount = yearId == null
        ? await scalar("SELECT COUNT(*) FROM students WHERE status='active'")
        : await scalar(
            '''SELECT COUNT(DISTINCT s.id)
               FROM students s
               JOIN student_enrollments se
                 ON se.student_id=s.id AND se.school_year_id=?
               WHERE se.status='active' ''',
            [yearId],
          );

    final dueYearClause = yearId == null ? '' : ' AND school_year_id = ?';
    final dueArgs = yearId == null ? <Object?>[nowIso] : <Object?>[nowIso, yearId];
    final expectedDue = await scalar(
      'SELECT COALESCE(SUM(amount_due),0) FROM dues '
      'WHERE COALESCE(due_date,created_at) <= ?$dueYearClause',
      dueArgs,
    );
    final collectedDue = await scalar(
      'SELECT COALESCE(SUM(amount_paid),0) FROM dues '
      'WHERE COALESCE(due_date,created_at) <= ?$dueYearClause',
      dueArgs,
    );
    final overdueBalance = await scalar(
      "SELECT COALESCE(SUM(amount_due-amount_paid),0) FROM dues "
      "WHERE status!='paid' AND due_date IS NOT NULL AND due_date < ?$dueYearClause",
      yearId == null ? <Object?>[todayIso] : <Object?>[todayIso, yearId],
    );

    final futureArgs = yearId == null ? <Object?>[nowIso] : <Object?>[nowIso, yearId];
    final futureBalance = await scalar(
      "SELECT COALESCE(SUM(amount_due-amount_paid),0) FROM dues "
      "WHERE status!='paid' AND due_date IS NOT NULL AND due_date >= ?$dueYearClause",
      futureArgs,
    );

    final paymentYearClause = yearId == null ? '' : ' AND school_year_id = ?';
    final monthPaymentArgs = yearId == null
        ? <Object?>[monthStart, nextMonth]
        : <Object?>[monthStart, nextMonth, yearId];
    final monthRevenue =
        await scalar(
          "SELECT COALESCE(SUM(amount),0) FROM payments "
          "WHERE status='posted' AND paid_at>=? AND paid_at<?$paymentYearClause",
          monthPaymentArgs,
        ) -
        await scalar(
          '''SELECT COALESCE(SUM(r.amount),0)
             FROM payment_refunds r
             JOIN payments p ON p.id=r.payment_id
             WHERE r.refunded_at>=? AND r.refunded_at<?
             ${yearId == null ? '' : 'AND p.school_year_id = ?'}''',
          monthPaymentArgs,
        ) +
        await scalar(
          "SELECT COALESCE(SUM(sale_amount),0) FROM asset_disposals WHERE disposal_type='sale' AND sale_amount>0 AND cash_account_id IS NOT NULL AND disposal_date>=? AND disposal_date<?",
          [monthStart, nextMonth],
        );

    return DashboardSummary(
      studentCount: studentCount,
      expectedDue: expectedDue,
      collectedDue: collectedDue,
      overdueBalance: overdueBalance,
      futureBalance: futureBalance,
      monthRevenue: monthRevenue,
      monthExpenses: await scalar(
        "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE status='posted' AND approval_status='approved' AND spent_at>=? AND spent_at<?",
        [monthStart, nextMonth],
      ) + await scalar(
        'SELECT COALESCE(SUM(amount),0) FROM supplier_payments WHERE paid_at>=? AND paid_at<?',
        [monthStart, nextMonth],
      ),
      unreadAlerts: await scalar(
        "SELECT COUNT(*) FROM alerts WHERE is_read=0 AND status!='archived'",
      ),
    );
  }
}
