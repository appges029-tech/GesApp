import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/models/asset.dart';
import '../../core/layout/responsive_layout.dart';

class AssetConfigurationScreen extends ConsumerStatefulWidget {
  const AssetConfigurationScreen({super.key});
  @override
  ConsumerState<AssetConfigurationScreen> createState()=>_AssetConfigurationScreenState();
}
class _AssetConfigurationScreenState extends ConsumerState<AssetConfigurationScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs=TabController(length:2,vsync:this);
  int _refresh=0;
  @override void dispose(){_tabs.dispose();super.dispose();}

  Future<void> _category([AssetCategoryItem? item]) async {
    final name=TextEditingController(text:item?.name??'');final desc=TextEditingController(text:item?.description??'');var active=item?.active??true;
    final ok=await showDialog<bool>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(title:Text(item==null?'Nouvelle catégorie':'Modifier la catégorie'),content:ResponsiveDialogContent(maxWidth:440,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Nom')),const SizedBox(height:10),TextField(controller:desc,decoration:const InputDecoration(labelText:'Description')),SwitchListTile(value:active,onChanged:(v)=>setLocal(()=>active=v),title:const Text('Active'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Enregistrer'))])));
    if(ok==true){await ref.read(assetRepositoryProvider).saveCategory(id:item?.id,name:name.text,description:desc.text,active:active);if(mounted)setState(()=>_refresh++);}name.dispose();desc.dispose();
  }

  Future<void> _location(List<AssetLocationItem> all,[AssetLocationItem? item]) async {
    final name=TextEditingController(text:item?.name??'');final desc=TextEditingController(text:item?.description??'');var type=item?.type??'room';String? parent=item?.parentId;var active=item?.active??true;
    final ok=await showDialog<bool>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(title:Text(item==null?'Nouvelle localisation':'Modifier la localisation'),content:ResponsiveDialogContent(maxWidth:460,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Nom')),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'Type'),items:const [DropdownMenuItem(value:'site',child:Text('Site')),DropdownMenuItem(value:'building',child:Text('Bâtiment')),DropdownMenuItem(value:'floor',child:Text('Étage')),DropdownMenuItem(value:'room',child:Text('Salle / local')),DropdownMenuItem(value:'store',child:Text('Dépôt / magasin'))],onChanged:(v)=>setLocal(()=>type=v??'room')),const SizedBox(height:10),DropdownButtonFormField<String?>(initialValue:parent,decoration:const InputDecoration(labelText:'Parent'),items:[const DropdownMenuItem<String?>(value:null,child:Text('Aucun')),...all.where((l)=>l.id!=item?.id).map((l)=>DropdownMenuItem<String?>(value:l.id,child:Text(l.name)))],onChanged:(v)=>setLocal(()=>parent=v)),const SizedBox(height:10),TextField(controller:desc,decoration:const InputDecoration(labelText:'Description')),SwitchListTile(value:active,onChanged:(v)=>setLocal(()=>active=v),title:const Text('Active'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Enregistrer'))])));
    if(ok==true){await ref.read(assetRepositoryProvider).saveLocation(id:item?.id,name:name.text,type:type,parentId:parent,description:desc.text,active:active);if(mounted)setState(()=>_refresh++);}name.dispose();desc.dispose();
  }

  @override Widget build(BuildContext context){final repo=ref.read(assetRepositoryProvider);return Scaffold(appBar:AppBar(title:const Text('Configuration du patrimoine'),bottom:TabBar(controller:_tabs,tabs:const[Tab(text:'Catégories'),Tab(text:'Localisations')])),body:FutureBuilder<List<Object?>>(key:ValueKey(_refresh),future:Future.wait<Object?>([repo.categories(activeOnly:false),repo.locations(activeOnly:false)]),builder:(context,snap){if(!snap.hasData)return const Center(child:CircularProgressIndicator());final cats=snap.data![0] as List<AssetCategoryItem>;final locs=snap.data![1] as List<AssetLocationItem>;return TabBarView(controller:_tabs,children:[
    _ListSection(onAdd:()=>_category(),children:cats.map((c)=>Card(child:ListTile(leading:Icon(c.active?Icons.category_outlined:Icons.block),title:Text(c.name),subtitle:Text(c.description??''),trailing:const Icon(Icons.edit_outlined),onTap:()=>_category(c)))).toList()),
    _ListSection(onAdd:()=>_location(locs),children:locs.map((l)=>Card(child:ListTile(leading:const Icon(Icons.place_outlined),title:Text(l.name),subtitle:Text('${l.type}${l.parentName==null?'':' · ${l.parentName}'}${l.active?'':' · Désactivée'}'),trailing:const Icon(Icons.edit_outlined),onTap:()=>_location(locs,l)))).toList()),
  ]); }));}
}
class _ListSection extends StatelessWidget{const _ListSection({required this.children,required this.onAdd});final List<Widget> children;final VoidCallback onAdd;@override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:onAdd,icon:const Icon(Icons.add),label:const Text('Ajouter'))),const SizedBox(height:10),...children]);}
