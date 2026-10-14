import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';

class FirstRunSetupScreen extends ConsumerStatefulWidget {
  const FirstRunSetupScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  ConsumerState<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(text: 'gestionnaire');
  final _displayName = TextEditingController();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  bool _obscurePin = true;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(securityRepositoryProvider);
      final userId = await repository.createUser(
        username: _username.text,
        displayName: _displayName.text,
        role: 'manager',
        pin: _pin.text,
      );
      final result = await repository.authenticate(userId, _pin.text);
      if (!result.success) {
        throw StateError(result.message ?? 'Connexion initiale impossible.');
      }
      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Configuration impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sécuriser GesApp',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Créez le premier compte gestionnaire. Cette étape est obligatoire avant d’accéder aux données de l’école.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Identifiant de connexion',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) => (value ?? '').trim().length < 3
                          ? 'Au moins 3 caractères sont requis.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _displayName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nom du gestionnaire',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Le nom est obligatoire.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pin,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.next,
                      maxLength: 64,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe (8 à 64 caractères)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscurePin = !_obscurePin),
                          icon: Icon(_obscurePin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (value) {
                        final secret = value ?? '';
                        return secret.length >= 8 && secret.length <= 64
                            ? null
                            : 'Saisissez entre 8 et 64 caractères.';
                      },
                    ),
                    TextFormField(
                      controller: _confirmation,
                      obscureText: true,
                      keyboardType: TextInputType.visiblePassword,
                      maxLength: 64,
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le mot de passe',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                      validator: (value) => value == _pin.text
                          ? null
                          : 'Les mots de passe ne correspondent pas.',
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_saving
                          ? 'Création du compte…'
                          : 'Créer et ouvrir GesApp'),
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
}
