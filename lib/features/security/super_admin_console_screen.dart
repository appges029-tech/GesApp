import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../services/super_admin_service.dart';
import 'super_admin_school_detail_screen.dart';

class SuperAdminConsoleScreen extends StatefulWidget {
  const SuperAdminConsoleScreen({super.key});

  @override
  State<SuperAdminConsoleScreen> createState() => _SuperAdminConsoleScreenState();
}

class _SuperAdminConsoleScreenState extends State<SuperAdminConsoleScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _schoolQuery = TextEditingController();
  final _activityQuery = TextEditingController();
  String _schoolStatus = 'all';
  DateTime? _lastSuccessAt;
  bool _lastRefreshFailed = false;
  final _service = SuperAdminService.instance;

  Timer? _timer;
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  bool _refreshing = false;
  bool _showCreate = false;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _schoolQuery.dispose();
    _activityQuery.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _code.text.trim().isEmpty) {
      setState(() => _error = 'Renseignez l’identifiant et le code Super Admin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.login(email: _email.text, code: _code.text);
      _code.clear();
      await _refresh();
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refresh(silent: true),
      );
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing || !_service.isAuthenticated) return;
    _refreshing = true;
    if (!silent && mounted) setState(() {});
    try {
      final value = await _service.overview();
      if (mounted) {
        setState(() {
          _data = value;
          _error = null;
          _lastRefreshFailed = false;
          _lastSuccessAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _lastRefreshFailed = true;
        if (!silent) _error = _message(e);
      });
      if (!_service.isAuthenticated && mounted) {
        _timer?.cancel();
        setState(() => _data = null);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _logout() async {
    _timer?.cancel();
    await _service.logout();
    if (!mounted) return;
    setState(() {
      _data = null;
      _error = null;
      _showCreate = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isAuthenticated || _data == null) return _loginPage();
    return _dashboard();
  }

  Widget _loginPage() {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Super Admin')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 38,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Console Super Admin',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Contrôler les écoles, les comptes, les appareils et les synchronisations.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Identifiant Super Admin',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(
                        labelText: 'Code Super Admin',
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _busy ? null : _login,
                      icon: const Icon(Icons.login_rounded),
                      label: Text(_busy ? 'Connexion…' : 'Ouvrir la console'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(text: _error!),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Le code n’est pas stocké dans l’application. La session est temporaire et validée côté serveur.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    final totals = _map(_data!['totals']);
    final allSchools = _list(_data!['organizations']);
    final search = _schoolQuery.text.trim().toLowerCase();
    final schools = allSchools.where((school) {
      final admin = _map(school['admin']);
      final managers = _list(school['managers']);
      final text = [school['name'], school['code'], admin['display_name'],
        ...managers.map((manager) => manager['display_name'])]
          .map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return (search.isEmpty || text.contains(search)) &&
        (_schoolStatus == 'all' || school['subscription_effective_status'] == _schoolStatus);
    }).toList(growable: false);
    final requests = _list(_data!['pending_requests']);
    final activitySearch = _activityQuery.text.trim().toLowerCase();
    final events = _list(_data!['recent_activity']).where((event) {
      final text = [event['organization_name'], event['module'],
        event['event_type'], event['message']]
          .map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return activitySearch.isEmpty || text.contains(activitySearch);
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrôle SaaS'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.monitor_heart_rounded),
                title: Text(
                  _lastRefreshFailed ? 'Supervision interrompue' : 'Supervision connectée',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(_lastRefreshFailed
                    ? 'Actualisation échouée : données éventuellement anciennes'
                    : 'Actualisation toutes les 30 secondes · Dernier succès : '
                        '${_lastSuccessAt?.hour.toString().padLeft(2, '0') ?? '—'}:'
                        '${_lastSuccessAt?.minute.toString().padLeft(2, '0') ?? '—'}'),
                trailing: _LiveDot(active: !_lastRefreshFailed),
              ),
            ),
            const SizedBox(height: 12),
            _Metrics(totals: totals),
            if ((totals['subscriptions_expired'] as num? ?? 0) > 0 ||
                (totals['sync_errors_recent'] as num? ?? 0) > 0) ...[
              const SizedBox(height: 10),
              Card(child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('Alertes de supervision'),
                subtitle: Text('${totals['subscriptions_expired'] ?? 0} abonnement(s) expiré(s) · '
                    '${totals['sync_errors_recent'] ?? 0} dernier(s) incident(s) de synchronisation connu(s)'),
              )),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => setState(() => _showCreate = !_showCreate),
              icon: Icon(_showCreate ? Icons.close_rounded : Icons.add_business_rounded),
              label: Text(_showCreate ? 'Fermer' : 'Créer une école'),
            ),
            if (_showCreate) ...[
              const SizedBox(height: 12),
              _CreateSchoolCard(
                onCreated: () async {
                  setState(() => _showCreate = false);
                  await _refresh();
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(text: _error!),
            ],
            const SizedBox(height: 22),
            _TitleRow(
              title: 'Demandes administrateurs',
              subtitle: requests.length.toString() + ' en attente',
            ),
            const SizedBox(height: 10),
            if (requests.isEmpty)
              const _EmptyCard(
                icon: Icons.check_circle_outline_rounded,
                text: 'Aucune demande en attente.',
              )
            else
              for (final request in requests) ...[
                _PendingRequestCard(
                  request: request,
                  onReviewed: (approve, cycle) async {
                    if (approve) {
                      await _service.approveRequest(request['id'].toString(), cycle);
                    } else {
                      await _service.rejectRequest(request['id'].toString());
                    }
                    await _refresh();
                  },
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 22),
            _TitleRow(
              title: 'Établissements',
              subtitle: '${schools.length}/${allSchools.length} affichés',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _schoolQuery,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Rechercher une école, un code ou un responsable',
                prefixIcon: Icon(Icons.search_outlined),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _schoolStatus,
              decoration: const InputDecoration(labelText: 'Filtrer par statut d’abonnement'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tous les statuts')),
                DropdownMenuItem(value: 'active', child: Text('Abonnement actif')),
                DropdownMenuItem(value: 'expired', child: Text('Abonnement expiré')),
                DropdownMenuItem(value: 'suspended', child: Text('École suspendue')),
                DropdownMenuItem(value: 'legacy', child: Text('École historique')),
              ],
              onChanged: (status) => setState(() => _schoolStatus = status ?? 'all'),
            ),
            const SizedBox(height: 10),
            if (schools.isEmpty)
              const _EmptyCard(
                icon: Icons.school_outlined,
                text: 'Aucune école enregistrée.',
              )
            else
              for (final school in schools) ...[
                _SchoolCard(
                  school: school,
                  onToggle: (active) async {
                    await _service.setSchoolActive(school['id'].toString(), active);
                    await _refresh();
                  },
                  onRenew: (cycle, reference) async {
                    await _service.renewSubscription(school['id'].toString(), cycle,
                        reference: reference);
                    await _refresh();
                  },
                  onDetails: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => SuperAdminSchoolDetailScreen(
                      organizationId: school['id'].toString(),
                      schoolName: school['name']?.toString() ?? 'Établissement',
                    )),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 18),
            _TitleRow(
              title: 'Activité récente',
              subtitle: '${events.length} résultat(s) parmi les derniers événements',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _activityQuery,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Filtrer les activités récentes',
                prefixIcon: Icon(Icons.manage_search_outlined),
              ),
            ),
            const SizedBox(height: 10),
            if (events.isEmpty)
              const _EmptyCard(
                icon: Icons.timeline_outlined,
                text: 'Aucune activité centralisée pour le moment.',
              )
            else
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < events.length && i < 30; i++) ...[
                      _ActivityTile(event: events[i]),
                      if (i < events.length - 1 && i < 29)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static String _message(Object e) =>
      e.toString().replaceFirst('Bad state: ', '');
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.totals});
  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (
        Icons.school_rounded,
        'Écoles actives',
        (totals['active_schools'] ?? 0).toString() +
            '/' +
            (totals['schools'] ?? 0).toString(),
      ),
      (
        Icons.manage_accounts_rounded,
        'Gestionnaires',
        (totals['managers'] ?? 0).toString(),
      ),
      (
        Icons.devices_other_rounded,
        'Appareils',
        (totals['devices'] ?? 0).toString(),
      ),
      (
        Icons.wifi_tethering_rounded,
        'En ligne',
        (totals['online_devices'] ?? 0).toString(),
      ),
      (Icons.credit_card_outlined, 'Abonnements actifs',
       (totals['subscriptions_active'] ?? 0).toString()),
      (Icons.event_busy_outlined, 'Abonnements expirés',
       (totals['subscriptions_expired'] ?? 0).toString()),
      (Icons.pending_actions_outlined, 'Demandes en attente',
       (totals['requests_pending'] ?? 0).toString()),
      (Icons.sync_problem_outlined, 'Incidents sync. récents',
       (totals['sync_errors_recent'] ?? 0).toString()),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 850
            ? 4
            : constraints.maxWidth >= 500
                ? 2
                : 1;
        final width = (constraints.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(child: Icon(item.$1)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$3,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(item.$2),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CreateSchoolCard extends StatefulWidget {
  const _CreateSchoolCard({required this.onCreated});
  final Future<void> Function() onCreated;

  @override
  State<_CreateSchoolCard> createState() => _CreateSchoolCardState();
}

class _CreateSchoolCardState extends State<_CreateSchoolCard> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminName = TextEditingController();
  final _adminPassword = TextEditingController();
  final _managerUsername = TextEditingController();
  final _managerName = TextEditingController();
  final _managerPassword = TextEditingController();
  String _subscriptionCycle = 'monthly';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _adminEmail.dispose();
    _adminName.dispose();
    _adminPassword.dispose();
    _managerUsername.dispose();
    _managerName.dispose();
    _managerPassword.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SuperAdminService.instance.createSchool(
        name: _name.text,
        code: _code.text,
        administratorEmail: _adminEmail.text,
        administratorName: _adminName.text,
        administratorPassword: _adminPassword.text,
        managerUsername: _managerUsername.text,
        managerName: _managerName.text,
        managerPassword: _managerPassword.text,
        subscriptionCycle: _subscriptionCycle,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('École, administrateur et gestionnaire créés.'),
        ),
      );
      await widget.onCreated();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nouvel établissement',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _field(_name, 'Nom de l’école', Icons.school_outlined),
            const SizedBox(height: 10),
            _field(_code, 'Code souhaité (facultatif)', Icons.tag_rounded),
            const SizedBox(height: 16),
            const Text(
              'Administrateur',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _field(_adminName, 'Nom administrateur', Icons.person_outline),
            const SizedBox(height: 10),
            _field(
              _adminEmail,
              'E-mail administrateur',
              Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            _field(
              _adminPassword,
              'Mot de passe temporaire (10+ caractères, majuscule, minuscule, chiffre)',
              Icons.password_rounded,
              obscure: true,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gestionnaire',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _field(_managerName, 'Nom gestionnaire', Icons.badge_outlined),
            const SizedBox(height: 10),
            _field(
              _managerUsername,
              'Identifiant gestionnaire',
              Icons.account_circle_outlined,
            ),
            const SizedBox(height: 10),
            _field(
              _managerPassword,
              'Mot de passe temporaire (10+ caractères, majuscule, minuscule, chiffre)',
              Icons.password_outlined,
              obscure: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _subscriptionCycle,
              decoration: const InputDecoration(labelText: 'Abonnement après paiement'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Mensuel · 1 mois')),
                DropdownMenuItem(value: 'annual', child: Text('Annuel · 1 an')),
              ],
              onChanged: (value) => setState(() => _subscriptionCycle = value ?? 'monthly'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(text: _error!),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_business_rounded),
              label: Text(
                _busy ? 'Création…' : 'Créer l’école et les accès',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SchoolCard extends StatefulWidget {
  const _SchoolCard({
    required this.school,
    required this.onToggle,
    required this.onRenew,
    required this.onDetails,
  });
  final Map<String, dynamic> school;
  final Future<void> Function(bool active) onToggle;
  final Future<void> Function(String cycle, String reference) onRenew;
  final VoidCallback onDetails;

  @override
  State<_SchoolCard> createState() => _SchoolCardState();
}

class _SchoolCardState extends State<_SchoolCard> {
  bool _busy = false;
  String _cycle = 'monthly';

  @override
  Widget build(BuildContext context) {
    final school = widget.school;
    final active = school['active'] == true;
    final admin = _asMap(school['admin']);
    final managers = _asList(school['managers']);
    final sync = _asMap(school['sync']);
    final online = (school['online_device_count'] as num?)?.toInt() ?? 0;
    final devices = (school['device_count'] as num?)?.toInt() ?? 0;
    final revision = (sync['revision'] as num?)?.toInt() ?? 0;
    final size = (sync['size_bytes'] as num?)?.toInt();

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(active ? Icons.school_rounded : Icons.pause_circle_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        school['name']?.toString() ?? 'École',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        (school['code'] ?? '—').toString() +
                            ' · ' +
                            (active ? 'Actif' : 'Suspendu'),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () async {
                          final next = !active;
                          setState(() => _busy = true);
                          try {
                            await widget.onToggle(next);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: Text(active ? 'Suspendre' : 'Réactiver'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Admin : ' + (admin['display_name'] ?? '—').toString(),
                  ),
                ),
                Chip(label: Text(managers.length.toString() + ' gestionnaire(s)')),
                Chip(label: Text(online.toString() + '/' + devices.toString() + ' en ligne')),
                Chip(label: Text('Révision ' + revision.toString())),
                Chip(label: Text('Abonnement : ' +
                    (school['subscription_effective_status'] ?? '—').toString())),
                Chip(label: Text('Échéance : ' +
                    _date(school['subscription_expires_at']))),
                if (size != null) Chip(label: Text(_bytes(size))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Dernier appareil : ' + _date(school['last_seen_at']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Dernière synchro : ' + _date(sync['updated_at']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_asMap(school['latest_sync_event'])['event_type'] == 'sync_error')
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('Dernier incident de synchronisation connu'),
                subtitle: Text('Consultez la fiche pour le détail.'),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onDetails,
                icon: const Icon(Icons.open_in_new_outlined),
                label: const Text('Voir la fiche complète'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _cycle,
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                    DropdownMenuItem(value: 'annual', child: Text('Annuel')),
                  ],
                  onChanged: _busy ? null :
                      (value) => setState(() => _cycle = value ?? 'monthly'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () async {
                    final reference = TextEditingController();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => StatefulBuilder(
                        builder: (dialogContext, update) => AlertDialog(
                          title: const Text('Confirmer le renouvellement ?'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vérifiez la réception du paiement. '
                                'Ce renouvellement prolongera l’accès de cette école.'),
                              const SizedBox(height: 12),
                              TextField(
                                controller: reference,
                                onChanged: (_) => update(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Référence du paiement / justificatif *',
                                  hintText: 'Ex. CAISSE-001 ou VIRT-2026-001',
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton(
                              onPressed: reference.text.trim().length >= 3
                                  ? () => Navigator.pop(dialogContext, true) : null,
                              child: const Text('Paiement confirmé'),
                            ),
                          ],
                        ),
                      ),
                    );
                    final paymentReference = reference.text.trim();
                    reference.dispose();
                    if (confirmed != true || !mounted) return;
                    setState(() => _busy = true);
                    try {
                      await widget.onRenew(_cycle, paymentReference);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Abonnement renouvelé et référencé.')));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Renouvellement refusé : $e')));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Valider paiement / renouveler'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static String _bytes(int value) {
    if (value >= 1024 * 1024) {
      return (value / (1024 * 1024)).toStringAsFixed(1) + ' Mo';
    }
    if (value >= 1024) return (value / 1024).toStringAsFixed(0) + ' Ko';
    return value.toString() + ' o';
  }

  static String _date(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return two(d.day) +
        '/' +
        two(d.month) +
        ' ' +
        two(d.hour) +
        ':' +
        two(d.minute);
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final type = event['event_type']?.toString() ?? 'event';
    final module = event['module']?.toString() ?? 'system';
    final school = event['organization_name']?.toString();
    final message = event['message']?.toString();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.bolt_outlined),
      title: Text(
        message == null || message.isEmpty ? type : message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        (school == null || school.isEmpty ? 'Plateforme' : school) +
            ' · ' +
            module +
            ' · ' +
            _date(event['created_at']),
      ),
    );
  }

  static String _date(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return two(d.day) +
        '/' +
        two(d.month) +
        ' ' +
        two(d.hour) +
        ':' +
        two(d.minute) +
        ':' +
        two(d.second);
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: const BoxDecoration(
        color: active ? Colors.green : Colors.orange,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(text),
      ),
    );
  }
}

class _PendingRequestCard extends StatefulWidget {
  const _PendingRequestCard({required this.request, required this.onReviewed});
  final Map<String, dynamic> request;
  final Future<void> Function(bool approve, String cycle) onReviewed;

  @override
  State<_PendingRequestCard> createState() => _PendingRequestCardState();
}

class _PendingRequestCardState extends State<_PendingRequestCard> {
  bool _busy = false;
  String _cycle = 'monthly';

  Future<void> _review(bool approve) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Valider cet administrateur ?' : 'Refuser la demande ?'),
        content: Text(approve
          ? 'Confirmez uniquement après réception du paiement. '
            'Un établissement et un abonnement actif seront alors créés.'
          : 'Cette action refuse la demande sans créer de compte actif.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Valider le paiement' : 'Refuser')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onReviewed(approve, _cycle);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(request['school_name']?.toString() ?? 'Établissement',
                style: Theme.of(context).textTheme.titleMedium),
            Text((request['display_name'] ?? '').toString() + ' · ' +
                (request['email'] ?? '').toString()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _cycle,
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                    DropdownMenuItem(value: 'annual', child: Text('Annuel')),
                  ],
                  onChanged: _busy ? null :
                      (value) => setState(() => _cycle = value ?? 'monthly'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _review(true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Paiement reçu · Approuver'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _review(false),
                  child: const Text('Refuser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
