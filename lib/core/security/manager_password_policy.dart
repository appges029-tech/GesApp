import 'dart:math';

/// Unified requirements for administrator-issued and self-chosen passwords.
abstract final class ManagerPasswordPolicy {
  static bool isStrong(String password) =>
      password.length >= 10 &&
      RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[0-9]').hasMatch(password);

  /// The generated code always satisfies the server-side password policy.
  static String generateTemporary({int length = 12}) {
    if (length < 10) throw ArgumentError.value(length, 'length');
    const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lowercase = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#';
    const alphabet = uppercase + lowercase + digits + symbols;
    final random = Random.secure();
    final characters = <String>[
      uppercase[random.nextInt(uppercase.length)],
      lowercase[random.nextInt(lowercase.length)],
      digits[random.nextInt(digits.length)],
      ...List.generate(
        length - 3,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ),
    ]..shuffle(random);
    return characters.join();
  }
}
