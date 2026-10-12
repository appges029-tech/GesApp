import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/data/repositories/report_repository.dart';

void main() {
  Map<String, Object?> movement(
    String date,
    String reference,
    int amount,
  ) => {
    'date': date,
    'reference': reference,
    'type': amount >= 0 ? 'Recette' : 'Dépense',
    'description': 'Opération test',
    'amount': amount,
  };

  test('le report d ouverture précède les mouvements et conserve le solde', () {
    final source = [
      movement('2026-10-15T09:00:00', 'DEP-1', -20),
      movement('2026-10-14T09:00:00', 'REC-1', 50),
    ];
    final entries = ReportRepository.ledgerEntriesFromJournal(
      source,
      openingBalance: 100,
      openingDate: DateTime(2026, 10, 14),
    );

    expect(entries, hasLength(3));
    // Le journal est affiché de la date la plus récente à la plus ancienne.
    expect(entries[0].reference, 'DEP-1');
    expect(entries[0].debit, 20);
    expect(entries[0].balance, 130);
    expect(entries[1].reference, 'REC-1');
    expect(entries[1].credit, 50);
    expect(entries[1].balance, 150);
    expect(entries[2].reference, 'REPORT');
    expect(entries[2].balance, 100);
    expect(entries[2].debit, 0);
    expect(entries[2].credit, 0);
    // Pas de tri destructif des données sources.
    expect(source[0]['reference'], 'DEP-1');
  });

  test('une période vide affiche le report sans inventer une recette', () {
    final entries = ReportRepository.ledgerEntriesFromJournal(
      [],
      openingBalance: 42500,
      openingDate: DateTime(2026, 10, 1),
    );
    expect(entries, hasLength(1));
    expect(entries.single.balance, 42500);
    expect(entries.single.debit + entries.single.credit, 0);
  });

  test('hors filtre de dates le journal ne crée pas de report artificiel', () {
    final entries = ReportRepository.ledgerEntriesFromJournal([
      movement('2026-10-01T12:00:00', 'REC-2', 3000),
    ]);
    expect(entries, hasLength(1));
    expect(entries.single.reference, 'REC-2');
    expect(entries.single.balance, 3000);
  });
}
