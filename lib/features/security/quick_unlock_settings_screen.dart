import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/session/operator_session.dart';
import '../../services/device_quick_unlock_service.dart';
import 'pattern_input.dart';

class QuickUnlockSettingsScreen extends StatefulWidget {
  const QuickUnlockSettingsScreen({super.key});

  @override
  State<QuickUnlockSettingsScreen> createState() => _QuickUnlockSettingsScreenState();
}

class _QuickUnlockSettingsScreenState extends State<QuickUnlockSettingsScreen> {
  final _service = DeviceQuickUnlockService.instance;
  DeviceUnlockProfile _profile = const DeviceUnlockProfile(
    hasPattern: false, biometricEnabled: false);
  bool _loading = true, _busy = false, _settingPattern = false;
  List<int>? _firstPattern;
  String? _message;

  String get _org => OperatorSession.organizationId ?? '';
  String get _user => OperatorSession.cloudUserId ?? '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final next = await _service.profile(_org, _user);
    if (mounted) setState(() {
      _profile = next;
      _loading = false;
    });
  }

  Future<bool> _verifyMainPassword() async {
    String password = '';
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer votre identité'),
        content: TextFormField(
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Mot de passe GesApp actuel'),
          onChanged: (value) => password = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, password),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (answer == null || answer.isEmpty) return false;
    final accepted = await _service.verifyCurrentCloudPassword(answer, _user);
    if (!accepted && mounted) setState(() =>
      _message = 'Mot de passe incorrect ou connexion Internet indisponible.');
    return accepted;
  }

  Future<void> _startPattern() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (!await _verifyMainPassword() || !mounted) return;
      setState(() {
        _firstPattern = null;
        _settingPattern = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptPattern(List<int> pattern) async {
    if (_busy || !_settingPattern) return;
    if (pattern.length < 6) {
      setState(() => _message = 'Reliez au moins six points différents.');
      return;
    }
    final first = _firstPattern;
    if (first == null) {
      setState(() {
        _firstPattern = pattern;
        _message = 'Redessinez exactement le même schéma pour confirmer.';
      });
      return;
    }
    if (!listEquals(first, pattern)) {
      setState(() {
        _firstPattern = null;
        _message = 'Les deux schémas sont différents. Recommencez.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.setPattern(_org, _user, pattern);
      if (!mounted) return;
      setState(() {
        _settingPattern = false;
        _firstPattern = null;
        _message = 'Schéma activé sur cet appareil uniquement.';
      });
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = 'Impossible d’activer le schéma : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBiometrics() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (!await _verifyMainPassword() || !mounted) return;
      if (_profile.biometricEnabled) {
        await _service.disableBiometrics(_org, _user);
        if (mounted) setState(() => _message = 'Biométrie désactivée.');
      } else {
        final enabled = await _service.enableBiometrics(_org, _user);
        if (mounted) setState(() => _message = enabled
          ? 'Biométrie activée sur cet appareil.'
          : 'Aucune biométrie inscrite ou autorisation refusée.');
      }
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = 'Biométrie indisponible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePattern() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (!await _verifyMainPassword() || !mounted) return;
      await _service.disablePattern(_org, _user);
      if (mounted) setState(() => _message = 'Schéma désactivé.');
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compatible = _service.isAndroid && _org.isNotEmpty && _user.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Déverrouillage rapide')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.security_outlined, size: 48),
            const SizedBox(height: 10),
            Text('Protéger GesApp sur ce téléphone',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Le mot de passe principal reste obligatoire pour la première '
              'connexion, la gestion du compte et les opérations sensibles. '
              'Ces options ne s’appliquent qu’à ce téléphone et à votre compte.',
              textAlign: TextAlign.center),
            const SizedBox(height: 18),
            if (!compatible)
              const Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Cette fonction nécessite Android et une session '
                    'Supabase liée à votre établissement.'),
              ))
            else if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_settingPattern) ...[
              Text(_firstPattern == null
                  ? 'Dessinez un schéma avec au moins six points.'
                  : 'Confirmez en répétant le même schéma.',
                textAlign: TextAlign.center),
              const SizedBox(height: 14),
              PatternInput(onComplete: _acceptPattern, enabled: !_busy),
              TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _settingPattern = false;
                  _firstPattern = null;
                }),
                child: const Text('Annuler'),
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.grid_on_rounded),
                title: const Text('Schéma à 9 points'),
                subtitle: Text(_profile.hasPattern ? 'Activé sur ce téléphone'
                    : 'Désactivé'),
                trailing: FilledButton.tonal(
                  onPressed: _busy ? null : _startPattern,
                  child: Text(_profile.hasPattern ? 'Modifier' : 'Activer'),
                ),
              ),
              if (_profile.hasPattern)
                Align(alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _removePattern,
                    child: const Text('Supprimer le schéma'))),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.fingerprint_rounded),
                title: const Text('Empreinte / biométrie Android'),
                subtitle: Text(_profile.biometricEnabled ? 'Activée'
                    : 'Utilise la biométrie enregistrée sur le téléphone'),
                trailing: Switch(
                  value: _profile.biometricEnabled,
                  onChanged: _busy ? null : (_) => _toggleBiometrics(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sur un téléphone partagé, les empreintes Android ne '
                'permettent pas de distinguer les personnes enregistrées. '
                'N’activez pas cette option si plusieurs agents utilisent '
                'le même téléphone.',
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }
}
