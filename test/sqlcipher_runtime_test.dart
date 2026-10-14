import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('native sqlite runtime exposes SQLCipher', () {
    final db = sqlite.sqlite3.openInMemory();
    try {
      final rows = db.select('PRAGMA cipher_version;');
      expect(rows, isNotEmpty, reason: 'SQLCipher runtime is required for production builds.');
      expect(rows.first.values.first.toString().trim(), isNotEmpty);

      const key = '8c4b4418595b461dafb2860d3cd29f8b6dd539560532a8f84667a53fd7631c28';
      db.execute('PRAGMA key = "x\'$key\'";');
      db.execute('CREATE TABLE secure_probe(id INTEGER PRIMARY KEY, value TEXT NOT NULL);');
      db.execute("INSERT INTO secure_probe(value) VALUES ('ok');");
      expect(db.select('SELECT value FROM secure_probe').single['value'], 'ok');
    } finally {
      db.close();
    }
  });
}
