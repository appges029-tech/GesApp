import 'package:intl/intl.dart';

import '../core/platform/pdf_output_service.dart';
import '../data/repositories/settings_repository.dart';
import 'document_identity.dart';
import 'document_number_service.dart';
import 'pos_printer_service.dart';
import 'receipt_service.dart';

class ReceiptPrinter {
  ReceiptPrinter(this._service);
  final ReceiptService _service;

  Future<void> printReceipt({
    required String receiptNumber,
    required String beneficiaryName,
    required int amount,
    required String paymentMethod,
    required DateTime paidAt,
    EstablishmentData? establishment,
    String paymentReference = '',
    List<ReceiptLine> lines = const [],
    ReceiptFormat format = ReceiptFormat.a5,
    bool directToPrinter = false,
    String? printerUrl,
    bool showLogo = true,
    bool includeDetails = true,
    int copies = 1,
  }) async {
    final identity = await DocumentIdentity.fromEstablishment(establishment);
    final data = ReceiptData(
      identity: identity,
      receiptNumber: receiptNumber,
      studentName: beneficiaryName,
      amount: amount,
      currency: 'FCFA',
      paymentMethod: paymentMethod,
      dateLabel: DateFormat('dd/MM/yyyy HH:mm').format(paidAt),
      paymentReference: paymentReference,
      lines: lines,
    );
    final bytes = await _service.generate(
      data,
      format: format,
      showLogo: showLogo,
      includeDetails: includeDetails,
    );

    // A5 keeps the historical fingerprint key. POS variants use their own
    // fingerprint key so printing the same receipt in another format cannot
    // overwrite the A5 document fingerprint.
    final fingerprintReference = format == ReceiptFormat.a5 ? receiptNumber : '$receiptNumber:${format.storageKey}';
    await DocumentNumberService().recordFingerprint(reference: fingerprintReference, bytes: bytes);

    if (directToPrinter && format.isPos) {
      final detailLines = includeDetails ? lines.length : 0;
      final printed = await PosPrinterService().directPrint(
        bytes: bytes,
        jobName: 'Recu-$receiptNumber-${format.storageKey}',
        pageFormat: format.pageFormatFor(detailLines: detailLines),
        printerUrl: printerUrl,
        copies: copies,
      );
      if (!printed) throw StateError("L'imprimante n'a pas confirmé l'impression du reçu.");
      return;
    }

    await outputPdf(bytes, fileName: format == ReceiptFormat.a5 ? 'Recu-$receiptNumber.pdf' : 'Recu-$receiptNumber-${format.storageKey}.pdf');
  }
}
