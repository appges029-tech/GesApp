import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/platform/pdf_output_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../services/excel_export_service.dart';
import '../../services/report_pdf_service.dart';
import '../../services/document_number_service.dart';
import '../../services/document_identity.dart';
import 'manual_journal_entry_screen.dart';
import 'supplier_accounting_screen.dart';
import 'bank_reconciliation_screen.dart';
import 'accounting_settings_screen.dart';

enum _AccountingView { journal, ledger, balance, accounts }

class AccountingScreen extends ConsumerStatefulWidget {
  const AccountingScreen({super.key});
  @override
  ConsumerState<AccountingScreen> createState()=>_AccountingScreenState();
}

class _AccountingScreenState extends ConsumerState<AccountingScreen> {
  late DateTime _start;
  late DateTime _end;
  _AccountingView _view=_AccountingView.journal;
  int _refresh=0;

  @override
  void initState(){super.initState();final now=DateTime.now();_start=DateTime(now.year,1,1);_end=DateTime(now.year,now.month,now.day);}
  DateTime get _exclusiveEnd=>DateTime(_end.year,_end.month,_end.day+1);
  String _date(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  String get _period=>'Du ${_date(_start)} au ${_date(_end)}';

  Future<void> _pickRange()async{final value=await showDateRangePicker(context:context,firstDate:DateTime(2000),lastDate:DateTime(2100),initialDateRange:DateTimeRange(start:_start,end:_end),helpText:'Période comptable',saveText:'Appliquer');if(value!=null&&mounted)setState((){_start=value.start;_end=value.end;_refresh++;});}

  Future<List<Map<String,Object?>>> _load()async{final repo=ref.read(accountingRepositoryProvider);final rows=await switch(_view){_AccountingView.journal=>repo.journal(start:_start,end:_exclusiveEnd),_AccountingView.ledger=>repo.generalLedger(start:_start,end:_exclusiveEnd),_AccountingView.balance=>repo.trialBalance(start:_start,end:_exclusiveEnd),_AccountingView.accounts=>repo.accounts()};if(_view==_AccountingView.balance&&rows.isNotEmpty){final debit=rows.fold<int>(0,(sum,r)=>sum+((r['debit'] as num?)?.toInt()??0));final credit=rows.fold<int>(0,(sum,r)=>sum+((r['credit'] as num?)?.toInt()??0));return [...rows,{'code':'TOTAL','name':'TOTAL GÉNÉRAL','debit':debit,'credit':credit,'balance':debit-credit}];}return rows;}

  String get _title=>switch(_view){_AccountingView.journal=>'Livre-journal',_AccountingView.ledger=>'Grand-livre',_AccountingView.balance=>'Balance générale',_AccountingView.accounts=>'Plan comptable simplifié'};
  List<String> get _headers=>switch(_view){_AccountingView.journal=>const['Date','Journal','Pièce','Compte','Intitulé','Débit','Crédit'],_AccountingView.ledger=>const['Compte','Intitulé','Date','Journal','Pièce','Débit','Crédit','Solde'],_AccountingView.balance=>const['Compte','Intitulé','Mouv. débit','Mouv. crédit','Solde débiteur','Solde créditeur'],_AccountingView.accounts=>const['Compte','Intitulé','Classe','Type']};

  List<String> _row(Map<String,Object?> r)=>switch(_view){
    _AccountingView.journal=>['${r['entry_date']}'.split('T').first,'${r['journal_code']}','${r['reference']}','${r['account_code']}','${r['account_name']}',formatXaf((r['debit'] as num?)??0),formatXaf((r['credit'] as num?)??0)],
    _AccountingView.ledger=>['${r['account_code']}','${r['account_name']}','${r['entry_date']}'.split('T').first,'${r['journal_code']}','${r['reference']}',formatXaf((r['debit'] as num?)??0),formatXaf((r['credit'] as num?)??0),formatXaf((r['balance'] as num?)??0)],
    _AccountingView.balance=>['${r['code']}','${r['name']}',formatXaf((r['debit'] as num?)??0),formatXaf((r['credit'] as num?)??0),formatXaf(((r['balance'] as num?)??0)>0?(r['balance'] as num):0),formatXaf(((r['balance'] as num?)??0)<0?-(r['balance'] as num):0)],
    _AccountingView.accounts=>['${r['code']}','${r['name']}','${r['account_class']}','${r['account_type']}'],
  };

  Future<void> _export(List<Map<String,Object?>> rows,bool pdf)async{final data=rows.map(_row).toList();final subtitle=_view==_AccountingView.accounts?'Référentiel comptable GesApp':'Écritures équilibrées débit/crédit';if(pdf){final establishment=await ref.read(establishmentProvider.future);final identity=await DocumentIdentity.fromEstablishment(establishment);final registry=DocumentNumberService();final prefix=switch(_view){_AccountingView.journal=>'JRN',_AccountingView.ledger=>'GL',_AccountingView.balance=>'BAL',_AccountingView.accounts=>'PCA'};final reference=await registry.getOrCreate(type:prefix,entityId:'${_start.toIso8601String()}-${_end.toIso8601String()}-${DateTime.now().microsecondsSinceEpoch}');final bytes=await ReportPdfService().table(title:_title,subtitle:subtitle,headers:_headers,rows:data,pageFormat:PdfPageFormat.a4.landscape,identity:identity,reference:reference,periodLabel:_view==_AccountingView.accounts?null:_period);await registry.recordFingerprint(reference:reference,bytes:bytes);await outputPdf(bytes,fileName:'${_title.replaceAll(' ','_')}_$reference.pdf');}else{await ExcelExportService().export(fileName:_title,headers:_headers,rows:data);}if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(pdf?'PDF généré.':'Export Excel généré.')));}

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Comptabilité générale'),actions:[
      IconButton(tooltip:'Écriture manuelle',icon:const Icon(Icons.edit_note_outlined),onPressed:()async{final changed=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>const ManualJournalEntryScreen()));if(changed==true&&mounted)setState(()=>_refresh++);}),
      IconButton(tooltip:'Fournisseurs',icon:const Icon(Icons.local_shipping_outlined),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const SupplierAccountingScreen()))),
      IconButton(tooltip:'Rapprochement',icon:const Icon(Icons.account_balance_outlined),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const BankReconciliationScreen()))),
      IconButton(tooltip:'Paramétrage',icon:const Icon(Icons.tune_outlined),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const AccountingSettingsScreen()))),
    ]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,12,12,4),child:Column(children:[
        SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
          ChoiceChip(label:const Text('Journal'),selected:_view==_AccountingView.journal,onSelected:(_)=>setState((){_view=_AccountingView.journal;_refresh++;})),const SizedBox(width:6),
          ChoiceChip(label:const Text('Grand-livre'),selected:_view==_AccountingView.ledger,onSelected:(_)=>setState((){_view=_AccountingView.ledger;_refresh++;})),const SizedBox(width:6),
          ChoiceChip(label:const Text('Balance'),selected:_view==_AccountingView.balance,onSelected:(_)=>setState((){_view=_AccountingView.balance;_refresh++;})),const SizedBox(width:6),
          ChoiceChip(label:const Text('Plan comptable'),selected:_view==_AccountingView.accounts,onSelected:(_)=>setState((){_view=_AccountingView.accounts;_refresh++;})),
        ])),
        if(_view!=_AccountingView.accounts)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.date_range_outlined),title:Text(_period),trailing:const Icon(Icons.edit_calendar_outlined),onTap:_pickRange),
      ])),
      Expanded(child:FutureBuilder<List<Map<String,Object?>>>(key:ValueKey('$_view-$_refresh'),future:_load(),builder:(context,s){if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Chargement impossible : ${s.error}',textAlign:TextAlign.center)));if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!;return Column(children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Row(children:[Expanded(child:Text('$_title · ${rows.length} ligne(s)',style:const TextStyle(fontWeight:FontWeight.w800))),IconButton(tooltip:'PDF',onPressed:rows.isEmpty?null:()=>_export(rows,true),icon:const Icon(Icons.picture_as_pdf_outlined)),IconButton(tooltip:'Excel',onPressed:rows.isEmpty?null:()=>_export(rows,false),icon:const Icon(Icons.table_view_outlined))])),
        Expanded(child:rows.isEmpty?const Center(child:Text('Aucune écriture sur cette période.')):ResponsiveDataTable(headers:_headers,rows:rows.map(_row).toList())),
      ]);}))
    ]),
  );
}
