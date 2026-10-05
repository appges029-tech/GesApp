import 'dart:typed_data';

class StudentMediaService {
  Future<String?> pickAndStorePhoto(String studentId) async => null;
  Future<String?> pickAndStoreDocument(String studentId) async => null;
  Future<Uint8List?> readStoredFileBytes(String reference) async => null;
  Future<void> deleteStoredFile(String reference) async {}
}
