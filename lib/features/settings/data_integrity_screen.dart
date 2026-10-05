import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/repositories/data_integrity_repository.dart';

class DataIntegrityScreen extends ConsumerWidget {
  const DataIntegrityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(dataIntegrityReportProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic des données'),
        actions: [
          IconButton(
            tooltip: 'Relancer les contrôles',
            onPressed: () => ref.invalidate(dataIntegrityReportProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(dataIntegrityReportProvider),
        ),
        data: (value) => _ReportView(report: value),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});
  final DataIntegrityReport report;

  @override
  Widget build(BuildContext context) {
    final healthy = report.healthy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  healthy ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  size: 34,
                  color: healthy
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy
                            ? 'Aucune incohérence détectée'
                            : '${report.failureCount} contrôle(s) en échec',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Ces contrôles sont en lecture seule. Une anomalie comptable n’est jamais réparée automatiquement.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final check in report.checks)
          Card(
            child: ListTile(
              leading: Icon(
                check.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: check.passed
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(
                check.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(check.detail),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Contrôle exécuté le ${_formatDate(report.generatedAt)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
}
