import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/hr.dart';
import 'attendance_screen.dart';
import 'employees_screen.dart';
import 'hr_configuration_screen.dart';
import 'hr_reports_screen.dart';
import 'leave_screen.dart';
import 'payroll_screen.dart';

class HrScreen extends ConsumerStatefulWidget {
  const HrScreen({super.key});

  @override
  ConsumerState<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends ConsumerState<HrScreen> {
  int _refresh = 0;

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return WindowsPageScaffold(
      title: 'Ressources humaines',
      subtitle: 'Personnel, présence, congés, contrats et paie',
      actions: [
        WindowsCommandButton(icon: Icons.refresh, label: 'Actualiser', onPressed: () => setState(() => _refresh++)),
        WindowsCommandButton(icon: Icons.settings_outlined, label: 'Configuration', onPressed: () => _open(const HrConfigurationScreen())),
      ],
      body: FutureBuilder<HrSummary>(
        key: ValueKey(_refresh),
        future: ref.read(hrRepositoryProvider).summary(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 42, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Impossible de charger les données RH.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() => _refresh++),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final summary = snapshot.data;
          if (summary == null) {
            return const Center(child: Text('Aucune donnée RH disponible.'));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _refresh++),
            child: ListView(
              padding: WindowsUi.isDesktop(context) ? EdgeInsets.zero : const EdgeInsets.all(16),
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth >= 1100 ? 4 : box.maxWidth >= 650 ? 2 : 1;
                    const gap = 10.0;
                    final width = (box.maxWidth - ((columns - 1) * gap)) / columns;
                    final cards = [
                      _Kpi('Personnel actif', '${summary.activeEmployees}', Icons.groups_2_outlined),
                      _Kpi('Absents aujourd’hui', '${summary.absentToday}', Icons.person_off_outlined),
                      _Kpi('En congé', '${summary.onLeaveToday}', Icons.beach_access_outlined),
                      _Kpi('Contrats ≤ 30 j', '${summary.expiringContracts}', Icons.event_busy_outlined),
                      _Kpi('Dossiers incomplets', '${summary.incompleteFiles}', Icons.folder_off_outlined),
                      _Kpi('Paies à traiter', '${summary.pendingPayroll}', Icons.pending_actions_outlined),
                      _Kpi('Paie du mois', formatXaf(summary.monthlyPayroll), Icons.payments_outlined),
                    ];
                    return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: width, child: card)]);
                  },
                ),
                const SizedBox(height: 22),
                Text('Modules', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                WindowsModuleGrid(children: [
                  WindowsModuleCard(icon: Icons.badge_outlined, title: 'Personnel', subtitle: 'Fiches, contrats, affectations, documents et avances.', onTap: () => _open(const EmployeesScreen())),
                  WindowsModuleCard(icon: Icons.how_to_reg_outlined, title: 'Présences', subtitle: 'Présent, absent, retard, permission, mission et maladie.', onTap: () => _open(const AttendanceScreen())),
                  WindowsModuleCard(icon: Icons.event_available_outlined, title: 'Congés & permissions', subtitle: 'Demandes, validation, refus et calendrier des absences.', onTap: () => _open(const LeaveScreen())),
                  WindowsModuleCard(icon: Icons.account_balance_wallet_outlined, title: 'Paie', subtitle: 'Calcul, retenues, avances, validation, paiement et bulletin PDF.', onTap: () => _open(const PayrollScreen())),
                  WindowsModuleCard(icon: Icons.analytics_outlined, title: 'Rapports RH', subtitle: 'Effectifs, masse salariale, présence, congés et contrats.', onTap: () => _open(const HrReportsScreen())),
                  WindowsModuleCard(icon: Icons.tune_outlined, title: 'Configuration RH', subtitle: 'Services, postes et éléments de salaire.', onTap: () => _open(const HrConfigurationScreen())),
                ]),
                const SizedBox(height: 28),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => WindowsPanel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}
