import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/repository_providers.dart';
import '../core/session/operator_session.dart';
import '../features/security/lock_screen.dart';
import '../features/security/first_run_setup_screen.dart';
import '../services/cloud_snapshot_service.dart';
import 'home_shell.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _loading = true;
  bool _locked = false;
  bool _needsSetup = false;
  bool _backgroundTransitionRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_loading) return;
    // `inactive` est transitoire (sélecteur de fichier, dialogue système, etc.) :
    // ne pas verrouiller ni détruire la session dans cet état.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_synchronizeThenLock());
    }
  }

  Future<void> _synchronizeThenLock() async {
    if (_backgroundTransitionRunning) return;
    _backgroundTransitionRunning = true;
    try {
      if (OperatorSession.isAuthenticated) {
        try {
          await CloudSnapshotService.instance.synchronize();
        } catch (_) {
          // Le verrouillage local ne doit jamais être bloqué par une panne réseau.
        }
      }
      OperatorSession.clear();
      await _refreshAndLock();
    } finally {
      _backgroundTransitionRunning = false;
    }
  }

  Future<void> _refreshAndLock() async {
    final hasUsers = await ref.read(securityRepositoryProvider).hasUsers();
    if (!mounted) return;
    setState(() {
      _locked = hasUsers;
      _needsSetup = !hasUsers;
    });
  }

  Future<void> _check() async {
    final hasUsers = await ref.read(securityRepositoryProvider).hasUsers();
    OperatorSession.clear();
    if (!mounted) return;
    setState(() {
      _locked = hasUsers;
      _needsSetup = !hasUsers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_locked) {
      return LockScreen(onUnlocked: () {
        if (!mounted) return;
        setState(() => _locked = false);
      });
    }
    if (_needsSetup) {
      return FirstRunSetupScreen(
        onCompleted: () {
          if (!mounted) return;
          setState(() {
            _needsSetup = false;
            _locked = false;
          });
        },
      );
    }
    return const HomeShell();
  }
}
