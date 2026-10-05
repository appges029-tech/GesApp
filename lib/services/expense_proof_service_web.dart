import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class ExpenseProofService {
  Future<String?> pickAndStore(String expenseToken) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    const maxBytes = 10 * 1024 * 1024;
    if (file.size > maxBytes) throw StateError('Le justificatif dépasse 10 Mo. Choisissez un fichier plus léger.');
    final bytes = await _readLimitedBytes(file, maxBytes);
    if (bytes == null) return null;
    final mime = switch ((file.extension ?? '').toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
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
    final comma = reference.indexOf(',');
    if (comma < 0) return null;
    return base64Decode(reference.substring(comma + 1));
  }

  Future<void> delete(String reference) async {}
}
