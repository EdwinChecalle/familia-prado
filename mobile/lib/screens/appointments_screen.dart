import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, required this.api, required this.updates});
  final FamilyApi api;
  final LiveUpdates updates;
  @override State<AppointmentsScreen> createState()=>_AppointmentsScreenState();
}
class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late Future<List<dynamic>> data;
  @override void initState(){
    super.initState();
    refresh();
    widget.updates.addListener(_onUpdate);
  }
  void _onUpdate() {
    if (widget.updates.lastTopic == 'appointments' || widget.updates.lastTopic == 'all') {
      if (mounted) reload();
    }
  }
  @override void dispose() {
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }
  void refresh(){data=Future.wait([widget.api.get('/api/appointments'),
    widget.api.get('/api/members'),widget.api.get('/api/auth/me')]);}
  void reload(){setState(refresh);}
  void notice(Object message){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$message')));}
  Future<void> create(List<dynamic> members) async {
    final hospital=TextEditingController(),specialty=TextEditingController(),prep=TextEditingController();
    DateTime day=peruToday();TimeOfDay time=const TimeOfDay(hour:9,minute:0);
    String? responsible=members.isNotEmpty?members.first['id']:null;
    try{
      final confirm=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(
        builder:(ctx,redraw)=>AlertDialog(title:const Text('Registrar cita médica'),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:hospital,decoration:const InputDecoration(labelText:'Hospital o centro médico')),
            const SizedBox(height:10),TextField(controller:specialty,
              decoration:const InputDecoration(labelText:'Especialidad o tipo de consulta')),
            const SizedBox(height:12),
            Text('Día: ${dateSpanish(day)}'),TextButton.icon(
              onPressed:()async{final picked=await showDatePicker(context:ctx,
                initialDate:day,firstDate:DateTime(2025),lastDate:DateTime(2032));
                if(picked!=null)redraw(()=>day=picked);},
              icon:const Icon(Icons.calendar_today),label:const Text('Elegir día')),
            Text('Hora en Perú: ${time.format(ctx)}'),TextButton.icon(
              onPressed:()async{final picked=await showTimePicker(context:ctx,initialTime:time);
                if(picked!=null)redraw(()=>time=picked);},
              icon:const Icon(Icons.schedule),label:const Text('Elegir hora')),
            if(members.isNotEmpty) DropdownButtonFormField<String>(initialValue:responsible,
              decoration:const InputDecoration(labelText:'Familiar que acompañará'),
              items:members.map((m)=>DropdownMenuItem<String>(value:m['id'],child:Text(m['name']))).toList(),
              onChanged:(v)=>redraw(()=>responsible=v)),
            const SizedBox(height:10),TextField(controller:prep,maxLines:2,
              decoration:const InputDecoration(labelText:'Preparación (opcional)',hintText:'Documentos, ayuno indicado, etc.')),
          ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Guardar cita'))])));
      if(confirm==true){
        await widget.api.post('/api/appointments',{
          'appointmentAt':peruToUtcIso(day,time.hour,time.minute),
          'hospital':hospital.text.trim(),'specialty':specialty.text.trim(),
          'responsibleMemberId':responsible,'preparation':prep.text.trim(),
        });reload();notice('Cita guardada');
      }
    }catch(e){notice(e);}finally{hospital.dispose();specialty.dispose();prep.dispose();}
  }
  Future<void> changeStatus(String id,String status) async {
    try{await widget.api.patch('/api/appointments/$id/status',{'status':status});reload();notice('Cita actualizada');}
    catch(e){notice(e);}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<List<dynamic>>(future:data,builder:(context,snap){
    if(!snap.hasData)return Center(child:snap.hasError?Text('${snap.error}'):const CircularProgressIndicator());
    final appointments=snap.data![0] as List,members=snap.data![1] as List,me=snap.data![2] as Map<String,dynamic>;
    final names={for (final x in members)x['id']:x['name']};
    return RefreshIndicator(onRefresh:()async{reload();await data;},child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Todas las horas se muestran según el horario de Perú.',
        style:TextStyle(fontWeight:FontWeight.w600)),const SizedBox(height:8),
      if(me['role']=='ADMIN') FilledButton.icon(onPressed:()=>create(members),
        icon:const Icon(Icons.add),label:const Text('Registrar una cita médica')),
      const SizedBox(height:14),
      if(appointments.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(20),
        child:Text('No hay citas médicas registradas.'))),
      ...appointments.map((a){
        final day=peruClock(a['appointmentAt']);
        final mine=me['role']=='ADMIN'||me['memberId']==a['responsibleMemberId'];
        final open=a['status']!='COMPLETED' && a['status']!='CANCELLED';
        final hour='${day.hour.toString().padLeft(2,'0')}:${day.minute.toString().padLeft(2,'0')}';
        return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(a['specialty'],style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:6),
            Text('Día: ${dateSpanish(day)} a las $hour (hora de Perú)'),
            Text('Lugar: ${a['hospital']}'),
            Text('Acompañante: ${names[a['responsibleMemberId']]??'Por asignar'}'),
            Text('Estado: ${a['status']=='PLANNED'?'Programada':a['status']=='CONFIRMED'?'Confirmada':
              a['status']=='COMPLETED'?'Realizada':'Cancelada'}'),
            if((a['preparation'] as String? ?? '').isNotEmpty)Text('Preparación: ${a['preparation']}'),
            if(mine&&open)Wrap(spacing:8,children:[
              if(a['status']=='PLANNED')OutlinedButton(onPressed:()=>changeStatus(a['id'],'CONFIRMED'),
                child:const Text('Confirmar asistencia')),
              FilledButton(onPressed:()=>changeStatus(a['id'],'COMPLETED'),
                child:const Text('Marcar como realizada')),
              TextButton(onPressed:()=>changeStatus(a['id'],'CANCELLED'),child:const Text('Cancelar cita')),
            ]),
          ])));
      }),
    ]));
  });
}
