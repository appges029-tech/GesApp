import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/repositories/security_repository.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  List<AppUser> _users = const [];
  String? _selectedUserId;
  String? _error;
  bool _checking = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final users = await ref.read(securityRepositoryProvider).users(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _users = users;
      _selectedUserId = users.isEmpty ? null : users.first.id;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final userId = _selectedUserId;
    if (userId == null) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await ref.read(securityRepositoryProvider).authenticate(userId, _pin.text);
    if (!mounted) return;
    if (result.success) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = result.lockedUntil == null
          ? result.message
          : '${result.message}\nRéessayez après ${TimeOfDay.fromDateTime(result.lockedUntil!.toLocal()).format(context)}.';
      _pin.clear();
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.manage_accounts_outlined, size: 58, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Connexion GesApp', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Sélectionnez le compte puis saisissez son PIN hérité ou son mot de passe.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUserId,
                    decoration: const InputDecoration(labelText: 'Compte'),
                    items: _users.map((u) => DropdownMenuItem(value: u.id, child: Text(u.displayName))).toList(),
                    onChanged: _checking ? null : (value) => setState(() { _selectedUserId = value; _error = null; _pin.clear(); }),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    maxLength: 64,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(errorText: _error, hintText: 'PIN ou mot de passe', counterText: ''),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking || _selectedUserId == null ? null : _submit,
                      icon: _checking ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                      label: Text(_checking ? 'Vérification…' : 'Se connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
