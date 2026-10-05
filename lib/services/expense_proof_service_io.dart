import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ExpenseProofService {
  static const _uuid = Uuid();

  Future<String?> pickAndStore(String expenseToken) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    final source = result?.files.single.path;
    if (source == null) return null;
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'GesApp', 'expenses', expenseToken, 'proofs'));
    await dir.create(recursive: true);
    final ext = p.extension(source).toLowerCase();
    final target = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}$ext');
    await File(source).copy(target);
    return target;
  }

  Future<Uint8List?> readBytes(String reference) async {
    final file = File(reference);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(String reference) async {
    final file = File(reference);
    if (await file.exists()) await file.delete();
  }
}
