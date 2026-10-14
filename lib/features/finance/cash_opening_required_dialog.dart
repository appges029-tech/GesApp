import 'package:flutter/material.dart';

/// Avertit le caissier avant tout encaissement dans une caisse physique fermée.
/// True signifie seulement qu'il souhaite accéder à l'écran d'ouverture.
Future<bool> showCashOpeningRequiredDialog(
  BuildContext context, {
  required String accountName,
}) async {
  final openCash = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline),
          SizedBox(width: 10),
          Expanded(child: Text('Caisse fermée')),
        ],
      ),
      content: Text(
        'La caisse « $accountName » est fermée.\n\n'
        'Pour enregistrer un paiement en espèces, ouvrez d’abord '
        'cette caisse dans « Caisse & trésorerie ».\n\n'
        'Aucun paiement n’a été enregistré.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Ouvrir la caisse'),
        ),
      ],
    ),
  );
  return openCash == true;
}
