import 'dart:typed_data';
class HrDocumentService {
  Future<String?> pickAndStore(String employeeId, {String folder = 'documents', List<String>? allowedExtensions}) async => null;
  Future<Uint8List?> readBytes(String reference) async => null;
  Future<void> delete(String reference) async {}
}
