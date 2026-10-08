import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/session/operator_session.dart';
import '../../core/session/tenant_subscription_access.dart';
import '../../services/tenant_cloud_service.dart';

class TenantSubscriptionOverlay extends StatefulWidget {
  const TenantSubscriptionOverlay({super.key});

  @override
  State<TenantSubscriptionOverlay> createState() => _TenantSubscriptionOverlayState();
}

class _TenantSubscriptionOverlayState extends State<TenantSubscriptionOverlay>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(TenantSubscriptionAccess.instance.tick()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(TenantSubscriptionAccess.instance.tick());
    }
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() { _checking = true; _message = null; });
    try {
      await TenantCloudService.instance.refreshSubscription();
      if (mounted && !TenantSubscriptionAccess.instance.isAllowed) {
        setState(() => _message = 'Paiement non encore confirmé par le Super Admin.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = "Connexion nécessaire pour obtenir l'activation du Super Admin.");
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _logout() async {
    try {
      await TenantCloudService.instance.signOut();
    } catch (_) {
      OperatorSession.clear();
      TenantSubscriptionAccess.instance.clearInMemory();
    }
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TenantSubscriptionAccess.instance.changes,
      builder: (context, _, __) {
        final access = TenantSubscriptionAccess.instance;
        if (!OperatorSession.isAuthenticated || access.isAllowed) {
          return const SizedBox.shrink();
        }
        final expiry = access.expiresAt?.toLocal();
        final endDate = expiry == null ? 'Non renseignée' :
            _twoDigits(expiry.day) + '/' + _twoDigits(expiry.month) + '/' +
            expiry.year.toString() + ' ' + _twoDigits(expiry.hour) + ':' +
            _twoDigits(expiry.minute);
        return Positioned.fill(
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock_rounded, size: 68),
                        const SizedBox(height: 14),
                        Text('Abonnement GesApp suspendu',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(access.denialReason,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text('Échéance : $endDate',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        const Text(
                          "Vos données scolaires sont conservées. Après paiement et "
                          "validation du Super Admin, connectez cet appareil à Internet "
                          "puis appuyez sur « Vérifier la réactivation ».",
                          textAlign: TextAlign.center,
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 10),
                          Text(_message!, textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _checking ? null : _refresh,
                          icon: const Icon(Icons.sync_rounded),
                          label: Text(_checking ? 'Vérification…' : 'Vérifier la réactivation'),
                        ),
                        TextButton(
                          onPressed: _logout,
                          child: const Text('Changer de compte'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
