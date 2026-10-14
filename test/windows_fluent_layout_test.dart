import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/windows/windows_page_scaffold.dart';
import 'package:gesapp/core/windows/windows_panels.dart';
import 'package:gesapp/core/windows/windows_ui.dart';
import 'package:gesapp/core/layout/responsive_layout.dart';
import 'package:gesapp/core/theme/app_theme.dart';
import 'package:gesapp/features/finance/finance_screen.dart';
import 'package:gesapp/core/session/operator_session.dart';

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
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows finances prioritize everyday operations on a 1366px display', (tester) async {
    // L'encaissement est réservé à un gestionnaire authentifié.
    OperatorSession.authenticate(
      userId: 'windows-finance-manager',
      displayName: 'Gestionnaire de test',
      role: 'manager',
    );
    addTearDown(OperatorSession.clear);
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
    debugDefaultTargetPlatformOverride = null;
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
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('Monthly calendar dialogs do not overflow scaled Windows viewports', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sizes = <(Size, double)>[
      (const Size(1366, 768), 1.25),
      (const Size(1366, 768), 1.5),
      (const Size(1280, 720), 1.25),
      (const Size(1920, 1080), 1),
      (const Size(480, 620), 1),
    ];
    for (final setup in sizes) {
      tester.view.physicalSize = setup.$1;
      tester.view.devicePixelRatio = setup.$2;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.windowsLight,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Dates limites mensuelles'),
                  content: ResponsiveDialogBody(
                    maxWidth: 460,
                    maxHeight: 440,
                    child: Column(children: [
                      const Text('Choisissez une date pour chaque mois payable'),
                      Expanded(child: ListView(children: [
                        for (var i = 0; i < 12; i++)
                          ListTile(title: Text('Mois $i'), trailing: const Icon(Icons.event)),
                      ])),
                    ]),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(context),
                      child: const Text('Enregistrer')),
                  ],
                ),
              ),
              child: const Text('Ouvrir'),
            )),
          ),
        ),
      ));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Dates limites mensuelles'), findsOneWidget);
      expect(tester.takeException(), isNull,
        reason: 'Dialog at ${setup.$1} / scale ${setup.$2}');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Narrow desktop tables scroll without shrinking payment columns', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.25;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.windowsLight,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 650, height: 340,
            child: WindowsPanel(
              padding: EdgeInsets.zero,
              child: WindowsAdaptiveTable(
                minWidth: 1080,
                child: Column(children: [
                  const SizedBox(height: 40, child: Text('Référence de paiement')),
                  Expanded(child: ListView(children: const [
                    ListTile(title: Text('Paiement contrôle')),
                    ListTile(title: Text('Paiement long intitulé')),
                  ])),
                ]),
              ),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Référence de paiement'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

}
