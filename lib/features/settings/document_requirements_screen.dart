import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/repositories/settings_repository.dart';

class DocumentRequirementsScreen extends ConsumerStatefulWidget {
  const DocumentRequirementsScreen({super.key});
  @override ConsumerState<DocumentRequirementsScreen> createState()=>_DocumentRequirementsScreenState();
}

class _DocumentRequirementsScreenState extends ConsumerState<DocumentRequirementsScreen>{
  List<DocumentRequirementSetting> _items=const[]; bool _loading=true;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {final items=await ref.read(settingsRepositoryProvider).documentRequirements();if(mounted)setState((){_items=items;_loading=false;});}
  Future<void> _edit([DocumentRequirementSetting? item]) async {
    final name=TextEditingController(text:item?.name??'');final desc=TextEditingController(text:item?.description??'');bool required=item?.required??true,active=item?.active??true;final order=TextEditingController(text:'${item?.sortOrder??(_items.length+1)*10}');
    final ok=await showDialog<bool>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setM)=>AlertDialog(title:Text(item==null?'Nouvelle pièce':'Modifier la pièce'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Nom de la pièce')),const SizedBox(height:10),TextField(controller:desc,maxLines:2,decoration:const InputDecoration(labelText:'Description')),const SizedBox(height:10),TextField(controller:order,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Ordre')),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Obligatoire'),value:required,onChanged:(v)=>setM(()=>required=v)),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Active'),value:active,onChanged:(v)=>setM(()=>active=v))])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Enregistrer'))])));
    if(ok==true){try{await ref.read(settingsRepositoryProvider).saveDocumentRequirement(id:item?.id,name:name.text,description:desc.text,required:required,active:active,sortOrder:int.tryParse(order.text)??0);await _load();ref.invalidate(auditEntriesProvider);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Pièces du dossier élève')),floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('Ajouter')),body:_loading?const Center(child:CircularProgressIndicator()):ListView.separated(padding:const EdgeInsets.all(16).copyWith(bottom:96),itemCount:_items.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final x=_items[i];return Card(child:ListTile(onTap:()=>_edit(x),leading:Icon(x.required?Icons.verified_outlined:Icons.description_outlined),title:Text(x.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${x.required?'Obligatoire':'Facultative'}${x.active?'':' · désactivée'}${(x.description??'').isEmpty?'':'\n${x.description}'}'),trailing:const Icon(Icons.edit_outlined)));}));
}
