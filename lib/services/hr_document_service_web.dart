import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class HrDocumentService {
  Future<String?> pickAndStore(
    String employeeId, {
    String folder = 'documents',
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions ?? const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    const maxBytes = 10 * 1024 * 1024;
    if (file.size > maxBytes) {
      throw StateError('Le document RH dépasse 10 Mo. Choisissez un fichier plus léger.');
    }

    final bytes = await _readLimitedBytes(file, maxBytes);
    if (bytes == null) return null;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }


  Future<Uint8List?> _readLimitedBytes(PlatformFile file, int maxBytes) async {
    final stream = file.readStream;
    if (stream == null) return file.bytes;
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw StateError('Le fichier sélectionné dépasse la taille autorisée.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<Uint8List?> readBytes(String reference) async {
    if (!reference.startsWith('data:')) return null;
    final i = reference.indexOf(',');
    return i < 0 ? null : base64Decode(reference.substring(i + 1));
  }

  Future<void> delete(String reference) async {}
}
