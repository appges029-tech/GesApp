import 'package:flutter/material.dart';

import '../../core/session/operator_session.dart';
import '../../services/cloud_snapshot_service.dart';
import '../../services/tenant_cloud_service.dart';

class CloudSyncScreen extends StatelessWidget {
  const CloudSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CloudSnapshotService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Compte & synchronisation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Établissement', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(OperatorSession.organizationName ?? '—'),
                Text('Code : ${OperatorSession.organizationCode ?? '—'}'),
                Text('Compte : ${OperatorSession.current}'),
                Text('Rôle : ${OperatorSession.isAdmin ? 'Administrateur — lecture seule' : 'Gestionnaire'}'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<CloudSyncStatus>(
            valueListenable: service.status,
            builder: (context, value, _) {
              final unsupported = value.state == 'unsupported';
              return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_icon(value.state), color: _color(context, value.state)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_label(value.state), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  ]),
                  if (value.message != null) ...[const SizedBox(height: 8), Text(value.message!)],
                  if (value.lastSyncedAt != null) ...[const SizedBox(height: 8), Text('Dernière synchronisation : ${value.lastSyncedAt!.toLocal()}')],
                  const SizedBox(height: 14),
                  if (value.state == 'conflict') ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await _confirmConflictAction(
                            context,
                            title: 'Utiliser la version cloud ?',
                            message: 'GesApp archivera d’abord la version locale chiffrée dans le bucket privé, puis restaurera la dernière version cloud. Aucune des deux versions ne sera supprimée.',
                          );
                          if (confirmed) await service.resolveConflictUsingCloud();
                        },
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Utiliser la version cloud'),
                      ),
                    ),
                    if (OperatorSession.isManager) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final confirmed = await _confirmConflictAction(
                              context,
                              title: 'Conserver les données de cet appareil ?',
                              message: 'GesApp vérifiera encore le cloud, puis publiera les données locales comme une nouvelle révision. L’ancienne version cloud restera conservée pour récupération.',
                            );
                            if (confirmed) await service.resolveConflictKeepingLocal();
                          },
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Conserver cet appareil'),
                        ),
                      ),
                    ],
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: unsupported || value.state == 'syncing' || value.state == 'restoring'
                            ? null
                            : () => service.synchronize(force: OperatorSession.isManager),
                        icon: const Icon(Icons.sync_rounded),
                        label: Text(OperatorSession.isAdmin ? 'Rechercher une mise à jour' : 'Synchroniser maintenant'),
                      ),
                    ),
                ]),
              ),
            );
            },
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<CloudSyncStatus>(
            valueListenable: service.status,
            builder: (context, value, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    value.state == 'unsupported' ? 'Disponibilité' : 'Règles automatiques',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value.state == 'unsupported'
                        ? 'La synchronisation de snapshot n’est pas disponible sur Web pour le moment. Les données Web restent locales à ce navigateur ; utilisez les sauvegardes JSON pour les exporter ou les restaurer.'
                        : '• vérification toutes les 10 minutes lorsque GesApp est ouvert ;\n• aucun envoi si aucune donnée n’a changé ;\n• un administrateur télécharge les mises à jour mais ne publie jamais de données ;\n• un conflit entre deux appareils bloque l’écrasement automatique et propose un choix explicite ;\n• le snapshot est chiffré avant son envoi au bucket privé Supabase.',
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await TenantCloudService.instance.signOut();
              // La déconnexion Supabase déclenche la reconstruction de
              // TenantAccessGate. Une navigation manuelle simultanée peut
              // désactiver deux fois les mêmes InheritedElements.
            },
            icon: const Icon(Icons.logout),
            label: const Text('Déconnecter ce compte'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _confirmConflictAction(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continuer'),
              ),
            ],
          ),
        )) ??
        false;
  }

  static IconData _icon(String state) => switch (state) {
        'up_to_date' => Icons.cloud_done_outlined,
        'syncing' || 'restoring' => Icons.cloud_sync_outlined,
        'pending' => Icons.cloud_upload_outlined,
        'conflict' => Icons.warning_amber_rounded,
        'error' => Icons.cloud_off_outlined,
        _ => Icons.cloud_outlined,
      };

  static String _label(String state) => switch (state) {
        'up_to_date' => 'Cloud à jour',
        'syncing' => 'Synchronisation…',
        'restoring' => 'Restauration depuis Supabase…',
        'pending' => 'Modifications en attente d’envoi',
        'conflict' => 'Conflit de synchronisation',
        'error' => 'Synchronisation interrompue',
        'unsupported' => 'Snapshot cloud indisponible',
        _ => 'Prêt à synchroniser',
      };

  static Color _color(BuildContext context, String state) => switch (state) {
        'error' || 'conflict' => Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.primary,
      };
}
