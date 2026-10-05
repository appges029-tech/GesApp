import 'package:flutter_test/flutter_test.dart';

import 'package:gesapp/services/document_identity.dart';
import 'package:gesapp/services/receipt_service.dart';

void main() {
  const data = ReceiptData(
    identity: DocumentIdentity(name: 'École Test', schoolYear: '2026-2027'),
    receiptNumber: 'REC-2026-000001',
    studentName: 'Jean Test',
    amount: 35000,
    currency: 'FCFA',
    paymentMethod: 'Espèces',
    dateLabel: '20/09/2026 12:00',
    lines: [ReceiptLine(label: 'Scolarité', amount: 25000), ReceiptLine(label: 'Transport', amount: 10000)],
  );

  test('receipt formats keep the expected POS widths', () {
    expect(ReceiptFormat.pos80.pageWidthMm, 80);
    expect(ReceiptFormat.pos58.pageWidthMm, 58);
    expect(ReceiptFormat.a5.isPos, isFalse);
    expect(ReceiptFormat.pos80.isPos, isTrue);
  });

  test('receipt format storage keys round-trip', () {
    for (final format in ReceiptFormat.values) {
      expect(ReceiptFormatX.fromStorageKey(format.storageKey), format);
    }
  });

  test('generates A5 and POS receipt PDFs', () async {
    final service = ReceiptService();
    for (final format in ReceiptFormat.values) {
      final bytes = await service.generate(data, format: format);
      expect(bytes.length, greaterThan(500), reason: format.label);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });
}
