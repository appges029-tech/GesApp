import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../finance/payment_form_screen.dart';
import '../finance/cash_screen.dart';
import '../finance/dues_screen.dart';
import '../students/student_form_screen.dart';
import '../settings/security_settings_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../notifications/notifications_screen.dart';
import '../settings/establishment_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final establishment = ref.watch(establishmentProvider);
    final scheme = Theme.of(context).colorScheme;
    final desktop = WindowsUi.isDesktop(context);

    final actions = <Widget>[
      WindowsCommandButton(
        icon: Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        label: 'Changer de thème',
        onPressed: () {
          final controller = ThemeController.instance;
          final darkNow = Theme.of(context).brightness == Brightness.dark;
          controller.setMode(darkNow ? ThemeMode.light : ThemeMode.dark);
        },
      ),
      summary.when(
        data: (d) => Badge(
          isLabelVisible: d.unreadAlerts > 0,
          label: Text('${d.unreadAlerts}'),
          child: WindowsCommandButton(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
        ),
        loading: () => const WindowsCommandButton(icon: Icons.notifications_none_rounded, label: 'Notifications', onPressed: null),
        error: (_, __) => const WindowsCommandButton(icon: Icons.notifications_none_rounded, label: 'Notifications', onPressed: null),
      ),
    ];

    final body = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        ref.invalidate(establishmentProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: desktop ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          if (!desktop) ...[
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(establishment.valueOrNull?.name ?? 'GesApp', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  establishment.valueOrNull == null ? 'Configurez votre établissement' : 'Votre établissement, en un coup d’œil',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ])),
              ...actions,
            ]),
            const SizedBox(height: 22),
          ],
          if (establishment.hasValue && establishment.valueOrNull == null) ...[
            _SetupBanner(onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const EstablishmentScreen()));
              ref.invalidate(establishmentProvider);
              ref.invalidate(dashboardProvider);
            }),
            const SizedBox(height: 16),
          ],
          _quickActions(context, ref),
          const SizedBox(height: 18),
          summary.when(
            data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _HeroBalance(netBalance: d.netBalance, revenue: d.monthRevenue, expenses: d.monthExpenses),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth >= 1100 ? 4 : box.maxWidth >= 700 ? 2 : 2;
                final width = (box.maxWidth - ((columns - 1) * 12)) / columns;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  _KpiCard(width: width, label: 'Élèves actifs', value: '${d.studentCount}', icon: Icons.groups_2_rounded, tone: AppColors.info),
                  _KpiCard(width: width, label: 'Recouvrement échu', value: '${(d.recoveryRate * 100).round()} %', icon: Icons.donut_large_rounded, tone: AppColors.success),
                  _KpiCard(width: width, label: 'Impayés échus', value: formatXaf(d.overdueBalance), icon: Icons.warning_amber_rounded, tone: AppColors.danger),
                  _KpiCard(width: width, label: 'À venir', value: formatXaf(d.futureBalance), icon: Icons.schedule_rounded, tone: AppColors.warning),
                ]);
              }),
              const SizedBox(height: 14),
              WindowsPanel(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Suivi des paiements en retard', style: Theme.of(context).textTheme.titleMedium)),
                    Text('${(d.recoveryRate * 100).round()} %', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.primary)),
                  ]),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: d.recoveryRate.clamp(0, 1), minHeight: desktop ? 7 : 10, backgroundColor: scheme.surfaceContainerHighest),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${formatXaf(d.collectedDue)} encaissés sur ${formatXaf(d.expectedDue)} arrivés à échéance.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => WindowsPanel(child: Text('Impossible de charger le tableau de bord : $e')),
          ),
          if (desktop) const SizedBox(height: 28),
        ],
      ),
    );

    if (!desktop) return SafeArea(child: body);
    return WindowsPageScaffold(
      title: establishment.valueOrNull?.name ?? 'GesApp',
      subtitle: establishment.valueOrNull == null ? 'Configurez votre établissement' : 'Vue d’ensemble de l’établissement',
      actions: actions,
      body: body,
    );
  }
  Widget _quickActions(BuildContext context, WidgetRef ref) {
    final manager = OperatorSession.isManager;
    final shortcuts = manager
        ? <({IconData icon, String title, String description, Widget destination})>[
            (icon: Icons.payments_rounded, title: 'Encaisser', description: 'Recevoir un paiement', destination: const PaymentFormScreen()),
            (icon: Icons.person_add_alt_1_rounded, title: 'Inscrire', description: 'Ajouter un élève', destination: const StudentFormScreen()),
            (icon: Icons.account_balance_wallet_rounded, title: 'Ma caisse', description: 'Ouvrir ou clôturer', destination: const CashScreen()),
            (icon: Icons.warning_amber_rounded, title: 'Impayés', description: 'Voir les sommes dues', destination: const DuesScreen()),
          ]
        : <({IconData icon, String title, String description, Widget destination})>[
            (icon: Icons.groups_rounded, title: 'Consulter les impayés', description: 'Suivi des paiements', destination: const DuesScreen()),
            (icon: Icons.admin_panel_settings_rounded, title: 'Comptes gestionnaires', description: 'Gérer les accès', destination: const SecuritySettingsScreen()),
          ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(manager ? 'Que souhaitez-vous faire ?' : 'Accès administrateur',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 1050 ? 4 : 2;
        final width = (box.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: shortcuts.map((item) => SizedBox(
            width: width,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  if (manager && !OperatorSession.hasPermission('finance.write')) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => item.destination));
                  if (context.mounted) {
                    ref.invalidate(dashboardProvider);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(item.icon, size: 27, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
            ),
          )).toList(),
        );
      }),
    ]);
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => WindowsPanel(
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.rocket_launch_rounded, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Terminer la configuration', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 3), Text('Renseignez l’établissement et l’année scolaire.')])),
          const Icon(Icons.arrow_forward_rounded),
        ]),
      );
}

class _HeroBalance extends StatelessWidget {
  const _HeroBalance({required this.netBalance, required this.revenue, required this.expenses});
  final int netBalance;
  final int revenue;
  final int expenses;

  @override
  Widget build(BuildContext context) {
    final positive = netBalance >= 0;
    final desktop = WindowsUi.isDesktop(context);
    return Container(
      padding: EdgeInsets.all(desktop ? 18 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF243EC4), AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(desktop ? 10 : 24),
        boxShadow: desktop ? null : [BoxShadow(color: AppColors.primary.withValues(alpha: .18), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Solde net du mois', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(formatXaf(netBalance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _MiniAmount(icon: Icons.south_west_rounded, label: 'Recettes', value: revenue)),
          const SizedBox(width: 12),
          Expanded(child: _MiniAmount(icon: Icons.north_east_rounded, label: 'Dépenses', value: expenses)),
          const SizedBox(width: 8),
          Icon(positive ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: Colors.white),
        ]),
      ]),
    );
  }
}

class _MiniAmount extends StatelessWidget {
  const _MiniAmount({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: Colors.white, size: 18)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)), Text(formatXaf(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))])),
      ]);
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.width, required this.label, required this.value, required this.icon, required this.tone});
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: WindowsPanel(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: tone, size: 21)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ],
          ),
        ),
      );
}
