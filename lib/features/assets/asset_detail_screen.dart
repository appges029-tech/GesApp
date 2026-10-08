import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';
import '../../services/asset_document_service.dart';
import 'asset_form_screen.dart';

class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.assetId});
  final String assetId;
  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  int _refresh = 0;

  Future<void> _edit() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AssetFormScreen(assetId: widget.assetId)));
    if (mounted) setState(() => _refresh++);
  }

  Future<void> _move() async {
    final repo = ref.read(assetRepositoryProvider);
    final locations = await repo.locations();
    final employees = await repo.employeeOptions();
    if (!mounted) return;
    String? locationId;
    String? employeeId;
    String type = 'transfer';
    final reason = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: const Text('Affecter / déplacer le bien'),
      content: ResponsiveDialogContent(maxWidth: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(isExpanded:true,initialValue: type, decoration: const InputDecoration(labelText: 'Type de mouvement'), items: const [
          DropdownMenuItem(value:'transfer',child:Text('Transfert')), DropdownMenuItem(value:'assignment',child:Text('Affectation')), DropdownMenuItem(value:'loan',child:Text('Prêt')), DropdownMenuItem(value:'return',child:Text('Retour')),
        ], onChanged:(v)=>setLocal(()=>type=v??'transfer')),
        const SizedBox(height:10),
        DropdownButtonFormField<String?>(isExpanded:true,initialValue: locationId, decoration: const InputDecoration(labelText: 'Nouvelle localisation'), items: [const DropdownMenuItem<String?>(value:null,child:Text('Aucune')),...locations.map((l)=>DropdownMenuItem<String?>(value:l.id,child:Text(l.name,maxLines:1,overflow:TextOverflow.ellipsis)))], onChanged:(v)=>setLocal(()=>locationId=v)),
        const SizedBox(height:10),
        DropdownButtonFormField<String?>(isExpanded:true,initialValue: employeeId, decoration: const InputDecoration(labelText: 'Responsable / employé'), items: [const DropdownMenuItem<String?>(value:null,child:Text('Aucun')),...employees.map((e)=>DropdownMenuItem<String?>(value:e['id'] as String,child:Text('${e['name']}',maxLines:1,overflow:TextOverflow.ellipsis)))], onChanged:(v)=>setLocal(()=>employeeId=v)),
        const SizedBox(height:10),
        TextField(controller: reason, decoration: const InputDecoration(labelText:'Motif / observation')),
      ])),
      actions: [TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Valider'))],
    )));
    if (ok == true) {
      await repo.moveAsset(assetId: widget.assetId, toLocationId: locationId, toEmployeeId: employeeId, movementType: type, reason: reason.text);
      if (mounted) setState(() => _refresh++);
    }
    reason.dispose();
  }

  Future<void> _addDocument() async {
    final type = TextEditingController(text: 'Justificatif / document');
    final confirmed = await showDialog<bool>(context: context, builder: (context)=>AlertDialog(
      title:const Text('Ajouter un document'), content:TextField(controller:type,decoration:const InputDecoration(labelText:'Type de document')),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Choisir le fichier'))],
    ));
    if(confirmed==true){
      final path=await AssetDocumentService().pickAndStore(widget.assetId);
      if(path!=null){await ref.read(assetRepositoryProvider).addDocument(assetId:widget.assetId,documentType:type.text.trim().isEmpty?'Document':type.text,filePath:path);if(mounted)setState(()=>_refresh++);}
    }
    type.dispose();
  }

  Future<void> _disposeAsset() async {
    final accounts=await ref.read(cashRepositoryProvider).accounts();
    if(!mounted)return;
    String type='reform';String? cashAccountId=accounts.isEmpty?null:'${accounts.first['id']}';
    final reason=TextEditingController();final amount=TextEditingController(text:'0');final reference=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(
      title:const Text('Sortir du patrimoine'),
      content:ResponsiveDialogContent(maxWidth:430,child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(isExpanded:true,initialValue:type,decoration:const InputDecoration(labelText:'Mode de sortie'),items:const[
          DropdownMenuItem(value:'sale',child:Text('Vente')),DropdownMenuItem(value:'donation',child:Text('Don')),DropdownMenuItem(value:'reform',child:Text('Réforme / mise au rebut')),DropdownMenuItem(value:'loss',child:Text('Perte')),DropdownMenuItem(value:'destruction',child:Text('Destruction')),
        ],onChanged:(v)=>setLocal(()=>type=v??'reform')),
        if(type=='sale')...[const SizedBox(height:10),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Montant encaissé (XAF)')),const SizedBox(height:10),DropdownButtonFormField<String>(isExpanded:true,initialValue:cashAccountId,decoration:const InputDecoration(labelText:'Compte d’encaissement'),items:accounts.map((a)=>DropdownMenuItem(value:'${a['id']}',child:Text('${a['name']}',maxLines:1,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setLocal(()=>cashAccountId=v)),const SizedBox(height:10),TextField(controller:reference,decoration:const InputDecoration(labelText:'Référence de cession'))],
        const SizedBox(height:10),TextField(controller:reason,maxLines:2,decoration:const InputDecoration(labelText:'Motif')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Confirmer'))],
    )));
    if(ok==true){try{await ref.read(assetRepositoryProvider).disposeAsset(assetId:widget.assetId,disposalType:type,disposalDate:DateTime.now(),saleAmount:type=='sale'?(int.tryParse(amount.text)??0):0,cashAccountId:type=='sale'?cashAccountId:null,reference:reference.text,reason:reason.text);if(mounted)setState(()=>_refresh++);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
    reason.dispose();amount.dispose();reference.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo=ref.read(assetRepositoryProvider);
    return Scaffold(
      appBar:AppBar(title:const Text('Fiche patrimoine'),actions:[if(!OperatorSession.isReadOnly)...[IconButton(onPressed:_edit,icon:const Icon(Icons.edit_outlined)),PopupMenuButton<String>(onSelected:(v){if(v=='move')_move();if(v=='doc')_addDocument();if(v=='dispose')_disposeAsset();},itemBuilder:(_)=>const[
        PopupMenuItem(value:'move',child:Text('Affecter / déplacer')),PopupMenuItem(value:'doc',child:Text('Ajouter un document')),PopupMenuDivider(),PopupMenuItem(value:'dispose',child:Text('Sortir du patrimoine')),
      ])]]),
      body:FutureBuilder<List<Object?>>(
        key:ValueKey(_refresh),
        future:Future.wait<Object?>([repo.assetDetails(widget.assetId),repo.movements(widget.assetId),repo.documents(widget.assetId),repo.maintenance(assetId:widget.assetId)]),
        builder:(context,snapshot){
          if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
          final row=snapshot.data![0] as Map<String,Object?>?;if(row==null)return const Center(child:Text('Bien introuvable.'));
          final movements=snapshot.data![1] as List<Map<String,Object?>>;final docs=snapshot.data![2] as List<Map<String,Object?>>;final maintenance=snapshot.data![3] as List;
          return ListView(padding:const EdgeInsets.all(16),children:[
            Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('${row['asset_number']} · ${row['name']}',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
              const SizedBox(height:8),Text('${row['category_name']} · ${row['brand']??''} ${row['model']??''}'.trim()),
              Text('N° série : ${row['serial_number']??'—'}'),Text('Localisation : ${row['location_name']??'Non localisé'}'),Text('Responsable : ${row['employee_name']??'Aucun'}'),
              Text('État : ${row['condition']} · Statut : ${row['status']}'),Text('Valeur d’acquisition : ${formatXaf((row['acquisition_value'] as num).toInt())}'),
              if(row['warranty_end_date']!=null)Text('Fin de garantie : ${('${row['warranty_end_date']}').split('T').first}'),
            ]))),
            const SizedBox(height:14),
            Text('Documents (${docs.length})',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
            if(docs.isEmpty)const Card(child:ListTile(title:Text('Aucun document joint.'))),
            ...docs.map((d)=>Card(child:ListTile(leading:const Icon(Icons.description_outlined),title:Text('${d['document_type']}'),subtitle:Text('${d['added_at']}'.split('T').first)))),
            const SizedBox(height:14),
            Text('Maintenance (${maintenance.length})',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
            if(maintenance.isEmpty)const Card(child:ListTile(title:Text('Aucune intervention enregistrée.'))),
            ...maintenance.take(5).map((m)=>Card(child:ListTile(leading:const Icon(Icons.build_outlined),title:Text('${m.type} · ${m.status}'),subtitle:Text('${m.provider??'Prestataire non renseigné'} · ${formatXaf(m.cost)}')))),
            const SizedBox(height:14),
            Text('Historique des mouvements',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
            if(movements.isEmpty)const Card(child:ListTile(title:Text('Aucun mouvement.'))),
            ...movements.map((m)=>Card(child:ListTile(leading:const Icon(Icons.swap_horiz),title:Text('${m['movement_type']} · ${('${m['moved_at']}').split('T').first}'),subtitle:Text('${m['from_location']??'—'} → ${m['to_location']??'—'}${m['to_employee']==null?'':' · ${m['to_employee']}'}')))),
          ]);
        },
      ),
    );
  }
}
