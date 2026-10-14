import 'package:flutter/material.dart';

import '../core/session/operator_session.dart';
import '../core/session/tenant_subscription_access.dart';
import '../features/security/quick_unlock_challenge.dart';
import '../services/device_quick_unlock_service.dart';
import '../services/tenant_cloud_service.dart';

/// Sits AFTER cloud tenant verification and BEFORE HomeShell.
/// A quick unlock never signs into Supabase or changes the selected tenant.
class QuickUnlockGate extends StatefulWidget {
  const QuickUnlockGate({super.key, required this.child});
  final Widget child;

  @override
  State<QuickUnlockGate> createState() => _QuickUnlockGateState();
}

class _QuickUnlockGateState extends State<QuickUnlockGate>
    with WidgetsBindingObserver {
  bool _loading = true, _locked = false;
  DeviceUnlockProfile _profile =
      const DeviceUnlockProfile(hasPattern: false, biometricEnabled: false);

  String get _org => OperatorSession.organizationId ?? '';
  String get _user => OperatorSession.cloudUserId ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceQuickUnlockService.instance.changes.addListener(_profileChanged);
    _check(initial: true);
  }

  void _profileChanged() { _check(initial: false); }

  Future<void> _check({required bool initial}) async {
    final scopeOrg = _org, scopeUser = _user;
    final profile = await DeviceQuickUnlockService.instance.profile(
      scopeOrg, scopeUser);
    if (!mounted || _org != scopeOrg || _user != scopeUser) return;
    setState(() {
      _profile = profile;
      _locked = initial ? profile.enabled : (_locked && profile.enabled);
      _loading = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (_profile.enabled && mounted) setState(() => _locked = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceQuickUnlockService.instance.changes.removeListener(_profileChanged);
    super.dispose();
  }

  Future<void> _usePassword() async {
    try {
      await TenantCloudService.instance.signOut();
    } catch (_) {
      // The cloud gate remains responsible for its own auth/error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_locked || !_profile.enabled) return widget.child;
    final lockedOrganization = _org;
    final lockedUser = _user;
    return Scaffold(
      body: SafeArea(
        child: QuickUnlockChallenge(
          organizationId: _org,
          cloudUserId: _user,
          profile: _profile,
          onUnlocked: () {
            if (!OperatorSession.isAuthenticated ||
                !TenantSubscriptionAccess.instance.isAllowed ||
                _org != lockedOrganization || _user != lockedUser ||
                TenantCloudService.instance.currentCloudUser?.id != lockedUser) {
              return; // Reject stale biometric responses for changed sessions.
            }
            if (mounted) setState(() => _locked = false);
          },
          onUsePassword: _usePassword,
        ),
      ),
    );
  }
}
