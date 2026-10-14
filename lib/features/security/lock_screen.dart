import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/db/app_database.dart';
import '../../data/repositories/security_repository.dart';
import '../../data/repositories/tenant_repository.dart';
import '../../services/device_quick_unlock_service.dart';
import 'quick_unlock_challenge.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  List<AppUser> _users = const [];
  TenantMembershipCache? _cachedManager;
  DeviceUnlockProfile _quick = const DeviceUnlockProfile(hasPattern: false, biometricEnabled: false);
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
    final cached = await TenantRepository(AppDatabase.instance).cachedMembership();
    final profile = cached != null && cached.active && cached.isManager && !cached.mustChangePassword
        ? await DeviceQuickUnlockService.instance.profile(cached.organizationId, cached.cloudUserId)
        : const DeviceUnlockProfile(hasPattern: false, biometricEnabled: false);
    if (!mounted) return;
    setState(() {
      _users = users;
      _cachedManager = cached;
      _quick = profile;
      _selectedUserId = users.isEmpty ? null : users.first.id;
      _loading = false;
    });
  }

  bool get _quickAvailable {
    final cached = _cachedManager;
    if (!_quick.enabled || cached == null || !cached.active ||
        !cached.isManager || cached.mustChangePassword) return false;
    for (final user in _users) {
      if (user.id == _selectedUserId && user.role == 'manager' &&
          user.username.toLowerCase() == cached.username?.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showQuickUnlock() async {
    final userId = _selectedUserId;
    final cached = _cachedManager;
    if (_checking || !_quickAvailable || userId == null || cached == null) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: QuickUnlockChallenge(
          organizationId: cached.organizationId,
          cloudUserId: cached.cloudUserId,
          profile: _quick,
          verifyAndUnlock: (verify) async {
            if (!mounted || _selectedUserId != userId) return false;
            final result = await ref.read(securityRepositoryProvider)
                .authenticateWithDeviceUnlock(
              userId: userId, verify: verify);
            return result.success;
          },
          onUnlocked: () {
            if (sheetContext.mounted) Navigator.pop(sheetContext);
            if (mounted) widget.onUnlocked();
          },
        ),
      ),
    );
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
                  if (_quickAvailable) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _checking ? null : _showQuickUnlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Schéma ou empreinte digitale'),
                      ),
                    ),
                  ],
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
