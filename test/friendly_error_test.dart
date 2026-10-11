import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/utils/friendly_error.dart';

void main() {
  test('database busy has a useful retry hint', () {
    expect(FriendlyError.message(Exception('SQLITE_BUSY: database is locked')),
      contains('Attendez'));
  });
  test('no network explains how to recover', () {
    expect(FriendlyError.message(Exception('SocketException: failed host lookup')),
      contains('connexion'));
  });
  test('existing business error stays readable', () {
    expect(FriendlyError.message(StateError('Cette rubrique existe déjà.')),
      'Cette rubrique existe déjà.');
  });
  test('raw unknown stack information is not exposed to users', () {
    expect(FriendlyError.message(Exception('internal #0 stack trace')),
      isNot(contains('stack trace')));
  });
}
