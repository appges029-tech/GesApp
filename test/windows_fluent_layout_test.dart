import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/windows/windows_page_scaffold.dart';
import 'package:gesapp/core/windows/windows_panels.dart';
import 'package:gesapp/core/windows/windows_ui.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows page scaffold uses desktop header at wide width', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WindowsPageScaffold(
          title: 'Élèves',
          subtitle: 'Gestion des élèves',
          body: Center(child: Text('CONTENU')),
        ),
      ),
    );

    expect(find.text('Élèves'), findsOneWidget);
    expect(find.text('Gestion des élèves'), findsOneWidget);
    expect(find.text('CONTENU'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('Windows module grid keeps all modules visible', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowsModuleGrid(
            children: [
              WindowsModuleCard(icon: Icons.people, title: 'Élèves', subtitle: 'Gestion', onTap: () {}),
              WindowsModuleCard(icon: Icons.payments, title: 'Finances', subtitle: 'Paiements', onTap: () {}),
              WindowsModuleCard(icon: Icons.settings, title: 'Réglages', subtitle: 'Configuration', onTap: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Élèves'), findsOneWidget);
    expect(find.text('Finances'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
  });

  test('Windows desktop threshold remains 900 px', () {
    expect(WindowsUi.desktopBreakpoint, 900);
    expect(WindowsUi.expandedPaneBreakpoint, 1200);
  });
}
