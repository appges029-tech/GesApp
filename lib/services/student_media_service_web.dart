import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class StudentMediaService {
  Future<String?> pickAndStorePhoto(String studentId) => _pick(
        FileType.image,
        const [],
      );

  Future<String?> pickAndStoreDocument(String studentId) => _pick(
        FileType.custom,
        const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );

  Future<String?> _pick(FileType type, List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: extensions.isEmpty ? null : extensions,
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final isPhoto = type == FileType.image;
    final maxBytes = isPhoto ? 4 * 1024 * 1024 : 10 * 1024 * 1024;
    if (file.size > maxBytes) {
      throw StateError(isPhoto
          ? 'La photo dépasse 4 Mo. Choisissez une image plus légère.'
          : 'Le document dépasse 10 Mo. Choisissez un fichier plus léger.');
    }
    // Important sur Web : la taille est contrôlée avant la lecture. Le flux
    // évite que FilePicker précharge un fichier arbitrairement volumineux.
    final bytes = await _readLimitedBytes(file, maxBytes);
    if (bytes == null) return null;
    final mime = _mimeFor(file.extension);
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

  Future<Uint8List?> readStoredFileBytes(String reference) async {
    if (!reference.startsWith('data:')) return null;
    final comma = reference.indexOf(',');
    if (comma < 0) return null;
    return base64Decode(reference.substring(comma + 1));
  }

  Future<void> deleteStoredFile(String reference) async {
    // Les données Web sont stockées dans la ligne SQLite/IndexedDB sous forme
    // de data URL. La suppression de la référence en base suffit.
  }

  String _mimeFor(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
