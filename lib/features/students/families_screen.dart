import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/family.dart';
import 'family_detail_screen.dart';

class FamiliesScreen extends ConsumerWidget {
  const FamiliesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle famille'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom de famille *'), autofocus: true),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone principal')),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Adresse')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, name.text.trim().isNotEmpty), child: const Text('Créer')),
        ],
      ),
    );
    final familyName = name.text.trim();
    final phoneValue = phone.text.trim();
    final addressValue = address.text.trim();
    name.dispose();
    phone.dispose();
    address.dispose();
    if (save != true) return;
    try {
      await ref.read(familyRepositoryProvider).add(
            name: familyName,
            primaryPhone: phoneValue,
            address: addressValue,
          );
      ref.invalidate(familiesProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Création impossible : $error')),
        );
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, FamilyItem family) async {
    final name=TextEditingController(text:family.name),phone=TextEditingController(text:family.primaryPhone??''),phone2=TextEditingController(text:family.secondaryPhone??''),address=TextEditingController(text:family.address??'');
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Modifier la famille'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Nom *')),const SizedBox(height:8),TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Téléphone principal')),const SizedBox(height:8),TextField(controller:phone2,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Téléphone secondaire')),const SizedBox(height:8),TextField(controller:address,decoration:const InputDecoration(labelText:'Adresse'))])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(c,name.text.trim().isNotEmpty),child:const Text('Enregistrer'))]));
    final n=name.text.trim(),p1=phone.text.trim(),p2=phone2.text.trim(),a=address.text.trim();name.dispose();phone.dispose();phone2.dispose();address.dispose();if(ok!=true)return;
    await ref.read(familyRepositoryProvider).update(id:family.id,name:n,primaryPhone:p1,secondaryPhone:p2,address:a);ref.invalidate(familiesProvider);ref.invalidate(auditEntriesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final families = ref.watch(familiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Familles')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.add), label: const Text('Famille')),
      body: families.when(
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'Aucune famille. Créez une famille pour regrouper des frères et sœurs et permettre un encaissement unique ou un forfait familial.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16).copyWith(bottom: 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final f = items[i];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.family_restroom)),
                      title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${f.studentCount} élève(s)${f.primaryPhone != null && f.primaryPhone!.isNotEmpty ? ' · ${f.primaryPhone}' : ''}'),
                      trailing: PopupMenuButton<String>(onSelected:(v){if(v=='open')Navigator.of(context).push(MaterialPageRoute(builder:(_)=>FamilyDetailScreen(family:f)));if(v=='edit')_edit(context,ref,f);},itemBuilder:(_)=>const [PopupMenuItem(value:'open',child:Text('Ouvrir')),PopupMenuItem(value:'edit',child:Text('Modifier'))]),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FamilyDetailScreen(family: f))),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
    );
  }
}
