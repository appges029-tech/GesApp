import 'package:flutter_test/flutter_test.dart';

import 'package:gesapp/services/receipt_printing_preferences.dart';
import 'package:gesapp/services/receipt_service.dart';

void main() {
  test('receipt printing preferences serialize without losing POS settings', () {
    const original = ReceiptPrintingPreferences(
      format: ReceiptFormat.pos80,
      printerUrl: 'printer://cashier',
      printerName: 'POS Caisse',
      autoPrint: true,
      showLogo: false,
      includeDetails: true,
      copies: 2,
    );
    final restored = ReceiptPrintingPreferences.fromMap(original.toMap());
    expect(restored.format, ReceiptFormat.pos80);
    expect(restored.printerUrl, 'printer://cashier');
    expect(restored.printerName, 'POS Caisse');
    expect(restored.autoPrint, isTrue);
    expect(restored.showLogo, isFalse);
    expect(restored.includeDetails, isTrue);
    expect(restored.copies, 2);
  });

  test('invalid copy count is clamped to supported range', () {
    final restored = ReceiptPrintingPreferences.fromMap({'copies': 99});
    expect(restored.copies, 2);
  });
}
