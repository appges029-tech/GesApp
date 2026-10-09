import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/download_service.dart';
import '../../core/platform/pdf_output_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/widgets/stored_image.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/student.dart';
import '../../services/student_media_service.dart';
import '../../services/student_pdf_service.dart';
import '../../services/document_number_service.dart';
import 'student_form_screen.dart';
import 'student_guardians_screen.dart';

class StudentDetailScreen extends ConsumerStatefulWidget {
  const StudentDetailScreen({super.key, required this.student});
  final Student student;
  @override ConsumerState<StudentDetailScreen> createState()=>_StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen>{
  late Future<StudentDetailBundle> _future; bool _busy=false;
  final _media=StudentMediaService();
  @override void initState(){super.initState();_reload();}
  void _reload(){_future=ref.read(studentRepositoryProvider).detailBundle(widget.student.id);if(mounted)setState((){});}
  String _status(String s)=>switch(s){'active'=>'Actif','reinscrit'=>'Actif','transfere'=>'Transféré','exclu'=>'Exclu','abandon'=>'Abandon',_=>s};

  Future<void> _changeStatus(Student s) async {
    String selected=s.status; final note=TextEditingController();
    final value=await showDialog<String>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('Changer le statut'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(initialValue:selected,items:const [DropdownMenuItem(value:'active',child:Text('Actif')),DropdownMenuItem(value:'transfere',child:Text('Transféré')),DropdownMenuItem(value:'exclu',child:Text('Exclu')),DropdownMenuItem(value:'abandon',child:Text('Abandon'))],onChanged:(v){if(v!=null)setD(()=>selected=v);}),const SizedBox(height:10),TextField(controller:note,decoration:const InputDecoration(labelText:'Motif / note'))]),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(d,selected),child:const Text('Enregistrer'))])));
    final noteText=note.text.trim();note.dispose();if(value==null||value==s.status)return;
    setState(()=>_busy=true);try{await ref.read(studentRepositoryProvider).updateStatus(s.id,value,note:noteText.isEmpty?null:noteText);ref.invalidate(studentsProvider);ref.invalidate(dashboardProvider);_reload();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _reEnroll(Student s) async {
    final classes=await ref.read(studentRepositoryProvider).classrooms();if(!mounted)return;if(classes.isEmpty)return;
    String selected=classes.any((c)=>c.id==s.classroomId)?s.classroomId:classes.first.id;
    final value=await showDialog<String>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('Réinscrire pour l’année active'),content:DropdownButtonFormField<String>(initialValue:selected,items:classes.map((c)=>DropdownMenuItem(value:c.id,child:Text(c.label))).toList(),onChanged:(v){if(v!=null)setD(()=>selected=v);}),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(d,selected),child:const Text('Réinscrire'))])));
    if(value==null)return;setState(()=>_busy=true);try{await ref.read(studentRepositoryProvider).reEnroll(studentId:s.id,classroomId:value);ref.invalidate(studentsProvider);ref.invalidate(classroomsProvider);ref.invalidate(dashboardProvider);_reload();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _changeClassroom(Student s) async {
    final classes=await ref.read(studentRepositoryProvider).classrooms();if(!mounted||classes.isEmpty)return;
    String selected=s.classroomId;final note=TextEditingController();
    final value=await showDialog<String>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('Changer de classe'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(initialValue:selected,items:classes.map((c)=>DropdownMenuItem(value:c.id,child:Text(c.label))).toList(),onChanged:(v){if(v!=null)setD(()=>selected=v);}),const SizedBox(height:10),TextField(controller:note,decoration:const InputDecoration(labelText:'Motif / observation'))]),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(d,selected),child:const Text('Changer'))])));
    final reason=note.text.trim();note.dispose();if(value==null||value==s.classroomId)return;
    setState(()=>_busy=true);try{await ref.read(studentRepositoryProvider).changeClassroom(studentId:s.id,classroomId:value,note:reason.isEmpty?null:reason);ref.invalidate(studentsProvider);ref.invalidate(classroomsProvider);_reload();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _photo(Student s) async {final path=await _media.pickAndStorePhoto(s.id);if(path==null)return;setState(()=>_busy=true);try{await ref.read(studentRepositoryProvider).updatePhotoPath(s.id,path);_reload();}finally{if(mounted)setState(()=>_busy=false);}}

  Future<void> _changeFamily(Student s) async {
    final families = await ref.read(familyRepositoryProvider).list();
    if (!mounted) return;
    String? selected = s.familyId;
    final value = await showDialog<String?>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Rattacher à une famille'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Famille'),
            items: families.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
            onChanged: (v) => setD(() => selected = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            if (s.familyId != null) TextButton(onPressed: () => Navigator.pop(d, '__DETACH__'), child: const Text('Détacher')),
            FilledButton(onPressed: selected == null ? null : () => Navigator.pop(d, selected), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(familyRepositoryProvider).assignStudent(studentId: s.id, familyId: value == '__DETACH__' ? null : value);
      ref.invalidate(familiesProvider);
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addDocument(Student s) async {
    final configured = await ref.read(settingsRepositoryProvider).documentRequirements(includeInactive: false);
    if (!mounted) return;
    final custom = TextEditingController();
    String? selected = configured.isEmpty ? null : configured.first.name;
    bool required = configured.isEmpty ? false : configured.first.required;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Ajouter une pièce'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (configured.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Type de pièce configuré'),
                items: configured.map((x) => DropdownMenuItem(value: x.name, child: Text('${x.name}${x.required ? ' *' : ''}'))).toList(),
                onChanged: (v) {
                  setD(() {
                    selected = v;
                    for (final item in configured) { if (item.name == v) { required = item.required; break; } }
                  });
                },
              ),
            if (configured.isNotEmpty) const SizedBox(height: 8),
            TextField(controller: custom, decoration: InputDecoration(labelText: configured.isEmpty ? 'Type de pièce *' : 'Ou autre type (facultatif)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, custom.text.trim().isNotEmpty || selected != null), child: const Text('Choisir le fichier')),
          ],
        ),
      ),
    );
    final label = custom.text.trim().isNotEmpty ? custom.text.trim() : (selected ?? 'Document');
    custom.dispose();
    if (ok != true) return;
    final path = await _media.pickAndStoreDocument(s.id);
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(studentRepositoryProvider).addDocument(studentId: s.id, documentType: label, filePath: path, isRequired: required);
      _reload();
    } catch (e) {
      await _media.deleteStoredFile(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _deleteDoc(StudentDocumentItem d) async {final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Supprimer cette pièce ?'),content:Text(d.documentType),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Supprimer'))]));if(ok!=true)return;await ref.read(studentRepositoryProvider).deleteDocument(d.id);await _media.deleteStoredFile(d.filePath);_reload();}

  Future<void> _viewDoc(StudentDocumentItem d) async {final bytes=await _media.readStoredFileBytes(d.filePath);if(bytes==null){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Fichier introuvable.')));return;}final lower=d.filePath.toLowerCase();final isImage=lower.contains('image/')||lower.endsWith('.jpg')||lower.endsWith('.jpeg')||lower.endsWith('.png')||lower.endsWith('.webp');if(isImage){if(!mounted)return;showDialog(context:context,builder:(c)=>Dialog(child:InteractiveViewer(child:Image.memory(bytes))));return;}await downloadBytes(bytes:bytes,fileName:'${d.documentType.replaceAll(' ','_')}.pdf',mimeType:'application/pdf');}

  Future<void> _print(StudentDetailBundle b) async {final est=await ref.read(settingsRepositoryProvider).establishment();final registry=DocumentNumberService();final reference=await registry.getOrCreate(type:'FEL',entityId:b.student.id);final bytes=await StudentPdfService().build(bundle:b,establishment:est,reference:reference);await registry.recordFingerprint(reference:reference,bytes:bytes);await outputPdf(bytes,fileName:'Fiche_${b.student.registrationNumber??b.student.id}_$reference.pdf');}

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fiche élève')),
        body: FutureBuilder<StudentDetailBundle>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Erreur : ${snap.error}'));
            }

            final b = snap.data!;
            final s = b.student;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _busy || OperatorSession.isReadOnly ? null : () => _photo(s),
                              child: ClipOval(
                                child: StoredImage(
                                  reference: s.photoPath,
                                  width: 68,
                                  height: 68,
                                  fallback: Container(
                                    width: 68,
                                    height: 68,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.add_a_photo_outlined),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.fullName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(s.registrationNumber ?? 'Sans matricule'),
                                  Text('${s.cycleName} · ${s.classroomName}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        _line('Statut', _status(s.status)),
                        _line('Sexe', s.gender ?? '—'),
                        _line(
                          'Naissance',
                          s.birthDate?.toIso8601String().split('T').first ?? '—',
                        ),
                        _line('Lieu', s.birthPlace ?? '—'),
                        _line('Parent / tuteur', s.guardianName ?? '—'),
                        _line('Téléphone', s.guardianPhone ?? '—'),
                        _line('Famille', s.familyName ?? '—'),
                        const SizedBox(height: 10),
                        if (!OperatorSession.isReadOnly)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentGuardiansScreen(studentId: s.id, studentName: s.fullName))),
                              icon: const Icon(Icons.supervisor_account_outlined),
                              label: const Text('Gérer les responsables'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Situation financière',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        if (s.paymentStatus == 'pending_configuration')
                          const Text('Échéancier incomplet : configurez les frais et leur calendrier.', style: TextStyle(color: Colors.deepOrange)),
                        if (s.paymentStatus == 'needs_review')
                          const Text('Échéancier à vérifier après modification du dossier.', style: TextStyle(color: Colors.deepOrange)),
                        _line('Attendu', formatXaf(b.finance.expected)),
                        _line('Payé', formatXaf(b.finance.paid)),
                        _line('Reste', formatXaf(b.finance.outstanding)),
                        _line('En retard', formatXaf(b.finance.overdue)),
                        _line('Paiements', '${b.finance.paymentCount}'),
                        _line('Forfait', s.hasPackage ? 'Actif' : 'Non'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Map<String,Object?>>>(
                  future: ref.read(studentRepositoryProvider).classroomMovements(b.student.id),
                  builder: (context, snapshot) {
                    final moves=snapshot.data ?? const <Map<String,Object?>>[];
                    return Card(child:ExpansionTile(
                      title:const Text('Mouvements de classe',style:TextStyle(fontWeight:FontWeight.w800)),
                      subtitle:Text('${moves.length} changement(s) intra-annuel(s)'),
                      children:moves.isEmpty
                        ? const [Padding(padding:EdgeInsets.all(16),child:Text('Aucun changement de classe enregistré.'))]
                        : moves.map((m)=>ListTile(leading:const Icon(Icons.swap_horiz_rounded),title:Text('${m['from_classroom']} → ${m['to_classroom']}'),subtitle:Text('${m['school_year']} · ${('${m['effective_at']}').split('T').first}${(m['reason']??'').toString().isEmpty?'':' · ${m['reason']}'}'))).toList(),
                    ));
                  },
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Pièces du dossier',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (!OperatorSession.isReadOnly)
                              IconButton(
                                tooltip: 'Ajouter une pièce',
                                onPressed: _busy ? null : () => _addDocument(s),
                                icon: const Icon(Icons.note_add_outlined),
                              ),
                          ],
                        ),
                        FutureBuilder<Map<String,Object?>>(
                          future: ref.read(studentRepositoryProvider).documentCompleteness(s.id),
                          builder: (context, snap) {
                            final c=snap.data; if(c==null) return const SizedBox.shrink();
                            final missing=(c['missing'] as List?)?.cast<String>() ?? const <String>[];
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: (c['complete']==true?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.errorContainer).withValues(alpha:.55),borderRadius:BorderRadius.circular(12)),
                              child: Text(c['complete']==true?'Dossier complet · ${c['present']}/${c['required']} pièces obligatoires':'Dossier incomplet · ${c['present']}/${c['required']} · Manque : ${missing.join(', ')}',style:const TextStyle(fontWeight:FontWeight.w700)),
                            );
                          },
                        ),
                        if (b.documents.isEmpty)
                          const Text('Aucune pièce enregistrée.')
                        else
                          ...b.documents.map(
                            (d) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                d.isRequired
                                    ? Icons.verified_outlined
                                    : Icons.description_outlined,
                              ),
                              title: Text(d.documentType),
                              subtitle: Text(
                                '${d.addedAt.toIso8601String().split('T').first}${d.verificationCode == null ? '' : ' · ${d.verificationCode}'}${d.isVerificationValid ? '' : ' · INVALIDÉ'}',
                              ),
                              onTap: () => _viewDoc(d),
                              trailing: OperatorSession.isReadOnly
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _deleteDoc(d),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ExpansionTile(
                    title: const Text(
                      'Échéances',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${b.dues.length} ligne(s)'),
                    children: [
                      if (b.dues.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune échéance.'),
                        )
                      else
                        ...b.dues.map(
                          (d) => ListTile(
                            title: Text('${d.feeName} · ${d.periodKey}'),
                            subtitle: Text(
                              'Dû ${formatXaf(d.amountDue)} · payé ${formatXaf(d.amountPaid)} · reste ${formatXaf(d.balance)}',
                            ),
                            trailing: Text(d.status),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ExpansionTile(
                    title: const Text(
                      'Paiements',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${b.payments.length} paiement(s)'),
                    children: [
                      if (b.payments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucun paiement.'),
                        )
                      else
                        ...b.payments.map(
                          (p) => ListTile(
                            title: Text(
                              '${p.receiptNumber} · ${formatXaf(p.amount)}',
                            ),
                            subtitle: Text(
                              '${p.paidAt.toIso8601String().split('T').first} · ${p.method}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ExpansionTile(
                    title: const Text('Parcours scolaire', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${b.enrollments.length} année(s)'),
                    children: [
                      if (b.enrollments.isEmpty)
                        const Padding(padding: EdgeInsets.all(16), child: Text('Aucun historique annuel.'))
                      else
                        ...b.enrollments.map((e) => ListTile(
                              leading: const Icon(Icons.calendar_month_outlined),
                              title: Text('${e.schoolYearLabel} · ${e.cycleName} ${e.classroomName}'),
                              subtitle: Text('${e.enrollmentType == 're_enrollment' ? 'Réinscription' : e.enrollmentType == 'new' ? 'Nouvelle inscription' : 'Historique migré'} · ${_status(e.status)}${e.observations == null || e.observations!.isEmpty ? '' : ' · ${e.observations}'}'),
                            )),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historique des statuts',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        if (b.history.isEmpty)
                          const Text('Aucun historique.')
                        else
                          ...b.history.map(
                            (h) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.history),
                              title: Text(
                                '${h.oldStatus == null ? '—' : _status(h.oldStatus!)} → ${_status(h.newStatus)}',
                              ),
                              subtitle: Text(
                                '${h.changedAt.toIso8601String().split('T').first}${h.note == null || h.note!.isEmpty ? '' : ' · ${h.note}'}',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!OperatorSession.isReadOnly) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () async {
                      final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StudentFormScreen(student: s)));
                      if (changed == true) { ref.invalidate(studentsProvider); _reload(); }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier les informations'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _reEnroll(s),
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('Réinscrire pour l’année active'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _changeClassroom(s),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Changer de classe'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _changeFamily(s),
                    icon: const Icon(Icons.family_restroom),
                    label: const Text('Rattacher / changer de famille'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _changeStatus(s),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Changer le statut'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _print(b),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Imprimer / exporter la fiche PDF'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            );
          },
        ),
      );

  Widget _line(String label,String value)=>Padding(padding:const EdgeInsets.only(bottom:8),child:LayoutBuilder(builder:(context,box){final compact=box.maxWidth<360;final labelWidget=Text(label,style:const TextStyle(fontWeight:FontWeight.w700));final valueWidget=Text(value.isEmpty?'—':value);return compact?Column(crossAxisAlignment:CrossAxisAlignment.start,children:[labelWidget,const SizedBox(height:2),valueWidget]):Row(crossAxisAlignment:CrossAxisAlignment.start,children:[SizedBox(width:115,child:labelWidget),Expanded(child:valueWidget)]);}));
}
