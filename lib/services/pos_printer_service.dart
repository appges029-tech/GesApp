import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class PosPrinterDescriptor {
  const PosPrinterDescriptor({
    required this.url,
    required this.name,
    required this.isDefault,
    required this.isAvailable,
  });

  final String url;
  final String name;
  final bool isDefault;
  final bool isAvailable;
}

class PosPrinterService {
  Future<List<PosPrinterDescriptor>> listPrinters() async {
    final info = await Printing.info();
    if (!info.canListPrinters) return const [];
    final printers = await Printing.listPrinters();
    return printers
        .map((printer) => PosPrinterDescriptor(
              url: printer.url,
              name: printer.name,
              isDefault: printer.isDefault,
              isAvailable: printer.isAvailable,
            ))
        .toList(growable: false);
  }

  Future<bool> directPrint({
    required Uint8List bytes,
    required String jobName,
    required PdfPageFormat pageFormat,
    String? printerUrl,
    int copies = 1,
  }) async {
    final info = await Printing.info();
    if (!info.canPrint) {
      throw StateError("L'impression PDF n'est pas disponible sur cette plateforme.");
    }
    if (!info.directPrint || !info.canListPrinters) {
      return Printing.layoutPdf(
        name: jobName,
        format: pageFormat,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    }
    final printers = await Printing.listPrinters();
    if (printers.isEmpty) {
      return Printing.layoutPdf(
        name: jobName,
        format: pageFormat,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    }

    // Never silently redirect a configured POS job to another printer.
    // Receipts can contain sensitive financial information.
    if (printerUrl == null || printerUrl.trim().isEmpty) {
      return Printing.layoutPdf(
        name: jobName,
        format: pageFormat,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    }

    final matching = printers.where((printer) => printer.url == printerUrl).toList();
    if (matching.isEmpty) {
      throw StateError('L’imprimante POS configurée est introuvable.');
    }
    final selected = matching.first;
    if (!selected.isAvailable) {
      throw StateError('L’imprimante POS configurée est indisponible.');
    }

    var printed = true;
    for (var i = 0; i < copies.clamp(1, 2).toInt(); i++) {
      final result = await Printing.directPrintPdf(
        printer: selected,
        name: jobName,
        format: pageFormat,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
      printed = printed && result;
    }
    return printed;
  }
}
