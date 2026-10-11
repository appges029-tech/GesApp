
import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/session/tenant_data_isolation.dart';

void main() {
  const gustave = 'b38efacc-4fa1-4ffe-8989-e936a90fc197';
  const mageste = '98286bee-529c-4f00-8272-3b5b178105b3';

  Map<String, dynamic> snapshot({
    String school = gustave,
    String? boundSchool,
  }) => {
    'tables': <String, dynamic>{
      'establishments': [
        {'id': school, 'name': 'École test'},
      ],
      'app_settings': [
        if (boundSchool != null)
          {
            'key': 'gesapp.cloud.bound_organization_id.v1',
            'value': boundSchool,
          },
      ],
    },
  };

  test('l établissement propriétaire peut relire sa base', () {
    expect(
      () => TenantDataIsolation.requireSameTenant(gustave, gustave),
      returnsNormally,
    );
  });

  test('un établissement différent ne peut jamais hériter de la base', () {
    expect(
      () => TenantDataIsolation.requireSameTenant(mageste, gustave),
      throwsStateError,
    );
  });

  test('une base non encore attribuée peut être vérifiée au premier accès', () {
    expect(
      () => TenantDataIsolation.requireSameTenant(gustave, null),
      returnsNormally,
    );
  });

  test('le bon snapshot chiffré est accepté après déchiffrement', () {
    expect(
      () => TenantDataIsolation.validateSnapshot(
        snapshot(school: gustave, boundSchool: gustave),
        gustave,
      ),
      returnsNormally,
    );
  });

  test('snapshot de Gustave sous identité Mageste est rejeté', () {
    expect(
      () => TenantDataIsolation.validateSnapshot(
        snapshot(school: gustave), mageste,
      ),
      throwsStateError,
    );
  });

  test('un snapshot avec l ancienne liaison Mageste est rejeté pour Gustave', () {
    expect(
      () => TenantDataIsolation.validateSnapshot(
        snapshot(school: gustave, boundSchool: mageste), gustave,
      ),
      throwsStateError,
    );
  });

  test('un snapshot sans identité scolaire est refusé', () {
    expect(
      () => TenantDataIsolation.validateSnapshot(
        {'tables': {'establishments': [], 'app_settings': []}},
        gustave,
      ),
      throwsStateError,
    );
  });

  test('un snapshot déclarant plusieurs écoles est refusé', () {
    expect(
      () => TenantDataIsolation.validateSnapshot(
        {
          'tables': {
            'establishments': [
              {'id': gustave}, {'id': mageste},
            ],
            'app_settings': [],
          },
        },
        gustave,
      ),
      throwsStateError,
    );
  });
}
