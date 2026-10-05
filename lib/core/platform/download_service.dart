import 'dart:typed_data';

import 'download_service_stub.dart'
    if (dart.library.io) 'download_service_io.dart'
    if (dart.library.html) 'download_service_web.dart' as impl;

Future<String?> downloadBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) => impl.downloadBytes(bytes: bytes, fileName: fileName, mimeType: mimeType);
