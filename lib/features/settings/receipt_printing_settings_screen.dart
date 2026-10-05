import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../services/document_identity.dart';
import '../../services/pos_printer_service.dart';
import '../../services/receipt_printing_preferences.dart';
import '../../services/receipt_service.dart';

class ReceiptPrintingSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptPrintingSettingsScreen({super.key});

  @override
  ConsumerState<ReceiptPrintingSettingsScreen> createState() => _ReceiptPrintingSettingsScreenState();
}

class _ReceiptPrintingSettingsScreenState extends ConsumerState<ReceiptPrintingSettingsScreen> {
  final _store = ReceiptPrintingPreferencesStore();
  final _printerService = PosPrinterService();
  ReceiptPrintingPreferences _value = const ReceiptPrintingPreferences();
  List<PosPrinterDescriptor> _printers = const [];
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    var value = await _store.load();
    List<PosPrinterDescriptor> printers = const [];
    try {
      printers = await _printerService.listPrinters();
    } catch (_) {}
    if (!mounted) return;
    final selectedStillExists = value.printerUrl == null || printers.any((p) => p.url == value.printerUrl);
    if (!selectedStillExists) value = value.copyWith(clearPrinter: true);
    setState(() {
      _value = value;
      _printers = printers;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _store.save(_value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réglages d’impression enregistrés.')));
  }

  Future<void> _testPrint() async {
    if (!_value.format.isPos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choisissez POS 80 mm ou POS 58 mm pour lancer un ticket test.')));
      return;
    }
    setState(() => _testing = true);
    try {
      final establishment = await ref.read(establishmentProvider.future);
      final identity = await DocumentIdentity.fromEstablishment(establishment);
      final data = ReceiptData(
        identity: identity,
        receiptNumber: 'POS-TEST',
        studentName: 'Ticket de test',
        amount: 35000,
        currency: 'FCFA',
        paymentMethod: 'Espèces',
        dateLabel: '20/09/2026 12:00',
        lines: const [
          ReceiptLine(label: 'Scolarité', amount: 25000),
          ReceiptLine(label: 'Transport', amount: 10000),
        ],
      );
      final bytes = await ReceiptService().generate(
        data,
        format: _value.format,
        showLogo: _value.showLogo,
        includeDetails: _value.includeDetails,
      );
      final ok = await _printerService.directPrint(
        bytes: bytes,
        jobName: 'GesApp-POS-Test',
        pageFormat: _value.format.pageFormatFor(detailLines: _value.includeDetails ? data.lines.length : 0),
        printerUrl: _value.printerUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Ticket test envoyé à l’imprimante.' : 'Le ticket test n’a pas été confirmé.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impression test impossible : $error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final posEnabled = _value.format.isPos;
    return Scaffold(
      appBar: AppBar(title: const Text('Reçus & imprimante POS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Format des reçus', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          DropdownButtonFormField<ReceiptFormat>(
            initialValue: _value.format,
            decoration: const InputDecoration(labelText: 'Format par défaut'),
            items: ReceiptFormat.values.map((format) => DropdownMenuItem(value: format, child: Text(format.label))).toList(),
            onChanged: (format) {
              if (format == null) return;
              setState(() => _value = _value.copyWith(format: format, autoPrint: format.isPos ? _value.autoPrint : false));
            },
          ),
          const SizedBox(height: 18),
          Text('Imprimante thermique', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _value.printerUrl != null && _printers.any((p) => p.url == _value.printerUrl) ? _value.printerUrl : null,
            decoration: InputDecoration(
              labelText: 'Imprimante POS par défaut',
              helperText: _printers.isEmpty ? 'Aucune imprimante détectée. Vérifiez Windows et le pilote.' : 'La sélection est mémorisée sur cet appareil.',
            ),
            items: _printers
                .map((printer) => DropdownMenuItem(
                      value: printer.url,
                      child: Text('${printer.name}${printer.isDefault ? ' · par défaut' : ''}${printer.isAvailable ? '' : ' · indisponible'}'),
                    ))
                .toList(),
            onChanged: posEnabled
                ? (url) {
                    PosPrinterDescriptor? printer;
                    for (final item in _printers) {
                      if (item.url == url) { printer = item; break; }
                    }
                    setState(() => _value = printer == null
                        ? _value.copyWith(clearPrinter: true, autoPrint: false)
                        : _value.copyWith(printerUrl: printer.url, printerName: printer.name));
                  }
                : null,
          ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Actualiser les imprimantes'))),
          const Divider(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Impression automatique après paiement'),
            subtitle: Text(_value.printerUrl == null
                ? 'Sélectionnez d’abord une imprimante POS. Le paiement reste enregistré même si l’impression échoue.'
                : 'Le paiement reste enregistré même si l’imprimante devient indisponible.'),
            value: posEnabled && _value.printerUrl != null && _value.autoPrint,
            onChanged: posEnabled && _value.printerUrl != null
                ? (v) => setState(() => _value = _value.copyWith(autoPrint: v))
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher le logo sur le ticket'),
            value: _value.showLogo,
            onChanged: posEnabled ? (v) => setState(() => _value = _value.copyWith(showLogo: v)) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Imprimer le détail des affectations'),
            subtitle: const Text('Scolarité, transport, périodes et autres lignes affectées au paiement.'),
            value: _value.includeDetails,
            onChanged: posEnabled ? (v) => setState(() => _value = _value.copyWith(includeDetails: v)) : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _value.copies,
            decoration: const InputDecoration(labelText: 'Nombre de copies POS'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 copie')),
              DropdownMenuItem(value: 2, child: Text('2 copies')),
            ],
            onChanged: posEnabled ? (v) => setState(() => _value = _value.copyWith(copies: v ?? 1)) : null,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer')),
              OutlinedButton.icon(onPressed: _testing || !posEnabled ? null : _testPrint, icon: const Icon(Icons.print_outlined), label: Text(_testing ? 'Impression…' : 'Imprimer un ticket test')),
            ],
          ),
        ],
      ),
    );
  }
}
