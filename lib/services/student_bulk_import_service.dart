import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class StudentImportRow {
  const StudentImportRow({
    required this.line,
    required this.firstName,
    required this.lastName,
    required this.classroom,
    this.gender,
    this.birthDate,
    this.birthPlace,
    this.guardianName,
    this.guardianPhone,
    this.familyName,
    this.nationality,
    this.address,
    this.originSchool,
  });

  final int line;
  final String firstName;
  final String lastName;
  final String classroom;
  final String? gender;
  final DateTime? birthDate;
  final String? birthPlace;
  final String? guardianName;
  final String? guardianPhone;
  final String? familyName;
  final String? nationality;
  final String? address;
  final String? originSchool;
}

class StudentImportFile {
  const StudentImportFile({required this.fileName, required this.rows, required this.warnings});
  final String fileName;
  final List<StudentImportRow> rows;
  final List<String> warnings;
}

class StudentBulkImportResult {
  const StudentBulkImportResult({required this.imported, required this.skipped, required this.errors});
  final int imported;
  final int skipped;
  final List<String> errors;
}

class StudentBulkImportPreview {
  const StudentBulkImportPreview({required this.total, required this.valid, required this.skipped, required this.errors});
  final int total;
  final int valid;
  final int skipped;
  final List<String> errors;
  bool get canImport => valid > 0;
}

class StudentBulkImportService {
  static const _aliases = <String, List<String>>{
    'first_name': ['prenom', 'prénom', 'first_name', 'firstname'],
    'last_name': ['nom', 'last_name', 'lastname'],
    'classroom': ['classe', 'classroom', 'classroom_id'],
    'gender': ['sexe', 'genre', 'gender'],
    'birth_date': ['date_naissance', 'date de naissance', 'birth_date', 'naissance'],
    'birth_place': ['lieu_naissance', 'lieu de naissance', 'birth_place'],
    'guardian_name': ['responsable', 'parent', 'tuteur', 'guardian_name'],
    'guardian_phone': ['telephone_responsable', 'téléphone responsable', 'telephone', 'phone', 'guardian_phone'],
    'family_name': ['famille', 'family', 'family_name'],
    'nationality': ['nationalite', 'nationalité', 'nationality'],
    'address': ['adresse', 'address'],
    'origin_school': ['ecole_origine', 'école origine', 'origin_school'],
  };

  Future<StudentImportFile?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('Impossible de lire le fichier sélectionné.');
    }
    return parse(file.name, bytes);
  }

  StudentImportFile parse(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    final matrix = lower.endsWith('.xlsx') ? _xlsx(bytes) : _csv(bytes);
    if (matrix.isEmpty) throw const FormatException('Le fichier est vide.');

    final headers = matrix.first.map(_normalizeHeader).toList();
    final indexes = <String, int>{};
    for (final entry in _aliases.entries) {
      for (final alias in entry.value.map(_normalizeHeader)) {
        final i = headers.indexOf(alias);
        if (i >= 0) {
          indexes[entry.key] = i;
          break;
        }
      }
    }
    for (final required in const ['first_name', 'last_name', 'classroom']) {
      if (!indexes.containsKey(required)) {
        throw FormatException('Colonne obligatoire manquante : $required.');
      }
    }

    String value(List<Object?> row, String key) {
      final i = indexes[key];
      if (i == null || i >= row.length) return '';
      return (row[i] ?? '').toString().trim();
    }

    final rows = <StudentImportRow>[];
    final warnings = <String>[];
    for (var r = 1; r < matrix.length; r++) {
      final raw = matrix[r];
      if (raw.every((v) => (v ?? '').toString().trim().isEmpty)) continue;
      final first = value(raw, 'first_name');
      final last = value(raw, 'last_name');
      final classroom = value(raw, 'classroom');
      if (first.isEmpty || last.isEmpty || classroom.isEmpty) {
        warnings.add('Ligne ${r + 1} ignorée : nom, prénom ou classe manquant.');
        continue;
      }
      final birth = _parseDate(value(raw, 'birth_date'));
      if (value(raw, 'birth_date').isNotEmpty && birth == null) {
        warnings.add('Ligne ${r + 1} : date de naissance illisible, champ laissé vide.');
      }
      rows.add(StudentImportRow(
        line: r + 1,
        firstName: first,
        lastName: last,
        classroom: classroom,
        gender: _nullIfEmpty(value(raw, 'gender')),
        birthDate: birth,
        birthPlace: _nullIfEmpty(value(raw, 'birth_place')),
        guardianName: _nullIfEmpty(value(raw, 'guardian_name')),
        guardianPhone: _nullIfEmpty(value(raw, 'guardian_phone')),
        familyName: _nullIfEmpty(value(raw, 'family_name')),
        nationality: _nullIfEmpty(value(raw, 'nationality')),
        address: _nullIfEmpty(value(raw, 'address')),
        originSchool: _nullIfEmpty(value(raw, 'origin_school')),
      ));
    }
    return StudentImportFile(fileName: fileName, rows: rows, warnings: warnings);
  }

  List<List<Object?>> _csv(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\ufeff', '');
    final delimiter = text.split('\n').first.contains(';') ? ';' : ',';
    return CsvToListConverter(fieldDelimiter: delimiter, shouldParseNumbers: false)
        .convert(text)
        .map((r) => r.cast<Object?>())
        .toList();
  }

  List<List<Object?>> _xlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return const [];
    final sheet = workbook.tables.values.first;
    return sheet.rows
        .map((row) => row.map<Object?>((cell) => cell?.value?.toString()).toList())
        .toList();
  }

  static String _normalizeHeader(Object? value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String? _nullIfEmpty(String value) => value.trim().isEmpty ? null : value.trim();

  static DateTime? _parseDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final direct = DateTime.tryParse(value);
    if (direct != null) return direct;
    final parts = value.split(RegExp(r'[/.-]'));
    if (parts.length == 3) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      final c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        final year = c < 100 ? 2000 + c : c;
        try { return DateTime(year, b, a); } catch (_) {}
      }
    }
    return null;
  }
}
