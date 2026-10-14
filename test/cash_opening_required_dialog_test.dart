import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/features/finance/cash_opening_required_dialog.dart';

void main() {
  Widget app(ValueChanged<bool> onChoice) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            onChoice(await showCashOpeningRequiredDialog(
              context,
              accountName: 'Caisse principale',
            ));
          },
          child: const Text('Valider le paiement'),
        ),
      ),
    ),
  );

  testWidgets('closed cash warns before posting and offers opening', (tester) async {
    bool? choice;
    await tester.pumpWidget(app((value) => choice = value));
    await tester.tap(find.text('Valider le paiement'));
    await tester.pumpAndSettle();

    expect(find.text('Caisse fermée'), findsOneWidget);
    expect(find.textContaining('Caisse principale'), findsOneWidget);
    expect(find.textContaining('Aucun paiement n’a été enregistré.'), findsOneWidget);

    await tester.tap(find.text('Ouvrir la caisse'));
    await tester.pumpAndSettle();
    expect(choice, isTrue);
  });

  testWidgets('cashier can cancel the warning without posting', (tester) async {
    bool? choice;
    await tester.pumpWidget(app((value) => choice = value));
    await tester.tap(find.text('Valider le paiement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(choice, isFalse);
    expect(find.text('Caisse fermée'), findsNothing);
  });
}
