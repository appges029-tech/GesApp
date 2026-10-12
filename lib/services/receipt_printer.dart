import 'package:intl/intl.dart';

import '../core/platform/pdf_output_service.dart';
import '../data/repositories/settings_repository.dart';
import '../data/models/finance.dart';
import 'document_identity.dart';
import 'document_number_service.dart';
import 'pos_printer_service.dart';
import 'receipt_service.dart';

class ReceiptPrinter {
  ReceiptPrinter(this._service);
  final ReceiptService _service;

  /// Imprime les données comptables persistées et non l'état d'un formulaire.
  Future<void> printVerifiedReceipt({
    required ReceiptVerificationResult receipt,
    EstablishmentData? establishment,
    ReceiptFormat format = ReceiptFormat.a5,
    bool directToPrinter = false,
    String? printerUrl,
    bool showLogo = true,
    bool includeDetails = true,
    int copies = 1,
  }) => printReceipt(
    establishment: establishment,
    receiptNumber: receipt.receiptNumber,
    beneficiaryName: receipt.beneficiaryName,
    amount: receipt.amount,
    paymentMethod: receipt.method,
    paidAt: receipt.paidAt,
    paymentReference: receipt.transactionReference ?? '',
    lines: receipt.lines.map((line) =>
        ReceiptLine(label: line.label, amount: line.amount)).toList(),
    refundedAmount: receipt.refundedAmount,
    isCancelled: receipt.isCancelled,
    cancelReason: receipt.cancelReason,
    format: format,
    directToPrinter: directToPrinter,
    printerUrl: printerUrl,
    showLogo: showLogo,
    includeDetails: includeDetails,
    copies: copies,
  );

  Future<void> printReceipt({
    required String receiptNumber,
    required String beneficiaryName,
    required int amount,
    required String paymentMethod,
    required DateTime paidAt,
    EstablishmentData? establishment,
    String paymentReference = '',
    List<ReceiptLine> lines = const [],
    int refundedAmount = 0,
    bool isCancelled = false,
    String? cancelReason,
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
      refundedAmount: refundedAmount,
      isCancelled: isCancelled,
      cancelReason: cancelReason,
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

    final saved = await outputPdf(bytes, fileName: format == ReceiptFormat.a5 ? 'Recu-$receiptNumber.pdf' : 'Recu-$receiptNumber-${format.storageKey}.pdf');
    if (saved == null) throw StateError('L’enregistrement ou l’impression du reçu a été annulé.');
  }
}
