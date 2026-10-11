import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/security/manager_password_policy.dart';

void main() {
  test('rejects passwords that violate the Supabase manager policy', () {
    expect(ManagerPasswordPolicy.isStrong('shortA1'), isFalse);
    expect(ManagerPasswordPolicy.isStrong('ALLUPPERCASE123'), isFalse);
    expect(ManagerPasswordPolicy.isStrong('lowercaseonly123'), isFalse);
    expect(ManagerPasswordPolicy.isStrong('NoDigitsHere'), isFalse);
    expect(ManagerPasswordPolicy.isStrong('ValidSecret123'), isTrue);
  });

  test('random reset codes always include upper, lower and digits', () {
    for (var i = 0; i < 200; i++) {
      final code = ManagerPasswordPolicy.generateTemporary();
      expect(code, hasLength(12));
      expect(ManagerPasswordPolicy.isStrong(code), isTrue);
    }
  });

  test('rejects creating weak short reset codes', () {
    expect(
      () => ManagerPasswordPolicy.generateTemporary(length: 9),
      throwsArgumentError,
    );
  });
}
