import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
class HrDocumentService {
  static const _uuid = Uuid();
  Future<String?> pickAndStore(String employeeId, {String folder = 'documents', List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: allowedExtensions ?? const ['pdf','jpg','jpeg','png','webp'], allowMultiple: false);
    final source = result?.files.single.path;
    if (source == null) return null;
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path,'GesApp','hr','employees',employeeId,folder));
    await dir.create(recursive: true);
    final ext = p.extension(source).toLowerCase();
    final target = p.join(dir.path,'${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}$ext');
    await File(source).copy(target);
    return target;
  }
  Future<Uint8List?> readBytes(String reference) async { final f=File(reference); return await f.exists()?f.readAsBytes():null; }
  Future<void> delete(String reference) async { final f=File(reference); if(await f.exists()) await f.delete(); }
}
