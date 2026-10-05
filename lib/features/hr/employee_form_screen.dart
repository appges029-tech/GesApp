import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/models/hr.dart';

class EmployeeFormScreen extends ConsumerStatefulWidget {
  const EmployeeFormScreen({super.key, this.employee});
  
  final EmployeeItem? employee;
  
  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first, _last, _phone, _email, _address,
      _birthPlace, _idNumber, _socialSecurityNumber, _emergencyContactName, _emergencyContactPhone;
  
  String? _gender;
  String _status = 'active';
  DateTime _hireDate = DateTime.now();
  DateTime? _birthDate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _first = TextEditingController(text: e?.firstName ?? '');
    _last = TextEditingController(text: e?.lastName ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _birthPlace = TextEditingController(text: e?.birthPlace ?? '');
    _idNumber = TextEditingController(text: e?.idNumber ?? '');
    _socialSecurityNumber = TextEditingController(text: e?.socialSecurityNumber ?? '');
    _emergencyContactName = TextEditingController(text: e?.emergencyContactName ?? '');
    _emergencyContactPhone = TextEditingController(text: e?.emergencyContactPhone ?? '');
    _gender = e?.gender;
    _status = e?.status ?? 'active';
    _birthDate = e?.birthDate;
    _hireDate = e?.hireDate ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [
      _first,
      _last,
      _phone,
      _email,
      _address,
      _birthPlace,
      _idNumber,
      _socialSecurityNumber,
      _emergencyContactName,
      _emergencyContactPhone
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) => showDatePicker(
        context: context,
        firstDate: DateTime(1940),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        initialDate: current ?? DateTime.now(),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(hrRepositoryProvider).saveEmployee(
            id: widget.employee?.id,
            firstName: _first.text,
            lastName: _last.text,
            phone: _phone.text,
            email: _email.text,
            address: _address.text,
            birthPlace: _birthPlace.text,
            birthDate: _birthDate,
            gender: _gender,
            idNumber: _idNumber.text,
            socialSecurityNumber: _socialSecurityNumber.text,
            emergencyContactName: _emergencyContactName.text,
            emergencyContactPhone: _emergencyContactPhone.text,
            hireDate: _hireDate,
            status: _status,
          );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.employee == null ? 'Nouvel employé' : 'Modifier l\'employé',
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _first,
                      decoration: const InputDecoration(labelText: 'Prénom *'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _last,
                      decoration: const InputDecoration(labelText: 'Nom *'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Sexe'),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculin')),
                  DropdownMenuItem(value: 'F', child: Text('Féminin')),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date de naissance'),
                subtitle: Text(
                  _birthDate == null
                      ? 'Non renseignée'
                      : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await _pick(_birthDate);
                  if (picked != null) {
                    setState(() => _birthDate = picked);
                  }
                },
              ),
              TextFormField(
                controller: _birthPlace,
                decoration: const InputDecoration(labelText: 'Lieu de naissance'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idNumber,
                      decoration: const InputDecoration(
                        labelText: 'N° pièce d\'identité',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _socialSecurityNumber,
                      decoration: const InputDecoration(labelText: 'CNSS'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Contact d\'urgence',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emergencyContactName,
                      decoration: const InputDecoration(labelText: 'Nom *'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _emergencyContactPhone,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Téléphone *'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date d\'entrée'),
                subtitle: Text(
                  '${_hireDate.day.toString().padLeft(2, '0')}/${_hireDate.month.toString().padLeft(2, '0')}/${_hireDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await _pick(_hireDate);
                  if (picked != null) {
                    setState(() => _hireDate = picked);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Actif')),
                  DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspendu'),
                  ),
                  DropdownMenuItem(value: 'resigned', child: Text('Démission')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'active'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _save,
                child: _busy
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
