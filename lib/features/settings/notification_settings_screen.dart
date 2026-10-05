import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../services/local_notification_service.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool? _enabled;
  int _high = 30;
  int _critical = 90;
  int _dueSoon = 3;
  int _capacity = 90;
  int _backup = 7;

  bool get _readOnly => OperatorSession.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await LocalNotificationService.instance.isEnabled();
    final values = await ref.read(settingsRepositoryProvider).notificationThresholds();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _high = values['alert.overdue.high_days'] ?? 30;
      _critical = values['alert.overdue.critical_days'] ?? 90;
      _dueSoon = values['alert.due_soon_days'] ?? 3;
      _capacity = values['alert.capacity_percent'] ?? 90;
      _backup = values['alert.backup_stale_days'] ?? 7;
    });
  }

  Future<void> _save() async {
    if (_readOnly) return;
    try {
      await ref.read(settingsRepositoryProvider).saveNotificationThresholds(
        overdueHighDays: _high,
        overdueCriticalDays: _critical,
        dueSoonDays: _dueSoon,
        capacityPercent: _capacity,
        backupStaleDays: _backup,
      );
      ref.invalidate(auditEntriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seuils enregistrés.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Widget _number(String label, int value, ValueChanged<int> onChanged, {int min = 1, int max = 365}) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: List.generate(max - min + 1, (i) => min + i)
          .where((v) => max <= 30 || v % 5 == 0 || v == value || v == min || v == max)
          .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
          .toList(),
      onChanged: _readOnly ? null : (v) {
        if (v != null) setState(() => onChanged(v));
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications hors ligne')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_readOnly)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Mode lecture seule'),
                  subtitle: Text('Un compte Administrateur peut consulter ces réglages, mais seul un Gestionnaire peut les modifier.'),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notifications locales', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Plateforme détectée : ${LocalNotificationService.instance.platformLabel}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (_enabled == null)
                      const LinearProgressIndicator()
                    else
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _enabled!,
                        title: const Text('Autoriser les alertes GesApp'),
                        subtitle: Text(LocalNotificationService.instance.isSupported
                            ? 'Aucun serveur ni Internet requis.'
                            : 'Notifications système non prises en charge sur cette plateforme.'),
                        onChanged: !_readOnly && LocalNotificationService.instance.isSupported
                            ? (value) async {
                                try {
                                  await LocalNotificationService.instance.setEnabled(value);
                                  if (value) await LocalNotificationService.instance.initialize();
                                  if (mounted) setState(() => _enabled = value);
                                } catch (error) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de modifier les notifications : $error')));
                                  }
                                }
                              }
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text('Seuils des alertes', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _number('Impayé priorité élevée après (jours)', _high, (v) => _high = v, max: 180),
                    const SizedBox(height: 10),
                    _number('Impayé critique après (jours)', _critical, (v) => _critical = v, max: 365),
                    const SizedBox(height: 10),
                    _number('Prévenir avant échéance (jours)', _dueSoon, (v) => _dueSoon = v, max: 30),
                    const SizedBox(height: 10),
                    _number('Alerte capacité classe (%)', _capacity, (v) => _capacity = v, min: 50, max: 100),
                    const SizedBox(height: 10),
                    _number('Sauvegarde considérée ancienne après (jours)', _backup, (v) => _backup = v, max: 30),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _readOnly ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Enregistrer les seuils'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Tester une notification'),
                subtitle: Text('Envoie immédiatement une notification ${LocalNotificationService.instance.platformLabel}.'),
                enabled: _enabled == true && LocalNotificationService.instance.isSupported,
                onTap: _enabled == true && LocalNotificationService.instance.isSupported
                    ? () async {
                        try {
                          await LocalNotificationService.instance.showTestNotification();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Notification de test envoyée à ${LocalNotificationService.instance.platformLabel}.')),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec de la notification : $error')));
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
      );
}
