import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/layout/responsive_layout.dart';
import '../../data/models/asset.dart';
import '../../services/asset_document_service.dart';

class AssetFormScreen extends ConsumerStatefulWidget {
  const AssetFormScreen({super.key, this.assetId});
  final String? assetId;
  @override
  ConsumerState<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends ConsumerState<AssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _value = TextEditingController(text: '0');
  final _supplier = TextEditingController();
  final _notes = TextEditingController();
  String? _categoryId;
  String? _locationId;
  String? _employeeId;
  String _condition = 'good';
  String _status = 'in_service';
  String _acquisitionMethod = 'purchase';
  DateTime? _acquisitionDate;
  DateTime? _warrantyEnd;
  String? _photoPath;
  String? _purchaseProofPath;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (widget.assetId != null) {
      final row = await ref.read(assetRepositoryProvider).assetDetails(widget.assetId!);
      if (row != null) {
        _name.text = '${row['name'] ?? ''}';
        _number.text = '${row['asset_number'] ?? ''}';
        _brand.text = '${row['brand'] ?? ''}';
        _model.text = '${row['model'] ?? ''}';
        _serial.text = '${row['serial_number'] ?? ''}';
        _value.text = '${row['acquisition_value'] ?? 0}';
        _supplier.text = '${row['supplier'] ?? ''}';
        _notes.text = '${row['notes'] ?? ''}';
        _categoryId = row['category_id'] as String?;
        _locationId = row['current_location_id'] as String?;
        _employeeId = row['current_employee_id'] as String?;
        _condition = '${row['condition'] ?? 'good'}';
        _status = '${row['status'] ?? 'in_service'}' == 'retired' ? 'out_of_service' : '${row['status'] ?? 'in_service'}';
        _acquisitionMethod = '${row['acquisition_method'] ?? 'purchase'}';
        _acquisitionDate = DateTime.tryParse('${row['acquisition_date'] ?? ''}');
        _warrantyEnd = DateTime.tryParse('${row['warranty_end_date'] ?? ''}');
        _photoPath = row['photo_path'] as String?;
        _purchaseProofPath = row['purchase_proof_path'] as String?;
      }
    } else {
      _number.text = await ref.read(assetRepositoryProvider).nextAssetNumber();
      _acquisitionDate = DateTime.now();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_name,_number,_brand,_model,_serial,_value,_supplier,_notes]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickDate(bool warranty) async {
    final initial = warranty ? (_warrantyEnd ?? DateTime.now()) : (_acquisitionDate ?? DateTime.now());
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1950), lastDate: DateTime(2100));
    if (picked != null) setState(() { if (warranty) _warrantyEnd = picked; else _acquisitionDate = picked; });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choisissez une catégorie.'))); return; }
    setState(() => _saving = true);
    try {
      await ref.read(assetRepositoryProvider).saveAsset(
        id: widget.assetId,
        name: _name.text,
        categoryId: _categoryId!,
        assetNumber: _number.text,
        brand: _brand.text,
        model: _model.text,
        serialNumber: _serial.text,
        acquisitionDate: _acquisitionDate,
        acquisitionValue: int.tryParse(_value.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        acquisitionMethod: _acquisitionMethod,
        supplier: _supplier.text,
        locationId: _locationId,
        employeeId: _employeeId,
        condition: _condition,
        status: _status,
        warrantyEndDate: _warrantyEnd,
        photoPath: _photoPath,
        purchaseProofPath: _purchaseProofPath,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final repo = ref.read(assetRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.assetId == null ? 'Nouveau bien' : 'Modifier le bien')),
      body: FutureBuilder<List<Object?>>(
        future: Future.wait<Object?>([repo.categories(), repo.locations(), repo.employeeOptions()]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final categories = snapshot.data![0] as List<AssetCategoryItem>;
          final locations = snapshot.data![1] as List<AssetLocationItem>;
          final employees = snapshot.data![2] as List<Map<String,Object?>>;
          if (_categoryId == null && categories.isNotEmpty) _categoryId = categories.first.id;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Form(
            key: _formKey,
            child: ListView(padding: ResponsiveLayout.pagePadding(context), children: [
              TextFormField(controller: _number, decoration: const InputDecoration(labelText: "Numéro d'inventaire"), validator: (v) => (v??'').trim().isEmpty ? 'Obligatoire' : null),
              const SizedBox(height: 10),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Désignation *'), validator: (v) => (v??'').trim().isEmpty ? 'Obligatoire' : null),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(initialValue: _categoryId, decoration: const InputDecoration(labelText: 'Catégorie *'), items: categories.map((c)=>DropdownMenuItem(value:c.id,child:Text(c.name))).toList(), onChanged: (v)=>setState(()=>_categoryId=v)),
              const SizedBox(height: 10),
              ResponsiveFormRow(children:[TextFormField(controller:_brand,decoration:const InputDecoration(labelText:'Marque')),TextFormField(controller:_model,decoration:const InputDecoration(labelText:'Modèle'))]),
              const SizedBox(height: 10),
              TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'Numéro de série')),
              const SizedBox(height: 10),
              ResponsiveFormRow(children:[
                TextFormField(controller:_value,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:"Valeur d'acquisition (XAF)")),
                DropdownButtonFormField<String>(initialValue:_acquisitionMethod,decoration:const InputDecoration(labelText:"Mode d'acquisition"),items:const[
                  DropdownMenuItem(value:'purchase',child:Text('Achat')),DropdownMenuItem(value:'donation',child:Text('Don')),DropdownMenuItem(value:'transfer',child:Text('Transfert')),DropdownMenuItem(value:'construction',child:Text('Construction')),DropdownMenuItem(value:'other',child:Text('Autre')),
                ],onChanged:(v)=>setState(()=>_acquisitionMethod=v??'purchase')),
              ]),
              const SizedBox(height:10),
              TextFormField(controller:_supplier,decoration:const InputDecoration(labelText:'Fournisseur / origine')),
              const SizedBox(height:10),
              Wrap(spacing:10,runSpacing:10,children:[
                OutlinedButton.icon(onPressed:()=>_pickDate(false),icon:const Icon(Icons.event),label:Text(_acquisitionDate==null?"Date d'acquisition":'Acquisition : ${_acquisitionDate!.day}/${_acquisitionDate!.month}/${_acquisitionDate!.year}')),
                OutlinedButton.icon(onPressed:()=>_pickDate(true),icon:const Icon(Icons.shield_outlined),label:Text(_warrantyEnd==null?'Fin de garantie':'Garantie : ${_warrantyEnd!.day}/${_warrantyEnd!.month}/${_warrantyEnd!.year}')),
              ]),
              const SizedBox(height:10),
              Wrap(spacing:10,runSpacing:10,children:[
                OutlinedButton.icon(onPressed:()async{final path=await AssetDocumentService().pickAndStore(widget.assetId??'draft-${DateTime.now().millisecondsSinceEpoch}',folder:'photos',allowedExtensions:const['jpg','jpeg','png']);if(path!=null&&mounted)setState(()=>_photoPath=path);},icon:const Icon(Icons.photo_camera),label:const Text('Ajouter une photo')),
                OutlinedButton.icon(onPressed:()async{final path=await AssetDocumentService().pickAndStore(widget.assetId??'draft-${DateTime.now().millisecondsSinceEpoch}',folder:'purchase',allowedExtensions:const['pdf']);if(path!=null&&mounted)setState(()=>_purchaseProofPath=path);},icon:const Icon(Icons.description),label:const Text("Justificatif d'achat")),
              ]),
              const SizedBox(height:10),
              DropdownButtonFormField<String?>(initialValue:_locationId,decoration:const InputDecoration(labelText:'Localisation'),items:[const DropdownMenuItem<String?>(value:null,child:Text('Non localisé')),...locations.map((l)=>DropdownMenuItem(value:l.id,child:Text(l.name))).toList()],onChanged:(v)=>setState(()=>_locationId=v)),
              const SizedBox(height:10),
              DropdownButtonFormField<String?>(initialValue:_employeeId,decoration:const InputDecoration(labelText:'Responsable / employé affecté'),items:[const DropdownMenuItem<String?>(value:null,child:Text('Non assigné')),...employees.map((e)=>DropdownMenuItem(value:e['id'] as String,child:Text('${e['first_name']} ${e['last_name']}'))).toList()],onChanged:(v)=>setState(()=>_employeeId=v)),
              const SizedBox(height:10),
              ResponsiveFormRow(children:[
                DropdownButtonFormField<String>(initialValue:_condition,decoration:const InputDecoration(labelText:'État'),items:const[
                  DropdownMenuItem(value:'new',child:Text('Neuf')),DropdownMenuItem(value:'good',child:Text('Bon')),DropdownMenuItem(value:'fair',child:Text('Moyen')),DropdownMenuItem(value:'repair',child:Text('À réparer')),DropdownMenuItem(value:'broken',child:Text('Cassé')),
                ],onChanged:(v)=>setState(()=>_condition=v??'good')),
                DropdownButtonFormField<String>(initialValue:_status,decoration:const InputDecoration(labelText:'Statut'),items:[
                  const DropdownMenuItem(value:'in_service',child:Text('En service')),const DropdownMenuItem(value:'stock',child:Text('En stock')),const DropdownMenuItem(value:'maintenance',child:Text('En maintenance')),const DropdownMenuItem(value:'out_of_service',child:Text('Hors service')),
                  if(_status=='missing') const DropdownMenuItem(value:'missing',child:Text('Manquant')),
                  if(_status=='disposed') const DropdownMenuItem(value:'disposed',child:Text('Sorti du patrimoine')),
                ],onChanged:_status=='disposed'?null:(v)=>setState(()=>_status=v??'in_service')),
              ]),
              const SizedBox(height:10),
              TextFormField(controller:_notes,maxLines:3,decoration:const InputDecoration(labelText:'Observations')),
              const SizedBox(height:20),
              FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save),label:const Text('Enregistrer le bien')),
            ]),
          ),
            ),
          );
        },
      ),
    );
  }
}
