import 'package:flutter/material.dart';

import '../../core/session/business_write_guard.dart';
import '../../core/security/manager_password_policy.dart';
import '../../core/session/operator_session.dart';
import '../../services/tenant_cloud_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _managers = const [];
  String? _error;
  bool _resetInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!OperatorSession.isAdmin) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await TenantCloudService.instance.managers();
      if (!mounted) return;
      setState(() {
        _managers = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _temporaryPassword() => ManagerPasswordPolicy.generateTemporary();

  Future<void> _createManager() async {
    BusinessWriteGuard.ensureTenantAdmin();
    final username = TextEditingController();
    final name = TextEditingController();
    final password = TextEditingController(text: _temporaryPassword());
    bool obscure = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Créer un gestionnaire'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom du gestionnaire')),
              const SizedBox(height: 10),
              TextField(controller: username, decoration: const InputDecoration(labelText: 'Identifiant de connexion')),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Mot de passe temporaire',
                  helperText: 'À transmettre au gestionnaire. Il devra le changer.',
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: () => setDialogState(() => password.text = _temporaryPassword()),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Générer'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true) {
      username.dispose();
      name.dispose();
      password.dispose();
      return;
    }
    try {
      if (name.text.trim().isEmpty || username.text.trim().length < 3 || password.text.length < 8) {
        throw ArgumentError('Nom, identifiant (3 caractères minimum) et mot de passe (8 caractères minimum) sont obligatoires.');
      }
      await TenantCloudService.instance.createManager(
        username: username.text,
        displayName: name.text,
        temporaryPassword: password.text,
      );
      if (!mounted) return;
      final shownPassword = password.text;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Compte créé'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Transmettez ces informations au gestionnaire :'),
            const SizedBox(height: 12),
            SelectableText('Code établissement : ${OperatorSession.organizationCode}\nIdentifiant : ${username.text.trim()}\nMot de passe temporaire : $shownPassword', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Le mot de passe ne sera pas réaffiché automatiquement.'),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('J’ai noté les identifiants'))],
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      username.dispose();
      name.dispose();
      password.dispose();
    }
  }

  Future<void> _toggle(Map<String, dynamic> manager) async {
    final active = manager['active'] == true;
    try {
      await TenantCloudService.instance.setManagerActive(manager['id'].toString(), !active);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> manager) async {
    if (_resetInProgress) return;
    final password = TextEditingController(text: _temporaryPassword());
    bool obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Réinitialiser — ${manager['display_name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Le code actuel sera remplacé côté serveur. '
              'Le gestionnaire devra le modifier à la prochaine connexion en ligne.'),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: 'Mot de passe temporaire',
                helperText: '10 caractères, majuscule, minuscule et chiffre',
                suffixIcon: IconButton(
                  tooltip: obscure ? 'Afficher le code' : 'Masquer le code',
                  onPressed: () => update(() => obscure = !obscure),
                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => update(() => password.text = _temporaryPassword()),
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Générer un autre code'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Réinitialiser')),
          ],
        ),
      ),
    );
    if (ok != true) { password.dispose(); return; }
    final secret = password.text;
    password.dispose();
    setState(() => _resetInProgress = true);
    try {
      await TenantCloudService.instance.resetManagerPassword(manager['id'].toString(), secret);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mot de passe réinitialisé'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('À transmettre de façon confidentielle au gestionnaire :'),
            const SizedBox(height: 12),
            SelectableText(secret, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text('Les anciens codes locaux ne peuvent pas être révoqués '
              'sur un appareil totalement hors ligne. Une reconnexion est nécessaire.'),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('J’ai noté le code'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _resetInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes & sécurité')),
      floatingActionButton: OperatorSession.isAdmin
          ? FloatingActionButton.extended(onPressed: _createManager, icon: const Icon(Icons.person_add_alt_1), label: const Text('Gestionnaire'))
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Établissement', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${OperatorSession.organizationName ?? '—'} · ${OperatorSession.organizationCode ?? '—'}'),
                const SizedBox(height: 6),
                Text('Session : ${OperatorSession.current} · ${OperatorSession.isAdmin ? 'Administrateur (lecture seule)' : 'Gestionnaire'}'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (!OperatorSession.isAdmin)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('La gestion des comptes est réservée à l’administrateur propriétaire de l’établissement.')))
          else if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
            if (_managers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Aucun gestionnaire. Utilisez le bouton « Gestionnaire » pour créer le premier compte opérationnel.'))),
            for (final manager in _managers)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(manager['active'] == true ? Icons.badge_outlined : Icons.person_off_outlined)),
                  title: Text((manager['display_name'] ?? 'Gestionnaire').toString()),
                  subtitle: Text('@${manager['username'] ?? '—'}${manager['active'] == true ? '' : ' · Désactivé'}${manager['must_change_password'] == true ? ' · Mot de passe temporaire' : ''}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (_resetInProgress) return;
                      if (value == 'reset') _resetPassword(manager);
                      if (value == 'toggle') _toggle(manager);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'reset', child: Text('Réinitialiser le mot de passe')),
                      PopupMenuItem(value: 'toggle', child: Text(manager['active'] == true ? 'Désactiver' : 'Réactiver')),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
