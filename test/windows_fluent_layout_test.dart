import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/windows/windows_page_scaffold.dart';
import 'package:gesapp/core/windows/windows_panels.dart';
import 'package:gesapp/core/windows/windows_ui.dart';
import 'package:gesapp/core/theme/app_theme.dart';
import 'package:gesapp/features/finance/finance_screen.dart';

void main() {
  testWidgets('Windows page scaffold uses desktop header at wide width', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows module grid keeps all modules visible', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows desktop threshold remains 900 px', () {
    expect(WindowsUi.desktopBreakpoint, 900);
    expect(WindowsUi.expandedPaneBreakpoint, 1200);
  });

  testWidgets('Windows panels use solid surfaces instead of glass cards', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.windowsLight,
      home: const Scaffold(body: WindowsPanel(child: Text('Panneau lisible'))),
    ));
    expect(find.text('Panneau lisible'), findsOneWidget);
    expect(find.byType(Material), findsWidgets);
    expect(find.byType(WindowsPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows finances prioritize everyday operations on a 1366px display', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.windowsLight,
      home: const FinanceScreen(),
    ));
    expect(find.text('Opérations quotidiennes'), findsOneWidget);
    expect(find.text('Encaisser un paiement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows desktop header works at 125 percent screen scaling', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.windowsLight,
      home: const WindowsPageScaffold(
        title: 'Échéances',
        subtitle: 'Facturation annuelle des élèves',
        body: Center(child: Text('Opérations de paiement')),
      ),
    ));
    expect(find.text('Échéances'), findsOneWidget);
    expect(find.text('Opérations de paiement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
