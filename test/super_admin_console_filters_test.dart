import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/features/security/super_admin_console_filters.dart';

void main() {
  final schools = <Map<String, dynamic>>[
    {
      'name': 'École Gustave',
      'code': 'GS-001',
      'subscription_effective_status': 'active',
      'admin': {'display_name': 'Directeur Marcel'},
      'managers': [
        {'display_name': 'Gestionnaire Louise'}
      ],
    },
    {
      'name': 'Collège Makaya',
      'code': 'COL-002',
      'subscription_effective_status': 'expired',
      'admin': {'display_name': 'Direction Clémence'},
      'managers': <Map<String, dynamic>>[],
    },
  ];

  test('filtre des établissements par nom et code', () {
    expect(SuperAdminConsoleFilters.schools(schools, search: 'gustave'), hasLength(1));
    expect(SuperAdminConsoleFilters.schools(schools, search: 'COL-002'), hasLength(1));
  });

  test('recherche un administrateur ou un gestionnaire', () {
    expect(SuperAdminConsoleFilters.schools(schools, search: 'louise').single['code'], 'GS-001');
    expect(SuperAdminConsoleFilters.schools(schools, search: 'clémence').single['code'], 'COL-002');
  });

  test('sépare les abonnements expirés des écoles actives', () {
    final expired = SuperAdminConsoleFilters.schools(schools, status: 'expired');
    expect(expired.single['name'], 'Collège Makaya');
    expect(SuperAdminConsoleFilters.schools(schools,
      search: 'marcel', status: 'expired'), isEmpty);
  });

  test('filtre les incidents de synchronisation sans perdre leur école', () {
    final events = <Map<String, dynamic>>[
      {'organization_name': 'Gustave', 'event_type': 'sync_error',
       'module': 'synchronisation', 'message': 'Conflit cloud'},
      {'organization_name': 'Makaya', 'event_type': 'app_open',
       'module': 'application', 'message': 'GesApp ouvert'},
    ];
    final result = SuperAdminConsoleFilters.activities(events, search: 'conflit');
    expect(result, hasLength(1));
    expect(result.single['organization_name'], 'Gustave');
  });
}
