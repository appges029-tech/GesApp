import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/security/pattern_policy.dart';

void main() {
  test('schéma de six points au minimum', () {
    expect(PatternPolicy.isValid([0, 1, 2, 3, 4]), false);
    expect(PatternPolicy.isValid([0, 1, 2, 3, 4, 5]), true);
    expect(PatternPolicy.isValid([0, 1, 2, 3, 4, 5, 6, 7, 8]), true);
  });

  test('les points intermédiaires sont ajoutés automatiquement', () {
    expect(PatternPolicy.normalize([0, 2]), [0, 1, 2]);
    expect(PatternPolicy.normalize([0, 8]), [0, 4, 8]);
    expect(PatternPolicy.normalize([0, 6]), [0, 3, 6]);
    expect(PatternPolicy.normalize([2, 6]), [2, 4, 6]);
  });

  test('aucun point ne peut être compté deux fois', () {
    expect(PatternPolicy.normalize([0, 2, 1, 0, 5, 8, 7]), [0, 1, 2, 5, 8, 7]);
    expect(PatternPolicy.normalize([0, 0, 0]), [0]);
  });

  test('un index hors de la grille est ignoré', () {
    expect(PatternPolicy.normalize([-1, 0, 12, 1, 2]), [0, 1, 2]);
  });
}
