import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_service.dart';

class ReceiptPrintingPreferences {
  const ReceiptPrintingPreferences({
    this.format = ReceiptFormat.a5,
    this.printerUrl,
    this.printerName,
    this.autoPrint = false,
    this.showLogo = true,
    this.includeDetails = true,
    this.copies = 1,
  });

  final ReceiptFormat format;
  final String? printerUrl;
  final String? printerName;
  final bool autoPrint;
  final bool showLogo;
  final bool includeDetails;
  final int copies;

  ReceiptPrintingPreferences copyWith({
    ReceiptFormat? format,
    String? printerUrl,
    String? printerName,
    bool clearPrinter = false,
    bool? autoPrint,
    bool? showLogo,
    bool? includeDetails,
    int? copies,
  }) =>
      ReceiptPrintingPreferences(
        format: format ?? this.format,
        printerUrl: clearPrinter ? null : printerUrl ?? this.printerUrl,
        printerName: clearPrinter ? null : printerName ?? this.printerName,
        autoPrint: autoPrint ?? this.autoPrint,
        showLogo: showLogo ?? this.showLogo,
        includeDetails: includeDetails ?? this.includeDetails,
        copies: (copies ?? this.copies).clamp(1, 2).toInt(),
      );

  Map<String, Object?> toMap() => {
        'format': format.storageKey,
        'printerUrl': printerUrl,
        'printerName': printerName,
        'autoPrint': autoPrint,
        'showLogo': showLogo,
        'includeDetails': includeDetails,
        'copies': copies,
      };

  factory ReceiptPrintingPreferences.fromMap(Map<String, Object?> map) => ReceiptPrintingPreferences(
        format: ReceiptFormatX.fromStorageKey(map['format'] as String?),
        printerUrl: map['printerUrl'] as String?,
        printerName: map['printerName'] as String?,
        autoPrint: map['autoPrint'] as bool? ?? false,
        showLogo: map['showLogo'] as bool? ?? true,
        includeDetails: map['includeDetails'] as bool? ?? true,
        copies: ((map['copies'] as int?) ?? 1).clamp(1, 2).toInt(),
      );
}

class ReceiptPrintingPreferencesStore {
  static const _format = 'receipt_print_format';
  static const _printerUrl = 'receipt_pos_printer_url';
  static const _printerName = 'receipt_pos_printer_name';
  static const _autoPrint = 'receipt_pos_auto_print';
  static const _showLogo = 'receipt_pos_show_logo';
  static const _includeDetails = 'receipt_pos_include_details';
  static const _copies = 'receipt_pos_copies';

  Future<ReceiptPrintingPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReceiptPrintingPreferences(
      format: ReceiptFormatX.fromStorageKey(prefs.getString(_format)),
      printerUrl: prefs.getString(_printerUrl),
      printerName: prefs.getString(_printerName),
      autoPrint: prefs.getBool(_autoPrint) ?? false,
      showLogo: prefs.getBool(_showLogo) ?? true,
      includeDetails: prefs.getBool(_includeDetails) ?? true,
      copies: (prefs.getInt(_copies) ?? 1).clamp(1, 2).toInt(),
    );
  }

  Future<void> save(ReceiptPrintingPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_format, value.format.storageKey);
    if ((value.printerUrl ?? '').isEmpty) {
      await prefs.remove(_printerUrl);
      await prefs.remove(_printerName);
    } else {
      await prefs.setString(_printerUrl, value.printerUrl!);
      await prefs.setString(_printerName, value.printerName ?? value.printerUrl!);
    }
    await prefs.setBool(_autoPrint, value.format.isPos && value.printerUrl != null && value.autoPrint);
    await prefs.setBool(_showLogo, value.showLogo);
    await prefs.setBool(_includeDetails, value.includeDetails);
    await prefs.setInt(_copies, value.copies.clamp(1, 2).toInt());
  }
}
