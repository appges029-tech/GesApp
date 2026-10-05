import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/student.dart';

class StudentFormScreen extends ConsumerStatefulWidget {
  const StudentFormScreen({super.key, this.student});
  final Student? student;
  @override
  ConsumerState<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends ConsumerState<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName, _lastName, _guardianName, _guardianPhone, _birthPlace, _nationality, _address, _originSchool;
  String? _classroomId, _familyId, _gender;
  DateTime? _birthDate;
  bool _saving = false;
  bool get editing => widget.student != null;

  @override
  void initState() {
    super.initState();
    final student = widget.student;
    _firstName = TextEditingController(text: student?.firstName);
    _lastName = TextEditingController(text: student?.lastName);
    _guardianName = TextEditingController(text: student?.guardianName);
    _guardianPhone = TextEditingController(text: student?.guardianPhone);
    _birthPlace = TextEditingController(text: student?.birthPlace);
    _nationality = TextEditingController(text: student?.nationality);
    _address = TextEditingController(text: student?.address);
    _originSchool = TextEditingController(text: student?.originSchool);
    _classroomId = student?.classroomId;
    _familyId = student?.familyId;
    _gender = student?.gender;
    _birthDate = student?.birthDate;
  }

  @override
  void dispose() {
    for (final controller in [_firstName, _lastName, _guardianName, _guardianPhone, _birthPlace, _nationality, _address, _originSchool]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
      initialDate: _birthDate ?? DateTime(DateTime.now().year - 10),
    );
    if (value != null && mounted) setState(() => _birthDate = value);
  }

  Future<bool> _confirmDuplicate() async {
    final duplicates = await ref.read(studentRepositoryProvider).findPossibleDuplicates(
          firstName: _firstName.text,
          lastName: _lastName.text,
          birthDate: _birthDate,
          excludingId: widget.student?.id,
        );
    if (duplicates.isEmpty) return true;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Doublon possible'),
            content: Text('${duplicates.length} élève(s) avec le même nom${_birthDate == null ? '' : ' et la même date de naissance'} existe(nt) déjà. Continuer quand même ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vérifier')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _classroomId == null) return;
    if (!await _confirmDuplicate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(studentRepositoryProvider);
      if (editing) {
        await repo.updateStudent(
          studentId: widget.student!.id,
          firstName: _firstName.text,
          lastName: _lastName.text,
          classroomId: _classroomId!,
          guardianName: _guardianName.text,
          guardianPhone: _guardianPhone.text,
          familyId: _familyId,
          gender: _gender,
          birthDate: _birthDate,
          birthPlace: _birthPlace.text,
          nationality: _nationality.text,
          address: _address.text,
          originSchool: _originSchool.text,
        );
      } else {
        await repo.add(
          firstName: _firstName.text,
          lastName: _lastName.text,
          classroomId: _classroomId!,
          guardianName: _guardianName.text,
          guardianPhone: _guardianPhone.text,
          familyId: _familyId,
          gender: _gender,
          birthDate: _birthDate,
          birthPlace: _birthPlace.text,
          nationality: _nationality.text,
          address: _address.text,
          originSchool: _originSchool.text,
        );
      }
      ref.invalidate(studentsProvider);
      ref.invalidate(classroomsProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(auditEntriesProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = ref.watch(classroomsProvider);
    final families = ref.watch(familiesProvider);
    final desktop = WindowsUi.isDesktop(context);

    final form = Form(
      key: _formKey,
      child: ListView(
        children: [
          WindowsPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Identité', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              ResponsiveFormRow(
                breakpoint: 720,
                spacing: 12,
                children: [
                  TextFormField(controller: _lastName, decoration: const InputDecoration(labelText: 'Nom *', prefixIcon: Icon(Icons.person_outline)), validator: (v) => v == null || v.trim().isEmpty ? 'Nom obligatoire' : null),
                  TextFormField(controller: _firstName, decoration: const InputDecoration(labelText: 'Prénom *', prefixIcon: Icon(Icons.badge_outlined)), validator: (v) => v == null || v.trim().isEmpty ? 'Prénom obligatoire' : null),
                ],
              ),
              const SizedBox(height: 12),
              ResponsiveFormRow(
                breakpoint: 720,
                spacing: 12,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(labelText: 'Sexe'),
                    isExpanded: true,
                    items: const [DropdownMenuItem(value: 'M', child: Text('Masculin')), DropdownMenuItem(value: 'F', child: Text('Féminin'))],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickBirthDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Align(alignment: Alignment.centerLeft, child: Text(_birthDate == null ? 'Date de naissance' : _birthDate!.toIso8601String().split('T').first)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ResponsiveFormRow(
                breakpoint: 720,
                spacing: 12,
                children: [
                  TextFormField(controller: _birthPlace, decoration: const InputDecoration(labelText: 'Lieu de naissance')),
                  TextFormField(controller: _nationality, decoration: const InputDecoration(labelText: 'Nationalité')),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Adresse'), maxLines: desktop ? 2 : 1),
              const SizedBox(height: 12),
              TextFormField(controller: _originSchool, decoration: const InputDecoration(labelText: 'Établissement d’origine')),
              const SizedBox(height: 12),
              classes.when(
                data: (items) => DropdownButtonFormField<String>(
                  initialValue: items.any((e) => e.id == _classroomId) ? _classroomId : null,
                  decoration: const InputDecoration(labelText: 'Classe *'),
                  isExpanded: true,
                  items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.label, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _classroomId = v),
                  validator: (v) => v == null ? 'Classe obligatoire' : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          WindowsPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Responsable principal', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ResponsiveFormRow(
                breakpoint: 720,
                spacing: 12,
                children: [
                  TextFormField(controller: _guardianName, decoration: const InputDecoration(labelText: 'Nom du parent / tuteur')),
                  TextFormField(controller: _guardianPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
                ],
              ),
              const SizedBox(height: 12),
              families.when(
                data: (items) => DropdownButtonFormField<String>(
                  initialValue: items.any((e) => e.id == _familyId) ? _familyId : null,
                  decoration: const InputDecoration(labelText: 'Famille'),
                  isExpanded: true,
                  items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _familyId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Enregistrement…' : editing ? 'Enregistrer les modifications' : 'Enregistrer l’inscription'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );

    return WindowsPageScaffold(
      title: editing ? 'Modifier l’élève' : 'Nouvelle inscription',
      subtitle: desktop ? 'Identité, classe et responsable principal' : null,
      maxWidth: WindowsUi.formMaxWidth,
      body: desktop ? form : Padding(padding: const EdgeInsets.all(16), child: form),
    );
  }
}
