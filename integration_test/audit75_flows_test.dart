import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gesapp/app/app_lock_gate.dart';
import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/platform/platform_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/security_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    configurePlatformDatabase();
  });

  setUp(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await platformDatabaseFactory.deleteDatabase(path);
    await AppDatabase.instance.initialize();
    final security = SecurityRepository(AppDatabase.instance);
    await security.createUser(
      username: 'integration75',
      displayName: 'Gestionnaire Intégration',
      role: 'manager',
      pin: 'MotDePasse-75!',
    );
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await platformDatabaseFactory.deleteDatabase(path);
  });

  testWidgets('inactive conserve la session, paused verrouille après synchronisation', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AppLockGate())));
    await tester.pumpAndSettle();

    expect(find.text('Connexion GesApp'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'MotDePasse-75!');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(OperatorSession.isManager, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(OperatorSession.isManager, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(OperatorSession.isAuthenticated, isFalse);
    expect(find.text('Connexion GesApp'), findsOneWidget);
  });
}
