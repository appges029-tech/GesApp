/// 3x3 Android-style pattern rules and canonicalization.
abstract final class PatternPolicy {
  static int _gcd(int a, int b) => b == 0 ? a.abs() : _gcd(b, a % b);

  static List<int> normalize(List<int> points) {
    final result = <int>[];
    for (final current in points) {
      if (current < 0 || current > 8 || result.contains(current)) continue;
      if (result.isNotEmpty) {
        final last = result.last;
        final dx = (current % 3) - (last % 3);
        final dy = (current ~/ 3) - (last ~/ 3);
        final count = _gcd(dx, dy);
        if (count > 1) {
          for (var step = 1; step < count; step++) {
            final x = last % 3 + dx ~/ count * step;
            final y = last ~/ 3 + dy ~/ count * step;
            final intermediate = y * 3 + x;
            if (!result.contains(intermediate)) result.add(intermediate);
          }
        }
      }
      result.add(current);
    }
    return List.unmodifiable(result);
  }

  static bool isValid(List<int> points) {
    final normalized = normalize(points);
    return normalized.length >= 6 && normalized.length <= 9 &&
        normalized.every((value) => value >= 0 && value < 9);
  }
}
