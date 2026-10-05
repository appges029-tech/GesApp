import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> downloadBytes({required Uint8List bytes, required String fileName, required String mimeType}) async {
  final target = await FilePicker.platform.saveFile(
    dialogTitle: 'Enregistrer le fichier',
    fileName: fileName,
    type: FileType.any,
  );
  if (target == null) return null;
  await File(target).writeAsBytes(bytes, flush: true);
  return target;
}
