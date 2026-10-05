import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../../data/models/dashboard_summary.dart';
import '../../data/models/expense.dart';
import '../../data/models/family.dart';
import '../../data/models/finance.dart';
import '../../data/models/finance_full.dart';
import '../../data/models/student.dart';
import '../../data/models/hr.dart';
import '../../data/models/asset.dart';
import '../../data/repositories/alerts_repository.dart';
import '../../data/repositories/accounting_repository.dart';
import '../../data/repositories/cash_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/data_integrity_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/family_repository.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/recovery_repository.dart';
import '../../data/repositories/security_repository.dart';
import '../../data/repositories/tenant_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/hr_repository.dart';
import '../../data/repositories/asset_repository.dart';
import '../../services/local_notification_service.dart';

final cashRepositoryProvider = Provider((ref)=>CashRepository(AppDatabase.instance));

final studentRepositoryProvider =
    Provider((ref) => StudentRepository(AppDatabase.instance));
final expenseRepositoryProvider =
    Provider((ref) => ExpenseRepository(AppDatabase.instance));
final financeRepositoryProvider =
    Provider((ref) => FinanceRepository(AppDatabase.instance));
final dashboardRepositoryProvider =
    Provider((ref) => DashboardRepository(AppDatabase.instance));
final dataIntegrityRepositoryProvider =
    Provider((ref) => DataIntegrityRepository(AppDatabase.instance));
final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(AppDatabase.instance));
final familyRepositoryProvider =
    Provider((ref) => FamilyRepository(AppDatabase.instance));
final securityRepositoryProvider =
    Provider((ref) => SecurityRepository(AppDatabase.instance));
final tenantRepositoryProvider =
    Provider((ref) => TenantRepository(AppDatabase.instance));
final auditRepositoryProvider =
    Provider((ref) => AuditRepository(AppDatabase.instance));
final reportRepositoryProvider =
    Provider((ref) => ReportRepository(AppDatabase.instance));
final recoveryRepositoryProvider =
    Provider((ref) => RecoveryRepository(AppDatabase.instance));
final alertsRepositoryProvider =
    Provider((ref) => AlertsRepository(AppDatabase.instance));
final accountingRepositoryProvider =
    Provider((ref) => AccountingRepository(AppDatabase.instance));
final hrRepositoryProvider = Provider((ref) => HrRepository(AppDatabase.instance));
final assetRepositoryProvider = Provider((ref) => AssetRepository(AppDatabase.instance));

final studentsProvider = FutureProvider<List<Student>>(
  (ref) => ref.watch(studentRepositoryProvider).list(),
);
final classroomsProvider = FutureProvider<List<ClassroomOption>>(
  (ref) => ref.watch(studentRepositoryProvider).classrooms(),
);

final allClassroomsProvider = FutureProvider<List<ClassroomOption>>(
  (ref) => ref.watch(studentRepositoryProvider).classrooms(includeInactive: true),
);
final expensesProvider = FutureProvider<List<ExpenseItem>>(
  (ref) => ref.watch(expenseRepositoryProvider).list(),
);
final expenseCategoriesProvider = FutureProvider<List<ExpenseCategory>>(
  (ref) => ref.watch(expenseRepositoryProvider).categories(),
);
final dashboardProvider = FutureProvider<DashboardSummary>((ref) async {
  await ref.watch(alertsRepositoryProvider).refreshOperationalAlerts();
  await LocalNotificationService.instance.publishPendingAlerts();
  return ref.watch(dashboardRepositoryProvider).load();
});
final establishmentProvider = FutureProvider<EstablishmentData?>(
  (ref) => ref.watch(settingsRepositoryProvider).establishment(),
);
final cyclesProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(settingsRepositoryProvider).cycles(),
);

final schoolYearsProvider = FutureProvider<List<SchoolYearItem>>(
  (ref) => ref.watch(settingsRepositoryProvider).schoolYears(),
);

final feeCategoriesProvider = FutureProvider<List<FeeCategoryItem>>(
  (ref) => ref.watch(financeRepositoryProvider).feeCategories(),
);
final recentPaymentsProvider = FutureProvider<List<PaymentItem>>(
  (ref) => ref.watch(financeRepositoryProvider).recentPayments(),
);
final cancelledPaymentsProvider = FutureProvider<List<PaymentItem>>(
  (ref) => ref.watch(financeRepositoryProvider).cancelledPayments(),
);
final feeGridProvider = FutureProvider<List<FeeGridItem>>(
  (ref) => ref.watch(financeRepositoryProvider).feeGrid(),
);
final unpaidDuesProvider = FutureProvider<List<DueItem>>(
  (ref) => ref.watch(financeRepositoryProvider).dues(unpaidOnly: true),
);
final packagesProvider = FutureProvider<List<PackageItem>>(
  (ref) => ref.watch(financeRepositoryProvider).packages(),
);
final alertsProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(alertsRepositoryProvider).list(),
);

final familiesProvider = FutureProvider<List<FamilyItem>>(
  (ref) => ref.watch(familyRepositoryProvider).list(),
);
final familyMembersProvider = FutureProvider.family<List<FamilyMember>, String>(
  (ref, familyId) => ref.watch(familyRepositoryProvider).members(familyId),
);
final familyBalanceProvider = FutureProvider.family<FamilyBalance, String>(
  (ref, familyId) => ref.watch(familyRepositoryProvider).balance(familyId),
);
final auditEntriesProvider = FutureProvider<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).recent(),
);

final dataIntegrityReportProvider = FutureProvider<DataIntegrityReport>(
  (ref) => ref.watch(dataIntegrityRepositoryProvider).run(),
);

final hrSummaryProvider = FutureProvider<HrSummary>((ref) => ref.watch(hrRepositoryProvider).summary());

final assetSummaryProvider = FutureProvider<AssetSummary>((ref) => ref.watch(assetRepositoryProvider).summary());
