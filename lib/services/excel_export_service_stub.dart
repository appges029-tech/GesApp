class ExcelExportService {
  Future<String> export({required String fileName, required List<String> headers, required List<List<String>> rows}) async =>
      throw UnsupportedError('Export non supporté sur cette plateforme.');
}
