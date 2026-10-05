import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/layout/responsive_layout.dart';
import 'package:gesapp/core/providers/repository_providers.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/models/hr.dart';
import 'package:gesapp/data/repositories/hr_repository.dart';
import 'package:gesapp/features/hr/hr_screen.dart';
import 'package:gesapp/features/settings/cloud_sync_screen.dart';
import 'package:gesapp/services/cloud_snapshot_service.dart';
import 'package:gesapp/services/json_schema.dart';

class _FailingHrRepository extends HrRepository {
  _FailingHrRepository() : super(AppDatabase.instance);

  @override
  Future<HrSummary> summary() async => throw StateError('Erreur RH simulée');
}

void main() {
  test('un export complet du même schéma avec manifeste exact est accepté', () {
    final tables = <String, dynamic>{
      for (final table in gesAppPortableTables) table: const <Object?>[],
    };
    expect(
      () => validateCompletePortableExport(
        sourceSchemaVersion: 29,
        currentSchemaVersion: 29,
        currentPortableTables: gesAppPortableTables,
        sourceTables: tables,
        tableManifest: gesAppPortableTables,
      ),
      returnsNormally,
    );
  });

  test('une table portable absente fait refuser la restauration complète', () {
    final tables = <String, dynamic>{
      for (final table in gesAppPortableTables.skip(1)) table: const <Object?>[],
    };
    expect(
      () => validateCompletePortableExport(
        sourceSchemaVersion: 29,
        currentSchemaVersion: 29,
        currentPortableTables: gesAppPortableTables,
        sourceTables: tables,
        tableManifest: tables.keys.toList(),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('un export JSON provenant d’un ancien schéma est refusé sans migration sûre', () {
    final tables = <String, dynamic>{
      for (final table in gesAppPortableTables) table: const <Object?>[],
    };
    expect(
      () => validateCompletePortableExport(
        sourceSchemaVersion: 28,
        currentSchemaVersion: 29,
        currentPortableTables: gesAppPortableTables,
        sourceTables: tables,
        tableManifest: gesAppPortableTables,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  testWidgets('ResponsiveDataTable utilise une scrollbar horizontale sans exception', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 400,
            child: ResponsiveDataTable(
              headers: ['A', 'B', 'C'],
              rows: [
                ['1', '2', '3'],
                ['4', '5', '6'],
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une erreur RH affiche une erreur et un bouton Réessayer', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hrRepositoryProvider.overrideWithValue(_FailingHrRepository()),
        ],
        child: const MaterialApp(home: HrScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger les données RH.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('le bouton de synchronisation est désactivé en état unsupported', (tester) async {
    final service = CloudSnapshotService.instance;
    final previous = service.status.value;
    addTearDown(() => service.status.value = previous);
    service.status.value = const CloudSyncStatus(
      state: 'unsupported',
      message: 'Synchronisation de snapshot non disponible sur cette plateforme.',
    );

    await tester.pumpWidget(const MaterialApp(home: CloudSyncScreen()));
    await tester.pumpAndSettle();

    final buttonFinder = find.byWidgetPredicate((widget) => widget is FilledButton);
    expect(buttonFinder, findsOneWidget);
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(find.text('Snapshot cloud indisponible'), findsOneWidget);
    expect(find.textContaining('sauvegardes JSON'), findsOneWidget);
  });

  testWidgets('un conflit propose les deux choix explicites au gestionnaire', (tester) async {
    final service = CloudSnapshotService.instance;
    final previous = service.status.value;
    addTearDown(() => service.status.value = previous);
    addTearDown(OperatorSession.clear);

    OperatorSession.authenticate(
      userId: 'manager-test',
      displayName: 'Gestionnaire test',
      role: 'manager',
      organizationId: 'org-test',
      organizationCode: 'TEST',
      organizationName: 'École test',
    );
    service.status.value = const CloudSyncStatus(
      state: 'conflict',
      message: 'Conflit simulé',
    );

    await tester.pumpWidget(const MaterialApp(home: CloudSyncScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Conflit de synchronisation'), findsOneWidget);
    expect(find.text('Utiliser la version cloud'), findsOneWidget);
    expect(find.text('Conserver cet appareil'), findsOneWidget);
  });
}
