import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cloud/supabase_bootstrap.dart';
import '../../core/cloud/supabase_config.dart';
import '../../core/session/operator_session.dart';
import '../../data/repositories/tenant_repository.dart';
import '../../services/tenant_cloud_service.dart';
import '../../services/cloud_snapshot_service.dart';
import '../../app/home_shell.dart';
import '../../app/app_lock_gate.dart';
import 'super_admin_console_screen.dart';

class TenantAccessGate extends StatefulWidget {
  const TenantAccessGate({super.key});

  @override
  State<TenantAccessGate> createState() => _TenantAccessGateState();
}

class _TenantAccessGateState extends State<TenantAccessGate> {
  bool _loading = true;
  TenantMembershipCache? _membership;
  bool _offlineManagerAvailable = false;
  Object? _error;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (SupabaseBootstrap.isInitialized) {
      _authSubscription = TenantCloudService.instance.authChanges.listen((_) => _restore());
    }
    _restore();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseConfig.isConfigured || !SupabaseBootstrap.isInitialized) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final membership = await TenantCloudService.instance.restoreCachedOrRemoteMembership();
      final offlineManagerAvailable = membership == null &&
          TenantCloudService.instance.currentCloudUser == null &&
          await TenantCloudService.instance.canUnlockCachedManagerOffline();
      if (membership != null) {
        await CloudSnapshotService.instance.synchronize();
      }
      if (!mounted) return;
      setState(() {
        _membership = membership;
        _offlineManagerAvailable = offlineManagerAvailable;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _offlineManagerAvailable = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return const _SupabaseConfigurationRequired();
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_membership != null && OperatorSession.isAuthenticated) {
      if (_membership!.isManager && _membership!.mustChangePassword) {
        return _MandatoryPasswordChangeScreen(
          onChanged: (membership) => setState(() => _membership = membership),
        );
      }
      return const HomeShell();
    }
    if (_offlineManagerAvailable && TenantCloudService.instance.currentCloudUser == null) {
      return const AppLockGate();
    }
    if (_error != null && TenantCloudService.instance.currentCloudUser != null) {
      return _TenantLookupErrorScreen(error: _error!, onRetry: _restore);
    }
    if (TenantCloudService.instance.currentCloudUser != null) {
      // Un compte administrateur authentifié par e-mail et confirmé sans tenant
      // est le premier administrateur : il doit créer son établissement.
      return _CreateTenantScreen(onCreated: (membership) {
        setState(() => _membership = membership);
        unawaited(CloudSnapshotService.instance.synchronize());
      });
    }
    return _CloudLoginScreen(
      error: _error,
      onConnected: (membership) {
        setState(() => _membership = membership);
        unawaited(CloudSnapshotService.instance.synchronize());
      },
    );
  }
}

class _TenantLookupErrorScreen extends StatelessWidget {
  const _TenantLookupErrorScreen({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cloud_off_rounded, size: 58, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 14),
                    Text('Impossible de vérifier l’établissement', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('La session e-mail existe, mais GesApp n’a pas pu vérifier l’établissement. Aucune création d’établissement ne sera proposée tant que cette vérification échoue.', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('$error', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: () => onRetry(), icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await TenantCloudService.instance.signOut();
                      },
                      icon: const Icon(Icons.logout_outlined),
                      label: const Text('Déconnecter ce compte'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupabaseConfigurationRequired extends StatelessWidget {
  const _SupabaseConfigurationRequired();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('Connexion Supabase requise', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      const Text(
                        'Cette version de GesApp utilise un établissement multitenant. '
                        'Compilez l’application avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY. '
                        'Aucune clé service_role ne doit être placée dans l’application.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const SelectableText(
                        'flutter run --dart-define=SUPABASE_URL=https://…supabase.co '
                        '--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_…',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudLoginScreen extends StatefulWidget {
  const _CloudLoginScreen({required this.onConnected, this.error});
  final ValueChanged<TenantMembershipCache> onConnected;
  final Object? error;

  @override
  State<_CloudLoginScreen> createState() => _CloudLoginScreenState();
}

class _CloudLoginScreenState extends State<_CloudLoginScreen> {
  final _orgCode = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  final _adminPasswordConfirmation = TextEditingController();
  bool _busy = false;
  bool _managerMode = false;
  bool _adminSignupMode = false;
  bool _obscure = true;
  bool _confirmationSent = false;
  String? _error;

  @override
  void dispose() {
    _orgCode.dispose();
    _username.dispose();
    _password.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    _adminPasswordConfirmation.dispose();
    super.dispose();
  }

  Future<void> _administrator() async {
    final email = _adminEmail.text.trim();
    final password = _adminPassword.text;
    if (email.isEmpty || !email.contains('@') || password.length < 10) {
      setState(() => _error = 'Renseignez un e-mail valide et un mot de passe fort d’au moins 10 caractères.');
      return;
    }
    if (_adminSignupMode && password != _adminPasswordConfirmation.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirmationSent = false;
    });
    try {
      if (_adminSignupMode) {
        final response = await TenantCloudService.instance.signUpAdministratorWithEmail(
          email: email,
          password: password,
        );
        if (response.session == null) {
          if (mounted) setState(() => _confirmationSent = true);
          return;
        }
      } else {
        await TenantCloudService.instance.signInAdministratorWithEmail(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _adminEmail.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Renseignez d’abord votre adresse e-mail.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await TenantCloudService.instance.resendAdministratorConfirmation(email);
      if (mounted) setState(() => _confirmationSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manager() async {
    if (_orgCode.text.trim().isEmpty || _username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Renseignez le code établissement, l’identifiant et le mot de passe.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final membership = await TenantCloudService.instance.signInManager(
        organizationCode: _orgCode.text,
        username: _username.text,
        password: _password.text,
      );
      widget.onConnected(membership);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorText = _error ?? (widget.error == null ? null : '${widget.error}');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.school_rounded, size: 60, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 14),
                      Text('Bienvenue dans GesApp', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(_managerMode ? 'Connexion du gestionnaire' : 'Accès administrateur par e-mail', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, icon: Icon(Icons.admin_panel_settings_outlined), label: Text('Administrateur')),
                          ButtonSegment(value: true, icon: Icon(Icons.badge_outlined), label: Text('Gestionnaire')),
                        ],
                        selected: {_managerMode},
                        onSelectionChanged: _busy ? null : (values) => setState(() { _managerMode = values.first; _error = null; _confirmationSent = false; }),
                      ),
                      const SizedBox(height: 20),
                      if (!_managerMode) ...[
                        const Text('Créez un accès candidat, confirmez votre e-mail puis demandez l’autorisation du Super Admin. L’établissement n’est activé qu’après validation et confirmation du paiement.', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Se connecter')),
                            ButtonSegment(value: true, label: Text('Créer un compte')),
                          ],
                          selected: {_adminSignupMode},
                          onSelectionChanged: _busy ? null : (values) => setState(() { _adminSignupMode = values.first; _error = null; _confirmationSent = false; }),
                        ),
                        const SizedBox(height: 16),
                        TextField(controller: _adminEmail, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Adresse e-mail', prefixIcon: Icon(Icons.email_outlined))),
                        const SizedBox(height: 12),
                        TextField(controller: _adminPassword, obscureText: _obscure, autofillHints: [_adminSignupMode ? AutofillHints.newPassword : AutofillHints.password], decoration: InputDecoration(labelText: 'Mot de passe', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
                        if (_adminSignupMode) ...[
                          const SizedBox(height: 12),
                          TextField(controller: _adminPasswordConfirmation, obscureText: _obscure, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', prefixIcon: Icon(Icons.lock_reset_outlined))),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(onPressed: _busy ? null : _administrator, icon: Icon(_adminSignupMode ? Icons.person_add_alt_1 : Icons.login), label: Text(_busy ? 'Traitement…' : (_adminSignupMode ? 'Créer ma demande d’accès' : 'Se connecter'))),
                        if (_confirmationSent) ...[
                          const SizedBox(height: 14),
                          Card(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('E-mail de confirmation envoyé. Ouvrez votre boîte mail et confirmez votre adresse. Sur Windows, la confirmation se termine dans le navigateur : revenez ensuite dans GesApp et utilisez « Se connecter ». La validation finale et l’activation de l’abonnement appartiennent exclusivement au Super Admin.', textAlign: TextAlign.center),
                            ),
                          ),
                          TextButton(onPressed: _busy ? null : _resendConfirmation, child: const Text('Renvoyer l’e-mail de confirmation')),
                        ],
                      ] else ...[
                        TextField(controller: _orgCode, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code établissement', prefixIcon: Icon(Icons.apartment_outlined))),
                        const SizedBox(height: 12),
                        TextField(controller: _username, decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline))),
                        const SizedBox(height: 12),
                        TextField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'Mot de passe', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), onSubmitted: (_) => _manager()),
                        const SizedBox(height: 18),
                        FilledButton.icon(onPressed: _busy ? null : _manager, icon: const Icon(Icons.login), label: Text(_busy ? 'Connexion…' : 'Se connecter')),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 14),
                        Text(errorText, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SuperAdminConsoleScreen(),
                                  ),
                                ),
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Accès Super Admin'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _MandatoryPasswordChangeScreen extends StatefulWidget {
  const _MandatoryPasswordChangeScreen({required this.onChanged});
  final ValueChanged<TenantMembershipCache> onChanged;

  @override
  State<_MandatoryPasswordChangeScreen> createState() => _MandatoryPasswordChangeScreenState();
}

class _MandatoryPasswordChangeScreenState extends State<_MandatoryPasswordChangeScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Le nouveau mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await TenantCloudService.instance.changeOwnPassword(_password.text);
      final membership = await TenantCloudService.instance.loadMyMembership();
      if (membership == null) throw StateError('Session introuvable après changement du mot de passe.');
      widget.onChanged(membership);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.password_rounded, size: 58),
                    const SizedBox(height: 14),
                    Text('Créer votre mot de passe', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('Le mot de passe transmis par l’administrateur est temporaire. Vous devez le remplacer avant d’utiliser GesApp.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'Nouveau mot de passe', suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
                    const SizedBox(height: 12),
                    TextField(controller: _confirmation, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'), onSubmitted: (_) => _save()),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.check_circle_outline), label: Text(_busy ? 'Enregistrement…' : 'Enregistrer et continuer')),
                    if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center)],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateTenantScreen extends StatefulWidget {
  const _CreateTenantScreen({required this.onCreated});
  final ValueChanged<TenantMembershipCache> onCreated;

  @override
  State<_CreateTenantScreen> createState() => _CreateTenantScreenState();
}

class _CreateTenantScreenState extends State<_CreateTenantScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _displayName = TextEditingController();
  Timer? _timer;
  bool _busy = false;
  bool _checking = false;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    unawaited(_checkStatus());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_checkStatus()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _code.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final membership = await TenantCloudService.instance.loadMyMembership();
      if (membership != null) {
        if (mounted) widget.onCreated(membership);
        return;
      }
      final request = await TenantCloudService.instance.myAdministratorRequest();
      if (mounted) setState(() { _request = request; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _checking = false;
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 3 || _displayName.text.trim().length < 2) {
      setState(() => _error = 'Saisissez le nom de l’école et votre nom complet.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await TenantCloudService.instance.requestAdministratorApproval(
        schoolName: _name.text,
        preferredCode: _code.text,
        displayName: _displayName.text,
      );
      await _checkStatus();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _request?['status']?.toString();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inscription administrateur'),
        actions: [
          TextButton(onPressed: _busy ? null : () => TenantCloudService.instance.signOut(),
              child: const Text('Déconnexion')),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Demande d’accès GesApp',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('La création du compte Administrateur nécessite '
                        'la validation du Super Admin et un abonnement mensuel ou annuel.'),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (status == 'pending') ...[
                      const Icon(Icons.hourglass_top_rounded, size: 48),
                      const SizedBox(height: 10),
                      Text('Demande en attente de validation',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Text('Établissement : ' + (_request?['school_name']?.toString() ?? '')),
                      const Text('Le Super Admin examinera votre demande et '
                          'activera votre abonnement après confirmation du paiement.'),
                    ] else ...[
                      if (status == 'rejected') ...[
                        Text('Votre précédente demande a été refusée.',
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        if ((_request?['review_note']?.toString() ?? '').isNotEmpty)
                          Text(_request!['review_note'].toString()),
                        const SizedBox(height: 12),
                      ],
                      TextField(controller: _displayName,
                          decoration: const InputDecoration(
                              labelText: 'Votre nom complet',
                              prefixIcon: Icon(Icons.person_outline))),
                      const SizedBox(height: 12),
                      TextField(controller: _name,
                          decoration: const InputDecoration(
                              labelText: 'Nom de l’établissement',
                              prefixIcon: Icon(Icons.school_outlined))),
                      const SizedBox(height: 12),
                      TextField(controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                              labelText: 'Code souhaité (facultatif)',
                              prefixIcon: Icon(Icons.tag))),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                          onPressed: _busy ? null : _create,
                          icon: const Icon(Icons.send_rounded),
                          label: Text(_busy ? 'Envoi…' : 'Envoyer au Super Admin')),
                    ],
                    const SizedBox(height: 12),
                    TextButton.icon(
                        onPressed: _checking ? null : _checkStatus,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Actualiser ma demande')),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
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
