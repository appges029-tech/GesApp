import 'package:flutter/material.dart';

import '../../data/repositories/security_repository.dart';

Future<AppUser?> requestSensitiveAuthorization({
  required BuildContext context,
  required SecurityRepository repository,
  required String action,
  String? entityId,
}) async {
  final users = await repository.users(activeOnly: true);
  if (!context.mounted) return null;
  if (users.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun gestionnaire actif pour autoriser cette opération.')));
    return null;
  }
  final username = TextEditingController();
  final pin = TextEditingController();
  String? error;
  final result = await showDialog<AppUser>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Validation renforcée'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(users.length > 1
              ? 'Cette opération sensible doit être confirmée avec le compte et le PIN d’un autre gestionnaire actif.'
              : 'Cette opération sensible doit être confirmée à nouveau avec le compte gestionnaire.'),
          const SizedBox(height: 12),
          TextField(controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Identifiant gestionnaire')),
          const SizedBox(height: 10),
          TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN')),
          if (error != null) ...[const SizedBox(height: 8), Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error))],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final authorized = await repository.authorizeSensitiveAction(username: username.text, pin: pin.text, action: action, entityId: entityId);
              if (!dialogContext.mounted) return;
              if (authorized == null) {
                setDialogState(() => error = users.length > 1 ? 'Identifiants invalides ou même gestionnaire que la session actuelle.' : 'Identifiants invalides.');
                return;
              }
              Navigator.pop(dialogContext, authorized);
            },
            child: const Text('Autoriser'),
          ),
        ],
      ),
    ),
  );
  username.dispose();
  pin.dispose();
  return result;
}
