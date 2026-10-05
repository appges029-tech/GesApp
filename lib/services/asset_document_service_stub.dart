import 'dart:typed_data';
class AssetDocumentService {
  Future<String?> pickAndStore(String assetId, {String folder='documents', List<String>? allowedExtensions}) async => null;
  Future<Uint8List?> readBytes(String reference) async => null;
  Future<void> delete(String reference) async {}
}
