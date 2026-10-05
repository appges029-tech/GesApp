import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import 'download_service.dart';

Future<String?> outputPdf(Uint8List bytes, {required String fileName}) async {
  if (kIsWeb) {
    return downloadBytes(bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
  }

  // Sur ordinateur, l'enregistrement direct ne dépend pas d'un pilote
  // d'impression installé ou configuré.
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return downloadBytes(bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
  }

  final completed = await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
  return completed ? fileName : null;
}
