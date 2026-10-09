import 'package:flutter/material.dart';
import '../../core/db/app_database.dart';
import '../../core/session/operator_session.dart';
import '../../services/annual_billing_service.dart';

class BillingCalendarScreen extends StatefulWidget {
  const BillingCalendarScreen({super.key});
  @override
  State<BillingCalendarScreen> createState() => _BillingCalendarScreenState();
}
class _BillingCalendarScreenState extends State<BillingCalendarScreen> {
  final repo = BillingCalendarRepository(AppDatabase.instance);
  late Future<BillingCalendarConfiguration> future;
  bool busy = false;
  @override
  void initState(){super.initState();refresh();}
  void refresh(){future=repo.load();if(mounted)setState((){});}
  String fmt(DateTime d)=>d.day.toString().padLeft(2,'0')+'/'
      +d.month.toString().padLeft(2,'0')+'/'+d.year.toString();
  void notify(String message) {
    if(mounted)ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content:Text(message)));
  }
  static const _monthNames = [
    'Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août',
    'Septembre','Octobre','Novembre','Décembre'
  ];

  Future<void> configureMonthly(BillingCalendarConfiguration data) async {
    if (busy) return;
    final old = await BillingCalendarRepository.readMonthlyDeadlines(
        AppDatabase.instance.db, data.yearId);
    if (!mounted) return;
    final selected = <String, DateTime?>{for (final e in old.entries) e.key:e.value};
    final first = DateTime(data.start.year, data.start.month);
    final last = DateTime(data.end.year, data.end.month);
    final months = <DateTime>[];
    for (var m=first; !m.isAfter(last); m=DateTime(m.year,m.month+1)) {
      months.add(m);
    }
    final confirmed = await showDialog<bool>(context: context,
      builder:(dialogContext)=>StatefulBuilder(builder:(context,update)=>
        AlertDialog(
          title:const Text('Dates limites mensuelles'),
          content:SizedBox(width:460,height:440,child:Column(children:[
            const Text('Sélectionnez uniquement les mois facturables. '
              'Pour chaque mois, choisissez sa date limite exacte.'),
            const SizedBox(height:10),
            Expanded(child:ListView(children: months.map((month) {
              final key=month.year.toString()+'-'+
                  month.month.toString().padLeft(2,'0');
              final chosen=selected.containsKey(key);
              final deadline=selected[key];
              return Column(children:[
                CheckboxListTile(
                  dense:true,controlAffinity:ListTileControlAffinity.leading,
                  value:chosen,
                  title:Text(_monthNames[month.month-1]+' '+month.year.toString()),
                  subtitle:Text(deadline==null?
                    'Date limite non choisie':fmt(deadline)),
                  onChanged:(value)=>update((){
                    if(value==true){selected[key]=null;}
                    else{selected.remove(key);}
                  }),
                ),
                if(chosen) Padding(
                  padding:const EdgeInsets.only(left:40,right:8,bottom:8),
                  child:OutlinedButton.icon(
                    icon:const Icon(Icons.event),
                    label:Text(deadline==null?'Choisir une date limite':
                        'Modifier : '+fmt(deadline)),
                    onPressed:() async {
                      final firstDate=month.isBefore(data.start)?data.start:month;
                      final lastOfMonth=DateTime(month.year,month.month+1,0);
                      final lastDate=lastOfMonth.isAfter(data.end)?
                          data.end:lastOfMonth;
                      final picked=await showDatePicker(context:context,
                        initialDate:deadline??firstDate,
                        firstDate:firstDate,lastDate:lastDate);
                      if(picked!=null)update(()=>selected[key]=picked);
                    },
                  ),
                ),
                const Divider(height:1),
              ]);
            }).toList())),
          ])),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(dialogContext,false),
              child:const Text('Annuler')),
            FilledButton(
              onPressed:selected.isNotEmpty &&
                  selected.values.every((v)=>v!=null)
                  ? ()=>Navigator.pop(dialogContext,true):null,
              child:const Text('Enregistrer le calendrier')),
          ],
        )));
    if (confirmed!=true || !mounted)return;
    setState(()=>busy=true);
    try {
      await repo.saveMonthlyDeadlines(
        selected.map((key,value)=>MapEntry(key,value!)));
      notify('Dates limites mensuelles enregistrées.');
      refresh();
    } catch(error) {
      notify('Dates limites refusées : '+error.toString());
    } finally {
      if(mounted)setState(()=>busy=false);
    }
  }

  Future<void> edit(BillingCalendarConfiguration data,
      Map<String,Object?> fee) async {
    var from=fee['start_date']==null?data.start:
        DateTime.parse(fee['start_date'] as String);
    var to=fee['end_date']==null?data.end:
        DateTime.parse(fee['end_date'] as String);
    var policy=(fee['admission_policy']??'current_period') as String;
    final day=TextEditingController(text:(fee['due_day']??10).toString());
    final grace=TextEditingController(text:(fee['grace_days']??0).toString());
    final accepted=await showDialog<bool>(context:context,
      builder:(d)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
        title:Text('Calendrier : '+(fee['fee_name'] as String)),
        content:SingleChildScrollView(child:Column(
          mainAxisSize:MainAxisSize.min,children:[
          Text('Année : '+data.label),
          ListTile(title:Text('Début : '+fmt(from)),onTap:()async{
            final v=await showDatePicker(context:ctx,
              initialDate:from,firstDate:data.start,lastDate:data.end);
            if(v!=null)setD(()=>from=v);
          }),
          ListTile(title:Text('Fin : '+fmt(to)),onTap:()async{
            final v=await showDatePicker(context:ctx,
              initialDate:to,firstDate:data.start,lastDate:data.end);
            if(v!=null)setD(()=>to=v);
          }),
          TextField(controller:day,keyboardType:TextInputType.number,
            decoration:const InputDecoration(
              labelText:'Jour limite du paiement (1 à 31)')),
          DropdownButtonFormField<String>(initialValue:policy,
            decoration:const InputDecoration(labelText:'Admission tardive'),
            items:const [
              DropdownMenuItem(value:'current_period',
                child:Text('Facturer la période en cours')),
              DropdownMenuItem(value:'next_period',
                child:Text('Commencer la période suivante')),
            ],onChanged:(v){if(v!=null)setD(()=>policy=v);}),
          TextField(controller:grace,keyboardType:TextInputType.number,
            decoration:const InputDecoration(
              labelText:'Délai après admission, en jours')),
          const Text('Les anciennes écritures financières seront conservées.'),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(d,false),
          child:const Text('Annuler')),
          FilledButton(onPressed:()=>Navigator.pop(d,true),
            child:const Text('Enregistrer'))],
      )));
    final paymentDay=int.tryParse(day.text.trim());
    final graceDays=int.tryParse(grace.text.trim());
    day.dispose();grace.dispose();
    if(accepted!=true)return;
    if(paymentDay==null||graceDays==null){
      notify('Jour ou délai invalide.');return;
    }
    setState(()=>busy=true);
    try{
      await repo.saveRule(feeId:fee['fee_id'] as String,
        startDate:from,endDate:to,dueDay:paymentDay,
        graceDays:graceDays,admissionPolicy:policy);
      refresh();
    }catch(e){notify('Configuration refusée : '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> complete()async{
    setState(()=>busy=true);
    try{
      final count=await repo.pendingEnrollmentCount();
      if(!mounted)return;
      if(count==0){notify('Aucun dossier à compléter.');return;}
      final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
        title:const Text('Compléter les dossiers ?'),
        content:Text(count.toString()+' inscription(s) incomplètes. '
          'Les écritures existantes seront conservées. '
          'Les situations demandant une vérification humaine seront ignorées.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(d,false),
          child:const Text('Annuler')),
          FilledButton(onPressed:()=>Navigator.pop(d,true),
          child:const Text('Confirmer'))]));
      if(ok!=true)return;
      final result=await repo.completePending();
      notify(result.created.toString()+' nouvelles échéances ; '+
        result.completed.toString()+' dossiers complets ; '+
        result.pending.toString()+' encore incomplets ; '+
        result.errors.length.toString()+' erreurs.');
      refresh();
    }catch(e){notify('Réconciliation refusée : '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Calendrier de facturation')),
    body:FutureBuilder<BillingCalendarConfiguration>(future:future,
      builder:(context,snap){
        if(snap.hasError)return Center(child:Text(snap.error.toString()));
        if(!snap.hasData)return const Center(child:CircularProgressIndicator());
        final data=snap.data!;
        return ListView(padding:const EdgeInsets.all(16),children:[
          Card(child:ListTile(title:Text('Année '+data.label),
            subtitle:Text(fmt(data.start)+' – '+fmt(data.end)+'\n'
              'Configurez les dates avant les inscriptions.'))),
          Card(child:ListTile(
            leading:const Icon(Icons.calendar_month_outlined),
            title:const Text('Dates limites de chaque mois'),
            subtitle:const Text('Choisir les mois à payer et leurs dates '
              'butoirs, une fois pour toute l’année scolaire.'),
            trailing:const Icon(Icons.edit_calendar_outlined),
            onTap:busy||OperatorSession.isReadOnly?
              null:()=>configureMonthly(data),
          )),
          if(data.fees.isEmpty)const ListTile(
            title:Text('Aucun frais actif'),
            subtitle:Text('Créez les rubriques et leurs tarifs.')),
          ...data.fees.map((fee)=>Card(child:ListTile(
            leading:Icon(fee['rule_id']==null
              ?Icons.warning_amber_outlined:Icons.check_circle_outline),
            title:Text(fee['fee_name'] as String),
            subtitle:Text((fee['periodicity'] as String)+' · '+
              (fee['rule_id']==null?'Non configuré':
              fmt(DateTime.parse(fee['start_date'] as String))+' – '+
              fmt(DateTime.parse(fee['end_date'] as String))+
              ' · Jour '+fee['due_day'].toString())),
            onTap:busy||OperatorSession.isReadOnly?null:()=>edit(data,fee),
            trailing:const Icon(Icons.edit_calendar_outlined)))),
          FilledButton.icon(
            onPressed:busy||OperatorSession.isReadOnly?null:complete,
            icon:const Icon(Icons.fact_check_outlined),
            label:const Text('Analyser et compléter les dossiers')),
          if(OperatorSession.isReadOnly)
            const Text('Lecture seule : connectez un gestionnaire.'),
        ]);
      }),
  );
}
