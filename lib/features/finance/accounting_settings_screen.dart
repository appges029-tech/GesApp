import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/repository_providers.dart';

class AccountingSettingsScreen extends ConsumerStatefulWidget { const AccountingSettingsScreen({super.key}); @override ConsumerState<AccountingSettingsScreen> createState()=>_AccountingSettingsScreenState(); }
class _AccountingSettingsScreenState extends ConsumerState<AccountingSettingsScreen> {
  int _refresh=0;
  static const labels={
    'student_receivable_account':'Créances familles / élèves',
    'school_revenue_account':'Produits scolaires',
    'supplier_payable_account':'Dettes fournisseurs',
    'default_cash_account':'Caisse espèces',
    'default_bank_account':'Banque',
    'default_mobile_account':'Mobile Money',
  };
  @override Widget build(BuildContext context){final repo=ref.read(accountingRepositoryProvider);return Scaffold(appBar:AppBar(title:const Text('Paramétrage comptable')),body:FutureBuilder<List<Object>>(key:ValueKey(_refresh),future:Future.wait([repo.accounts(),repo.settings()]),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final accounts=s.data![0] as List<Map<String,Object?>>,settings=s.data![1] as Map<String,String>;return ListView(padding:const EdgeInsets.all(12),children:labels.entries.map((e){final current=settings[e.key];return Card(child:DropdownButtonFormField<String>(value:accounts.any((a)=>'${a['code']}'==current)?current:null,isExpanded:true,decoration:InputDecoration(labelText:e.value,contentPadding:const EdgeInsets.all(16)),items:accounts.map((a)=>DropdownMenuItem(value:'${a['code']}',child:Text('${a['code']} · ${a['name']}'))).toList(),onChanged:(v)async{if(v==null)return;try{await repo.updateSetting(e.key,v);setState(()=>_refresh++);}catch(err){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$err')));}}));}).toList());}));}
}
