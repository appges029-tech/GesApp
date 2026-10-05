import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/cloud/supabase_config.dart';

void main() {
  test('compile-time Supabase configuration is available', () {
    const expected = bool.fromEnvironment('SUPABASE_CONFIG_EXPECTED');

    expect(SupabaseConfig.isConfigured, expected);
    if (expected) {
      expect(SupabaseConfig.url.trim(), isNotEmpty);
      expect(SupabaseConfig.publishableKey.trim(), isNotEmpty);
    }
  });
}
