import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/pdf_output_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../services/excel_export_service.dart';
import '../../services/report_pdf_service.dart';
import '../../services/document_number_service.dart';
import '../../services/document_identity.dart';

class AssetReportsScreen extends ConsumerStatefulWidget {
  const AssetReportsScreen({super.key});
  @override
  ConsumerState<AssetReportsScreen> createState() => _AssetReportsScreenState();
}

class _AssetReportsScreenState extends ConsumerState<AssetReportsScreen> {
  Future<void> _export(String title, List<Map<String,Object?>> rows, bool pdf) async {
    final data=rows.map((r)=>['${r['label']}','${r['count']}',formatXaf(((r['total_value'] as num?)??0).toInt())]).toList();
    if(pdf){
      final establishment=await ref.read(establishmentProvider.future);
      final identity=await DocumentIdentity.fromEstablishment(establishment);
      final registry=DocumentNumberService();
      final reference=await registry.getOrCreate(type:'RPA',entityId:'$title:${DateTime.now().microsecondsSinceEpoch}');
      final bytes=await ReportPdfService().table(title:title,subtitle:'Rapport patrimoine',headers:const ['Libellé','Nombre','Valeur d’acquisition'],rows:data,identity:identity,reference:reference);
      await registry.recordFingerprint(reference:reference,bytes:bytes);
      await outputPdf(bytes,fileName:'${title.replaceAll(' ','_')}_$reference.pdf');
    }else{
      await ExcelExportService().export(fileName:title,headers:const ['Libellé','Nombre','Valeur d’acquisition'],rows:data);
    }
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(pdf?'PDF généré.':'Export Excel généré.')));
  }

  @override
  Widget build(BuildContext context) {
    final repo=ref.read(assetRepositoryProvider);
    return Scaffold(
      appBar:AppBar(title:const Text('Rapports patrimoniaux')),
      body:FutureBuilder<List<Object?>>(
        future:Future.wait<Object?>([repo.reportByCategory(),repo.reportByLocation(),repo.reportByStatus()]),
        builder:(context,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final category=s.data![0] as List<Map<String,Object?>>;
          final location=s.data![1] as List<Map<String,Object?>>;
          final status=s.data![2] as List<Map<String,Object?>>;
          return ListView(padding:const EdgeInsets.all(16),children:[
            _Section(title:'Patrimoine par catégorie',rows:category,onPdf:()=>_export('Patrimoine par catégorie',category,true),onExcel:()=>_export('Patrimoine par catégorie',category,false)),
            const SizedBox(height:16),
            _Section(title:'Patrimoine par localisation',rows:location,onPdf:()=>_export('Patrimoine par localisation',location,true),onExcel:()=>_export('Patrimoine par localisation',location,false)),
            const SizedBox(height:16),
            _Section(title:'Patrimoine par statut',rows:status,onPdf:()=>_export('Patrimoine par statut',status,true),onExcel:()=>_export('Patrimoine par statut',status,false)),
          ]);
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title,required this.rows,required this.onPdf,required this.onExcel});
  final String title;
  final List<Map<String,Object?>> rows;
  final VoidCallback onPdf,onExcel;
  @override
  Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text(title,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900))),IconButton(onPressed:onPdf,tooltip:'PDF',icon:const Icon(Icons.picture_as_pdf_outlined)),IconButton(onPressed:onExcel,tooltip:'Excel',icon:const Icon(Icons.table_view_outlined))]),
    const SizedBox(height:8),
    Card(child:Column(children:rows.isEmpty?[const ListTile(title:Text('Aucune donnée.'))]:rows.map((r)=>ListTile(title:Text('${r['label']}'),subtitle:Text('${r['count']} bien(s)'),trailing:Text(formatXaf(((r['total_value'] as num?)??0).toInt()),style:const TextStyle(fontWeight:FontWeight.w800)))).toList())),
  ]);
}
