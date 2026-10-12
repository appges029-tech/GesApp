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

  test('long multi-student and multi-period receipts paginate without overflow', () async {
    final lines = List<ReceiptLine>.generate(
      70,
      (index) => ReceiptLine(
        label: 'Élève ${index + 1} · Scolarité · 2026-${(index % 12 + 1).toString().padLeft(2, '0')}',
        amount: 1000,
      ),
    );
    final longReceipt = ReceiptData(
      identity: const DocumentIdentity(name: 'École test', schoolYear: '2026-2027'),
      receiptNumber: 'REC-2026-000077',
      studentName: 'Famille de test',
      amount: 70000,
      currency: 'FCFA',
      paymentMethod: 'Espèces',
      dateLabel: '12/10/2026 09:00',
      lines: lines,
    );
    for (final format in ReceiptFormat.values) {
      final bytes = await ReceiptService().generate(longReceipt, format: format);
      expect(bytes.length, greaterThan(1000), reason: format.label);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });

  test('refunds and cancelled receipts still generate every PDF format', () async {
    final corrected = ReceiptData(
      identity: const DocumentIdentity(name: 'École test'),
      receiptNumber: 'REC-2026-000078',
      studentName: 'Famille test',
      amount: 30000,
      refundedAmount: 10000,
      isCancelled: true,
      cancelReason: 'Erreur de caisse',
      currency: 'FCFA',
      paymentMethod: 'Espèces',
      dateLabel: '12/10/2026 09:00',
      lines: const [ReceiptLine(label: 'Élève A · Scolarité · Octobre', amount: 30000)],
    );
    expect(corrected.netAmount, 20000);
    for (final format in ReceiptFormat.values) {
      final bytes = await ReceiptService().generate(corrected, format: format);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF', reason: format.label);
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
