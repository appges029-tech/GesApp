import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';

class RecurringExpensesScreen extends ConsumerStatefulWidget {
  const RecurringExpensesScreen({super.key});
  @override
  ConsumerState<RecurringExpensesScreen> createState() => _RecurringExpensesScreenState();
}

class _RecurringExpensesScreenState extends ConsumerState<RecurringExpensesScreen> {
  List<Map<String,Object?>> _items=const[];
  bool _loading=true;
  @override void initState(){super.initState();Future.microtask(_load);}
  Future<void> _load() async {setState(()=>_loading=true);final rows=await ref.read(expenseRepositoryProvider).recurringTemplates(includeInactive:true);if(mounted)setState((){_items=rows;_loading=false;});}

  Future<void> _edit([Map<String,Object?>? item]) async {
    final repo=ref.read(expenseRepositoryProvider);
    final categories=await repo.categories();
    final finance=ref.read(financeRepositoryProvider);
    final methods=await finance.paymentMethods();
    final accounts=await finance.cashAccounts();
    if(!mounted||categories.isEmpty)return;
    final name=TextEditingController(text:item?['name'] as String? ?? '');
    final amount=TextEditingController(text:item==null?'':'${item['amount']}');
    final beneficiary=TextEditingController(text:item?['beneficiary'] as String? ?? '');
    final description=TextEditingController(text:item?['description'] as String? ?? '');
    String categoryId=item?['category_id'] as String? ?? categories.first.id;
    String frequency=item?['frequency'] as String? ?? 'monthly';
    int day=item?['day_of_month'] as int? ?? 5;
    String? method=item?['payment_method'] as String?;
    String? accountId=item?['cash_account_id'] as String?;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(
      title:Text(item==null?'Nouveau modèle récurrent':'Modifier le modèle'),
      content:ResponsiveDialogContent(maxWidth:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Nom *')),const SizedBox(height:8),
        DropdownButtonFormField<String>(initialValue:categoryId,decoration:const InputDecoration(labelText:'Catégorie'),items:categories.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name))).toList(),onChanged:(v){if(v!=null)setD(()=>categoryId=v);}),const SizedBox(height:8),
        TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Montant *')),const SizedBox(height:8),
        TextField(controller:beneficiary,decoration:const InputDecoration(labelText:'Bénéficiaire')),const SizedBox(height:8),
        TextField(controller:description,decoration:const InputDecoration(labelText:'Description')),const SizedBox(height:8),
        DropdownButtonFormField<String>(initialValue:frequency,decoration:const InputDecoration(labelText:'Fréquence'),items:const [DropdownMenuItem(value:'monthly',child:Text('Mensuelle')),DropdownMenuItem(value:'quarterly',child:Text('Trimestrielle')),DropdownMenuItem(value:'annual',child:Text('Annuelle'))],onChanged:(v){if(v!=null)setD(()=>frequency=v);}),const SizedBox(height:8),
        DropdownButtonFormField<int>(initialValue:day,decoration:const InputDecoration(labelText:'Jour prévu'),items:List.generate(28,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))),onChanged:(v){if(v!=null)setD(()=>day=v);}),const SizedBox(height:8),
        DropdownButtonFormField<String?>(initialValue:method,decoration:const InputDecoration(labelText:'Moyen de paiement'),items:[const DropdownMenuItem<String?>(value:null,child:Text('À choisir lors de la saisie')), ...methods.map((m)=>DropdownMenuItem<String?>(value:m['name'] as String,child:Text(m['name'] as String)))],onChanged:(v)=>setD(()=>method=v)),const SizedBox(height:8),
        DropdownButtonFormField<String?>(initialValue:accountId,decoration:const InputDecoration(labelText:'Compte / caisse'),items:[const DropdownMenuItem<String?>(value:null,child:Text('À choisir lors de la saisie')), ...accounts.map((a)=>DropdownMenuItem<String?>(value:a['id'] as String,child:Text(a['name'] as String)))],onChanged:(v)=>setD(()=>accountId=v)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Enregistrer'))],
    )));
    final parsed=int.tryParse(amount.text.replaceAll(RegExp(r'\D'),''))??0;
    final n=name.text.trim(),b=beneficiary.text.trim(),d=description.text.trim();
    name.dispose();amount.dispose();beneficiary.dispose();description.dispose();
    if(ok!=true||n.isEmpty||parsed<=0)return;
    final existingDue = item?['next_due_at'] == null ? null : DateTime.tryParse(item!['next_due_at'] as String);
    final scheduleChanged = item != null &&
        (item['frequency'] != frequency || (item['day_of_month'] as int? ?? 1) != day);
    await repo.saveRecurringTemplate(
      id: item?['id'] as String?,
      name: n,
      categoryId: categoryId,
      amount: parsed,
      beneficiary: b.isEmpty ? null : b,
      description: d.isEmpty ? null : d,
      paymentMethod: method,
      cashAccountId: accountId,
      frequency: frequency,
      dayOfMonth: day,
      nextDueAt: scheduleChanged ? null : existingDue,
      active: item == null ? true : (item['active'] as int? ?? 1) == 1,
    );
    await _load();ref.invalidate(auditEntriesProvider);
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Dépenses récurrentes')),
    floatingActionButton:OperatorSession.isAdmin?null:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('Modèle')),
    body:_loading?const Center(child:CircularProgressIndicator()):_items.isEmpty?const Center(child:Text('Aucun modèle récurrent.')):ListView.separated(padding:const EdgeInsets.all(16).copyWith(bottom:90),itemCount:_items.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final x=_items[i];final active=x['active']==1;return Card(child:ListTile(
      leading:Icon(active?Icons.repeat_rounded:Icons.pause_circle_outline),
      title:Text(x['name'] as String,style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:Text('${x['category_name']} · ${formatXaf(x['amount'] as int)} · prochaine ${('${x['next_due_at']}').split('T').first}${active?'':' · désactivé'}'),
      onTap:OperatorSession.isAdmin?null:()=>_edit(x),
      trailing:OperatorSession.isAdmin?null:PopupMenuButton<String>(onSelected:(v)async{if(v=='generate'){await ref.read(expenseRepositoryProvider).createExpenseFromRecurringTemplate(x['id'] as String);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Demande de dépense créée.')));}else{await ref.read(expenseRepositoryProvider).setRecurringTemplateActive(x['id'] as String,!active);}await _load();},itemBuilder:(_)=>[if(active)const PopupMenuItem(value:'generate',child:Text('Créer la demande')),PopupMenuItem(value:'toggle',child:Text(active?'Désactiver':'Réactiver'))]),
    ));}),
  );
}
