import 'package:flutter/material.dart';

import '../../services/device_quick_unlock_service.dart';
import 'pattern_input.dart';

class QuickUnlockChallenge extends StatefulWidget {
  const QuickUnlockChallenge({
    super.key,
    required this.organizationId,
    required this.cloudUserId,
    required this.profile,
    required this.onUnlocked,
    this.onUsePassword,
  });

  final String organizationId, cloudUserId;
  final DeviceUnlockProfile profile;
  final VoidCallback onUnlocked;
  final VoidCallback? onUsePassword;

  @override
  State<QuickUnlockChallenge> createState() => _QuickUnlockChallengeState();
}

class _QuickUnlockChallengeState extends State<QuickUnlockChallenge> {
  bool _busy = false;
  String? _error;

  Future<void> _attempt(Future<bool> Function() verifier) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final accepted = await verifier();
      if (!mounted) return;
      if (accepted) {
        widget.onUnlocked();
      } else {
        setState(() => _error = 'Déverrouillage refusé. Réessayez ou utilisez votre mot de passe.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded, size: 48),
          const SizedBox(height: 14),
          Text('GesApp verrouillé', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Utilisez la méthode enregistrée sur cet appareil.',
            textAlign: TextAlign.center),
          if (widget.profile.hasPattern) ...[
            const SizedBox(height: 18),
            const Text('Dessinez votre schéma'),
            const SizedBox(height: 12),
            PatternInput(
              key: ValueKey(widget.cloudUserId),
              enabled: !_busy,
              onComplete: (pattern) => _attempt(() =>
                DeviceQuickUnlockService.instance.verifyPattern(
                  widget.organizationId, widget.cloudUserId, pattern)),
            ),
          ],
          if (widget.profile.biometricEnabled) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : () => _attempt(() =>
                DeviceQuickUnlockService.instance.verifyBiometrics(
                  widget.organizationId, widget.cloudUserId)),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Déverrouiller par biométrie'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const CircularProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (widget.onUsePassword != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _busy ? null : widget.onUsePassword,
              icon: const Icon(Icons.password_rounded),
              label: const Text('Se connecter avec le mot de passe principal'),
            ),
          ],
        ]),
      ),
    ),
  );
}
