import 'package:flutter/material.dart';
import '../core/api.dart';

class FundScreen extends StatefulWidget {
  const FundScreen({super.key,required this.api});
  final FamilyApi api;
  @override State<FundScreen> createState()=>_FundScreenState();
}
class _FundScreenState extends State<FundScreen> {
  late Future<List<dynamic>> data;
  @override void initState(){super.initState();refresh();}
  void refresh(){data=Future.wait([
    widget.api.get('/api/fund/summary'),widget.api.get('/api/fund/collections'),
    widget.api.get('/api/fund/expenses'),widget.api.get('/api/auth/me'),widget.api.get('/api/members'),
  ]);}
  void reload(){setState(refresh);}
  void notice(Object error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}
  Future<void> collect() async {
    final concept=TextEditingController(),amount=TextEditingController();
    try{
      final accept=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Nueva colecta familiar'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:concept,decoration:const InputDecoration(labelText:'¿Para qué se necesita el dinero?')),
          const SizedBox(height:10),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:const InputDecoration(labelText:'Monto por cada hijo (soles)')),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Crear colecta'))]));
      if(accept==true){await widget.api.post('/api/fund/collections',{
        'concept':concept.text.trim(),'amountPerMember':double.tryParse(amount.text.replaceAll(',','.')),
      });reload();notice('Colecta creada');}
    }catch(e){notice(e);}finally{concept.dispose();amount.dispose();}
  }
  Future<void> contribute(String collectionId,Map<String,dynamic> me,List<dynamic> members) async {
    final amount=TextEditingController(),reference=TextEditingController();
    String? memberId=(me['memberId'] as String?);
    if(memberId==null&&members.isNotEmpty)memberId=members.first['id'];
    String method='YAPE';
    try{
      final accept=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(
        builder:(ctx,redraw)=>AlertDialog(title:const Text('Registrar un aporte'),content:
          SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            if(me['role']=='ADMIN') DropdownButtonFormField<String>(initialValue:memberId,
              decoration:const InputDecoration(labelText:'¿Quién aportó?'),
              items:members.map((m)=>DropdownMenuItem<String>(value:m['id'],child:Text(m['name']))).toList(),
              onChanged:(v)=>redraw(()=>memberId=v)),
            const SizedBox(height:12),TextField(controller:amount,
              decoration:const InputDecoration(labelText:'Importe aportado en soles'),
              keyboardType:const TextInputType.numberWithOptions(decimal:true)),
            const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:method,
              decoration:const InputDecoration(labelText:'Forma de pago'),
              items:const [DropdownMenuItem(value:'YAPE',child:Text('Yape')),
                DropdownMenuItem(value:'PLIN',child:Text('Plin')),
                DropdownMenuItem(value:'TRANSFER',child:Text('Transferencia')),
                DropdownMenuItem(value:'CASH',child:Text('Efectivo'))],
              onChanged:(v){if(v!=null)redraw(()=>method=v);}),
            const SizedBox(height:12),TextField(controller:reference,
              decoration:const InputDecoration(labelText:'Referencia de pago (opcional)')),
            const SizedBox(height:8),const Text('El dinero se sumará a la caja cuando administración confirme el aporte.'),
          ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Guardar aporte'))])));
      if(accept==true&&memberId!=null){await widget.api.post('/api/fund/collections/$collectionId/contributions',{
        'memberId':memberId,'amount':double.tryParse(amount.text.replaceAll(',','.')),
        'paymentMethod':method,'paymentReference':reference.text.trim(),
      });reload();notice('Aporte enviado para verificación');}
    }catch(e){notice(e);}finally{amount.dispose();reference.dispose();}
  }
  Future<void> expense() async {
    final concept=TextEditingController(),amount=TextEditingController(),receipt=TextEditingController();
    try{
      final accept=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Solicitar un gasto'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:concept,decoration:const InputDecoration(labelText:'Descripción de la compra')),
          const SizedBox(height:12),TextField(controller:amount,
            decoration:const InputDecoration(labelText:'Importe en soles'),
            keyboardType:const TextInputType.numberWithOptions(decimal:true)),
          const SizedBox(height:12),TextField(controller:receipt,
            decoration:const InputDecoration(labelText:'Número o referencia de boleta (opcional)')),
          const SizedBox(height:10),const Text('Por ahora no hay carga de imágenes: guarda la referencia de la boleta y conserva el comprobante.'),
        ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Enviar solicitud'))]));
      if(accept==true){await widget.api.post('/api/fund/expenses',{
        'concept':concept.text,'amount':double.tryParse(amount.text.replaceAll(',','.')),
        'receiptReference':receipt.text,
      });reload();notice('Gasto enviado para revisión');}
    }catch(e){notice(e);}finally{concept.dispose();amount.dispose();receipt.dispose();}
  }
  Future<void> review(String path,bool accept)async{
    try{await widget.api.post(path,{'accept':accept});reload();notice('Operación registrada');}
    catch(e){notice(e);}
  }
  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future:data,builder:(context,snap){
    if(!snap.hasData)return Center(child:snap.hasError?Text('Error: ${snap.error}'):
      const CircularProgressIndicator());
    final summary=snap.data![0] as Map<String,dynamic>,collections=snap.data![1] as List,
      expenses=snap.data![2] as List,me=snap.data![3] as Map<String,dynamic>,members=snap.data![4] as List;
    final names={for(final m in members) m['id']:m['name']};
    return RefreshIndicator(onRefresh:()async{reload();await data;},child:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Dinero disponible en la caja'),const SizedBox(height:5),
          Text('S/ ${summary['available']}',style:Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height:7),Text('Aportes verificados: S/ ${summary['collected']}'),
          Text('Gastos aprobados: S/ ${summary['spent']}'),
        ]))),
      const SizedBox(height:10),
      if(me['role']=='ADMIN')FilledButton.icon(onPressed:collect,
        icon:const Icon(Icons.add),label:const Text('Crear una colecta')),
      const SizedBox(height:12),Text('Colectas',style:Theme.of(context).textTheme.titleLarge),
      if(collections.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('Todavía no se han creado colectas.')),
      ...collections.map((collection)=>Card(child:ExpansionTile(
        title:Text(collection['concept'],style:const TextStyle(fontWeight:FontWeight.w600)),
        subtitle:Text('Importe solicitado por persona: S/ ${collection['amountPerMember']}'),
        children:[Padding(padding:const EdgeInsets.all(12),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            FilledButton.icon(onPressed:()=>contribute(collection['id'],me,members),
              icon:const Icon(Icons.payments_outlined),label:const Text('Registrar aporte')),
            FutureBuilder<dynamic>(future:widget.api.get('/api/fund/collections/${collection['id']}/contributions'),
              builder:(ctx,paymentsSnap){
                if(!paymentsSnap.hasData)return const Padding(padding:EdgeInsets.all(8),child:Text('Cargando aportes...'));
                final payments=paymentsSnap.data as List;
                if(payments.isEmpty)return const Padding(padding:EdgeInsets.all(8),child:Text('Sin aportes todavía'));
                return Column(children:payments.map((p)=>ListTile(
                  title:Text('${names[p['memberId']] ?? 'Familiar'} — S/ ${p['amount']}'),
                  subtitle:Text(p['status']=='VERIFIED'?'Pago confirmado':
                    p['status']=='REJECTED'?'Pago rechazado':'Pendiente de verificar'),
                  trailing:me['role']=='ADMIN'&&p['status']=='SUBMITTED' ?
                    Wrap(spacing:4,children:[
                      IconButton(tooltip:'Confirmar pago',onPressed:()=>review(
                        '/api/fund/contributions/${p['id']}/review',true),icon:const Icon(Icons.check_circle_outline)),
                      IconButton(tooltip:'Rechazar pago',onPressed:()=>review(
                        '/api/fund/contributions/${p['id']}/review',false),icon:const Icon(Icons.cancel_outlined)),
                    ]):null,
                )).toList());
              }),
          ]))],
      ))),
      const SizedBox(height:16),Text('Gastos',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:7),OutlinedButton.icon(onPressed:expense,icon:const Icon(Icons.add),
        label:const Text('Registrar una compra o gasto')),
      if(expenses.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No se han registrado gastos todavía.')),
      ...expenses.map((e)=>Card(child:ListTile(title:Text(e['concept']),
        subtitle:Text('S/ ${e['amount']} — ${e['status']=='APPROVED'?'Gasto aprobado':
           e['status']=='REJECTED'?'Gasto rechazado':'Esperando aprobación'}'),
        trailing:me['role']=='ADMIN'&&e['status']=='REQUESTED'?Wrap(spacing:4,children:[
          IconButton(tooltip:'Aprobar gasto',onPressed:()=>review('/api/fund/expenses/${e['id']}/review',true),
            icon:const Icon(Icons.check_circle_outline)),
          IconButton(tooltip:'Rechazar gasto',onPressed:()=>review('/api/fund/expenses/${e['id']}/review',false),
            icon:const Icon(Icons.cancel_outlined)),
        ]):null))),
    ]));
  });
}
