import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StudentMediaService {
  static const _uuid = Uuid();

  Future<String?> pickAndStorePhoto(String studentId) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    final source = result?.files.single.path;
    if (source == null) return null;
    return _copyToStudentFolder(studentId, source, 'photos');
  }

  Future<String?> pickAndStoreDocument(String studentId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    final source = result?.files.single.path;
    if (source == null) return null;
    return _copyToStudentFolder(studentId, source, 'documents');
  }

  Future<String> _copyToStudentFolder(String studentId, String sourcePath, String kind) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'GesApp', 'students', studentId, kind));
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).toLowerCase();
    final target = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}$ext');
    await File(sourcePath).copy(target);
    return target;
  }


  Future<Uint8List?> readStoredFileBytes(String reference) async {
    final file = File(reference);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> deleteStoredFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
