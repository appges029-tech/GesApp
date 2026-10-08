import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/layout/responsive_layout.dart';
import 'package:gesapp/core/theme/app_theme.dart';

void main() {
  for (final width in <double>[320, 360, 390, 412]) {
    testWidgets('long dropdown stays inside dialog at ${width.toInt()} px',
        (tester) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const _DropdownDialogHarness(),
        ),
      );

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Avance sur salaire'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Employé avec un nom volontairement très long pour tester le petit écran',
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('Material overlay surfaces remain readable with Liquid Glass', () {
    final light = AppTheme.light;
    final dark = AppTheme.dark;

    expect(light.canvasColor.a, 1);
    expect(dark.canvasColor.a, 1);
    expect(light.popupMenuTheme.color?.a, 1);
    expect(dark.popupMenuTheme.color?.a, 1);
  });
}

class _DropdownDialogHarness extends StatelessWidget {
  const _DropdownDialogHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Avance sur salaire'),
              content: ResponsiveDialogContent(
                maxWidth: 520,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: 'employee',
                  decoration: const InputDecoration(labelText: 'Employé'),
                  items: const [
                    DropdownMenuItem(
                      value: 'employee',
                      child: Text(
                        'Employé avec un nom volontairement très long pour tester le petit écran',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
          child: const Text('Ouvrir'),
        ),
      ),
    );
  }
}
