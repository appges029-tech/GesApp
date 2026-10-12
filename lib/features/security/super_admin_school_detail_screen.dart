import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/super_admin_service.dart';

/// Fiche SaaS : métadonnées centrales uniquement, jamais de données scolaires.
class SuperAdminSchoolDetailScreen extends StatefulWidget {
  const SuperAdminSchoolDetailScreen({
    super.key,
    required this.organizationId,
    required this.schoolName,
  });

  final String organizationId;
  final String schoolName;

  @override
  State<SuperAdminSchoolDetailScreen> createState() =>
      _SuperAdminSchoolDetailScreenState();
}

class _SuperAdminSchoolDetailScreenState
    extends State<SuperAdminSchoolDetailScreen> {
  Map<String, dynamic>? _details;
  bool _loading = false;
  bool _actionBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static List<Map<String, dynamic>> _list(dynamic value) =>
      value is List
          ? value.whereType<Map>().map((value) =>
              Map<String, dynamic>.from(value)).toList(growable: false)
          : const [];

  static String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? '—'
        : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SuperAdminService.instance
          .organizationDetail(widget.organizationId);
      if (mounted) setState(() => _details = data);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notify(String message) {
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleManager(Map<String, dynamic> member) async {
    if (_actionBusy) return;
    final currentlyActive = member['active'] == true;
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(currentlyActive ? 'Désactiver le gestionnaire ?'
            : 'Réactiver le gestionnaire ?'),
        content: const Text(
          'Ce changement concerne uniquement le compte cloud sélectionné. '
          'Un appareil déjà connecté hors ligne peut conserver temporairement '
          'une session locale. Aucune donnée scolaire ne sera effacée.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: Text(currentlyActive ? 'Désactiver' : 'Réactiver')),
        ],
      ),
    );
    if (confirmation != true || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await SuperAdminService.instance.setManagerActive(
        organizationId: widget.organizationId,
        memberId: member['id'].toString(),
        active: !currentlyActive,
      );
      await _refresh();
      _notify('Statut du gestionnaire mis à jour.');
    } catch (error) {
      _notify('Modification refusée : $error');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _resetManager(Map<String, dynamic> member) async {
    if (_actionBusy) return;
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Réinitialiser le mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gestionnaire : ${member['display_name'] ?? '—'}'),
              const SizedBox(height: 8),
              const Text('Définissez un mot de passe provisoire d’au moins '
                  '10 caractères, avec majuscule, minuscule et chiffre. '
                  'Ne transmettez ce mot de passe que par un canal sûr.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                onChanged: (_) => update(() {}),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe provisoire',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: _strongPassword(controller.text)
                  ? () => Navigator.pop(dialog, controller.text)
                  : null,
              child: const Text('Réinitialiser'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (password == null || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await SuperAdminService.instance.resetManagerPassword(
        organizationId: widget.organizationId,
        memberId: member['id'].toString(),
        temporaryPassword: password,
      );
      await _refresh();
      _notify('Mot de passe modifié. Le gestionnaire devra le changer.');
    } catch (error) {
      _notify('Réinitialisation refusée : $error');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  bool _strongPassword(String text) =>
      text.length >= 10 && RegExp(r'[A-Z]').hasMatch(text)
      && RegExp(r'[a-z]').hasMatch(text) && RegExp(r'[0-9]').hasMatch(text);

  Widget _section(String title, List<Widget> children, {IconData? icon}) =>
      Card(
        child: ExpansionTile(
          initiallyExpanded: title == 'Abonnement et historique',
          leading: Icon(icon ?? Icons.info_outline),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final school = _map(details?['organization']);
    final members = _list(details?['members']);
    final devices = _list(details?['devices']);
    final payments = _list(details?['subscription_payments']);
    final events = _list(details?['events']);
    final sync = _map(details?['sync']);
    final managers = members.where((member) => member['role'] == 'manager').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schoolName, maxLines: 1,
          overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _loading || _actionBusy ? null : _refresh,
            tooltip: 'Actualiser la fiche',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Chargement impossible'),
                subtitle: Text(_error!),
                trailing: IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              )),
            if (details == null && !_loading && _error == null)
              const Center(child: Text('Aucune information disponible.')),
            if (school.isNotEmpty) ...[
              Card(child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(school['name']?.toString() ?? widget.schoolName),
                  subtitle: Text('Code : ${school['code'] ?? '—'}'),
                  trailing: Text(school['active'] == true
                      ? 'Actif' : 'Suspendu'),
                ),
                ListTile(
                  title: const Text('Créé le'),
                  trailing: Text(_date(school['created_at'])),
                ),
              ])),
              _section('Abonnement et historique', [
                ListTile(
                  title: const Text('Statut'),
                  trailing: Text(school['subscription_status']?.toString() ?? '—'),
                ),
                ListTile(
                  title: const Text('Période contractuelle'),
                  subtitle: Text(school['subscription_cycle'] == 'annual'
                      ? 'Annuel' : school['subscription_cycle'] == 'monthly'
                      ? 'Mensuel' : 'Historique / non défini'),
                  trailing: Text('Fin : ${_date(school['subscription_expires_at'])}'),
                ),
                const Divider(),
                if (payments.isEmpty)
                  const ListTile(title: Text('Aucune activation enregistrée'))
                else
                  for (final payment in payments)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(payment['event_type'] == 'renewal'
                          ? 'Renouvellement' : 'Activation'),
                      subtitle: Text(
                        'Confirmé : ${_date(payment['confirmed_at'])}\n'
                        'Référence : ${payment['reference'] ?? 'Non renseignée'}\n'
                        'Échéance : ${_date(payment['expires_at'])}',
                      ),
                      isThreeLine: true,
                      trailing: Text(payment['cycle'] == 'annual'
                          ? 'Annuel' : 'Mensuel'),
                    ),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Les anciens enregistrements ne contiennent '
                      'pas le montant payé : aucun total financier n’est '
                      'présenté sans donnée vérifiable.'),
                ),
              ], icon: Icons.credit_card),
              _section('Comptes et gestionnaires (${members.length})', [
                for (final member in members)
                  Column(children: [
                    ListTile(
                      leading: Icon(member['role'] == 'admin'
                          ? Icons.admin_panel_settings_outlined
                          : Icons.manage_accounts_outlined),
                      title: Text(member['display_name']?.toString() ?? 'Compte'),
                      subtitle: Text(
                        '${member['role'] == 'admin' ? 'Administrateur' : 'Gestionnaire'}'
                        ' · ${member['username'] ?? 'Sans identifiant local'}\n'
                        '${member['active'] == true ? 'Actif' : 'Désactivé'}'
                        ' · ${member['must_change_password'] == true ? 'Mot de passe à changer' : 'Accès normal'}',
                      ),
                      isThreeLine: true,
                    ),
                    if (member['role'] == 'manager')
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 12),
                        child: Wrap(spacing: 8, children: [
                          OutlinedButton(
                            onPressed: _actionBusy ? null : () => _toggleManager(member),
                            child: Text(member['active'] == true
                                ? 'Désactiver' : 'Réactiver'),
                          ),
                          OutlinedButton(
                            onPressed: _actionBusy ? null : () => _resetManager(member),
                            child: const Text('Réinitialiser l’accès'),
                          ),
                        ]),
                      ),
                    const Divider(height: 1),
                  ]),
                if (managers.isEmpty) const ListTile(
                  title: Text('Aucun gestionnaire rattaché')),
              ], icon: Icons.manage_accounts_outlined),
              _section('Appareils et connexions (${devices.length})', [
                if (devices.isEmpty)
                  const ListTile(title: Text('Aucun appareil enregistré'))
                else
                  for (final device in devices)
                    ListTile(
                      leading: const Icon(Icons.devices_outlined),
                      title: Text('${device['platform'] ?? 'Inconnu'}'
                        ' · Version ${device['app_version'] ?? 'non transmise'}'),
                      subtitle: Text('Dernier contact : ${_date(device['last_seen_at'])}\n'
                        'Clé appareil : ${(device['device_key'] ?? '').toString().substring(0,
                          (device['device_key'] ?? '').toString().length.clamp(0, 12))}…'),
                      isThreeLine: true,
                    ),
              ], icon: Icons.devices_other_outlined),
              _section('Synchronisation', [
                ListTile(
                  title: const Text('Révision distante'),
                  trailing: Text('${sync['revision'] ?? '—'}'),
                ),
                ListTile(
                  title: const Text('Dernière publication'),
                  trailing: Text(_date(sync['uploaded_at'])),
                ),
                ListTile(
                  title: const Text('Dernière mise à jour'),
                  trailing: Text(_date(sync['updated_at'])),
                ),
                const ListTile(
                  title: Text('Actions de récupération protégées'),
                  subtitle: Text('Aucune restauration, suppression ou fusion '
                    'de base scolaire n’est autorisée depuis cette fiche.'),
                ),
              ], icon: Icons.sync_outlined),
              _section('Journal des événements (${events.length})', [
                if (events.isEmpty)
                  const ListTile(title: Text('Aucune activité signalée'))
                else
                  for (final event in events)
                    ListTile(
                      leading: Icon(event['event_type'] == 'sync_error'
                          ? Icons.warning_amber : Icons.history),
                      title: Text(event['message']?.toString()
                          ?? event['event_type']?.toString() ?? 'Événement'),
                      subtitle: Text('${event['module'] ?? 'système'} · ${_date(event['created_at'])}'),
                    ),
              ], icon: Icons.history),
            ],
          ],
        ),
      ),
    );
  }
}
