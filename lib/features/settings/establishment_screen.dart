import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/student_media_service.dart';

class EstablishmentScreen extends ConsumerStatefulWidget {
  const EstablishmentScreen({super.key});
  
  @override
  ConsumerState<EstablishmentScreen> createState() => _EstablishmentScreenState();
}

class _EstablishmentScreenState extends ConsumerState<EstablishmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _phone, _email, _address, _approval;
  String? _logoPath;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _email = TextEditingController();
    _address = TextEditingController();
    _approval = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _approval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final reference = await StudentMediaService().pickAndStorePhoto('establishment-logo');
    if (reference != null && mounted) {
      setState(() => _logoPath = reference);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final activeYear = await repo.activeSchoolYear();
      final now = DateTime.now();
      final baseYear = now.month >= 8 ? now.year : now.year - 1;
      final initialStart = DateTime(baseYear, 9, 1);
      final initialEnd = DateTime(baseYear + 1, 7, 31);
      await repo.saveEstablishment(EstablishmentData(
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        approvalNumber: _approval.text,
        logoPath: _logoPath ?? '',
        schoolYearLabel: activeYear?.label ?? '$baseYear-${baseYear + 1}',
        schoolYearStart: activeYear?.startDate ?? initialStart,
        schoolYearEnd: activeYear?.endDate ?? initialEnd,
      ));
      ref.invalidate(establishmentProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Établissement enregistré.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final establishment = ref.watch(establishmentProvider);
    establishment.whenData((data) {
      if (!_loaded && data != null) {
        _loaded = true;
        _name.text = data.name;
        _phone.text = data.phone;
        _email.text = data.email;
        _address.text = data.address;
        _approval.text = data.approvalNumber;
        _logoPath = data.logoPath.trim().isEmpty ? null : data.logoPath;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Établissement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _approval,
              decoration: const InputDecoration(labelText: 'Approbation'),
            ),
            const SizedBox(height: 24),
            _logoPath != null
                ? Image.asset(_logoPath!, height: 120)
                : Container(
                    height: 120,
                    color: Colors.grey[300],
                    child: const Center(child: Text('Pas de logo')),
                  ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: OperatorSession.isReadOnly ? null : _pickLogo,
              icon: const Icon(Icons.image),
              label: const Text('Changer le logo'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving || OperatorSession.isReadOnly ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
