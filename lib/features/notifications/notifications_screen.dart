import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../services/local_notification_service.dart';
import '../finance/recovery_screen.dart';
import '../hr/employee_detail_screen.dart';
import '../hr/hr_screen.dart';
import '../hr/payroll_screen.dart';
import '../expenses/recurring_expenses_screen.dart';
import '../settings/backup_screen.dart';
import '../settings/data_integrity_screen.dart';
import '../students/student_detail_screen.dart';
import '../students/students_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _icon(String? severity) => switch (severity) {
    'critical' => Icons.error_rounded,
    'high' => Icons.warning_amber_rounded,
    _ => Icons.notifications_active_outlined,
  };

  Color _tone(String? severity) => switch (severity) {
    'critical' => AppColors.danger,
    'high' => AppColors.warning,
    _ => AppColors.info,
  };

  Future<void> _openTarget(BuildContext context, WidgetRef ref, Map<String,Object?> item) async {
    final type=item['target_type'] as String?;final id=item['target_id'] as String?;
    if(type=='due'&&id!=null){
      final rows=await ref.read(studentRepositoryProvider).studentIdForDue(id);
      if(rows!=null&&context.mounted){final student=await ref.read(studentRepositoryProvider).detail(rows);if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>StudentDetailScreen(student:student)));}
      return;
    }
    if(type=='recovery_action'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const RecoveryScreen()));return;}
    if(type=='classroom'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const StudentsScreen()));return;}
    if(type=='recurring_expense'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const RecurringExpensesScreen()));return;}
    if(type=='system'&&id=='backup'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const BackupScreen()));return;}
    if(type=='system'&&id=='database'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const DataIntegrityScreen()));return;}
    if(type=='employee'&&id!=null){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>EmployeeDetailScreen(employeeId:id)));return;}
    if(type=='employment_contract'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const HrScreen()));return;}
    if(type=='hr'){if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const PayrollScreen()));return;}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Tout marquer comme lu',
            onPressed: () async {
              await ref.read(alertsRepositoryProvider).markAllRead();
              ref.invalidate(alertsProvider);
              ref.invalidate(dashboardProvider);
            },
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () async {
              await ref.read(alertsRepositoryProvider).refreshOperationalAlerts();
              await LocalNotificationService.instance.publishPendingAlerts();
              ref.invalidate(alertsProvider);
              ref.invalidate(dashboardProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: alerts.when(
        data: (items) => items.isEmpty
            ? const _EmptyNotifications()
            : RefreshIndicator(
                onRefresh: () async {
                  await ref.read(alertsRepositoryProvider).refreshOperationalAlerts();
                  await LocalNotificationService.instance.publishPendingAlerts();
                  ref.invalidate(alertsProvider);
                  ref.invalidate(dashboardProvider);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final read = (item['is_read'] as int) == 1;
                    final severity = item['severity'] as String?;
                    final tone = _tone(severity);
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          await ref.read(alertsRepositoryProvider).markRead(item['id'] as String);
                          ref.invalidate(alertsProvider);
                          ref.invalidate(dashboardProvider);
                          if (context.mounted) await _openTarget(context, ref, item);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
                              child: Icon(read ? Icons.notifications_none_rounded : _icon(severity), color: tone, size: 22),
                            ),
                            const SizedBox(width: 13),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(item['title'] as String, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: read ? FontWeight.w600 : FontWeight.w800))),
                                if (!read) Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
                              ]),
                              const SizedBox(height: 5),
                              Text(item['message'] as String, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ])),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (value) async {
                                if (value == 'archive') {
                                  await ref.read(alertsRepositoryProvider).archive(item['id'] as String);
                                  ref.invalidate(alertsProvider);
                                  ref.invalidate(dashboardProvider);
                                }
                              },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'archive', child: Text('Archiver'))],
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(22)), child: Icon(Icons.notifications_none_rounded, color: Theme.of(context).colorScheme.primary, size: 32)),
        const SizedBox(height: 16),
        Text('Tout est calme', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('Aucune notification ne demande votre attention.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    ),
  );
}
