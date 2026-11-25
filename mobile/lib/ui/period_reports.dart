import 'package:flutter/material.dart';
import '../core/api.dart';
import 'prado_design.dart';
import 'family_report.dart';

String _when(String raw) {
  final d = peruClock(raw);
  return '${dateSpanish(d)} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
}
String _status(dynamic s) => switch(s) {
  'COMPLETED' => 'Realizada', 'CONFIRMED' => 'Confirmada',
  'CANCELLED' => 'Cancelada', _ => 'Programada',
};
void _notice(BuildContext context, String message) {
  if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
}
ReportLine _appointmentLine(Map a, Map names, bool showDetails) => ReportLine(
  '${_when('${a['appointmentAt']}')} · ${_status(a['status'])}',
  '${showDetails ? '${a['specialty']}\nLugar: ${a['hospital']}\n' : 'Cita médica\n'}'
  'Asignado: ${names[a['responsibleMemberId']] ?? 'Por asignar'}'
  '${a['actualMemberId'] == null ? '' : '\nAcompañó: ${names[a['actualMemberId']] ?? 'Familiar'}'}',
);
Future<bool?> _privacy(BuildContext context) => showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
  title:const Text('Información para compartir'),
  content:const Text('¿Incluir especialidad y lugar? No se incluyen indicaciones, diagnósticos ni documentos médicos. Comparte solo con la familia.'),
  actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
    OutlinedButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Solo organización')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Incluir detalles'))],
));
List<FamilyReport> _pages({required String title, required String subtitle, required String label,
  required String value,required List<ReportLine> lines,required String stamp,required String privacy,int size=5}) {
  final count=lines.isEmpty?1:(lines.length+size-1)~/size;
  return List.generate(count,(i)=>FamilyReport(title:title,
    subtitle:'$subtitle${count>1?' · Imagen ${i+1}/$count':''}', mainLabel:label, mainValue:value,
    lines:lines.skip(i*size).take(size).toList(),generatedLabel:stamp,privacy:privacy,expanded:true));
}
Future<void> shareSingleAppointment(BuildContext context,Map a,Map names,{bool next=false}) async {
  final detail=await _privacy(context);
  if(detail==null||!context.mounted)return;
  await showFamilyReportPages(context,_pages(title:next?'Próxima cita de Papá Isidro':'Cita de Papá Isidro',subtitle:'Organización familiar',
    label:'FECHA Y HORA · PERÚ',value:_when('${a['appointmentAt']}'),
    lines:[_appointmentLine(a,names,detail)],stamp:peruReportStamp(),privacy:'Comparte solo con la familia.'));
}
Future<DateTimeRange?> _pickDates(BuildContext context, {required bool historical}) async {
  final d=peruToday();
  return showDateRangePicker(context:context,firstDate:DateTime(2020),
    lastDate:historical?DateTime(d.year,d.month,d.day):DateTime(2035,12,31),helpText:'Selecciona el periodo (hora de Perú)');
}
Future<void> shareAppointmentPeriod(BuildContext context,FamilyApi api,List members) async {
  final selected=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Agenda médica en imagen'),children:[
    for(final option in {'TODAY':'Hoy','WEEK':'Esta semana (lunes a domingo)','MONTH':'Este mes','CUSTOM':'Periodo personalizado'}.entries)
      SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,option.key),child:Padding(padding:const EdgeInsets.all(10),child:Text(option.value))),
  ]));
  if(selected==null||!context.mounted)return;
  final day=peruToday(); final today=DateTime(day.year,day.month,day.day);
  DateTime start=today,end=today;
  if(selected=='WEEK'){start=DateTime(today.year,today.month,today.day-today.weekday+1);end=DateTime(start.year,start.month,start.day+6);}
  if(selected=='MONTH'){start=DateTime(today.year,today.month,1);end=DateTime(today.year,today.month+1,0);}
  if(selected=='CUSTOM'){
    final p=await _pickDates(context,historical:false);if(p==null||!context.mounted)return;start=p.start;end=p.end;
  }
  if(DateTime.utc(end.year,end.month,end.day).difference(DateTime.utc(start.year,start.month,start.day)).inDays>366){_notice(context,'Selecciona un periodo de hasta 367 días.');return;}
  final detail=await _privacy(context);if(detail==null||!context.mounted)return;
  try {
    _notice(context,'Preparando agenda…');
    final names={for(final m in members)m['id']:m['name']};
    final items=<Map>[];
    final fromKey=isoDate(start),toKey=isoDate(end);
    var month=DateTime(start.year,start.month,1);
    while(!month.isAfter(end)){
      final list=await api.get('/api/appointments/calendar?month=${isoDate(month)}') as List;
      if(!context.mounted)return;
      for(final raw in list){
        final a=raw as Map;
        final key=isoDate(peruClock('${a['appointmentAt']}'));
        if(key.compareTo(fromKey)>=0&&key.compareTo(toKey)<=0&&a['status']!='CANCELLED')items.add(a);
      }
      month=DateTime(month.year,month.month+1,1);
    }
    items.sort((a,b)=>DateTime.parse('${a['appointmentAt']}').compareTo(DateTime.parse('${b['appointmentAt']}')));
    if(!context.mounted)return;
    if(items.isEmpty){_notice(context,'No hay citas no canceladas en ese periodo.');return;}
    await showFamilyReportPages(context,_pages(title:'Agenda médica familiar',subtitle:'${dateSpanish(start)} – ${dateSpanish(end)}',
      label:'CITAS DEL PERIODO',value:'${items.length}',lines:items.map((a)=>_appointmentLine(a,names,detail)).toList(),
      stamp:peruReportStamp(),privacy:'No incluye citas canceladas ni indicaciones médicas. Comparte solo con la familia.',size:4));
  }catch(e){_notice(context,'No se pudo preparar la agenda: $e');}
}
Future<void> shareCollectionReport(BuildContext context,FamilyApi api,String id) async {
  final period=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Periodo de gastos y deducciones'),children:[
    for(final option in {'BETWEEN':'De la colecta anterior a esta','CURRENT':'Desde esta colecta hasta hoy','PREVIOUS_TO_NOW':'Desde la anterior hasta hoy','CUSTOM':'Periodo personalizado'}.entries)
      SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,option.key),child:Padding(padding:const EdgeInsets.all(10),child:Text(option.value))),
  ]));
  if(period==null||!context.mounted)return;
  String query='period=$period';
  if(period=='CUSTOM'){
    final range=await _pickDates(context,historical:true);if(range==null||!context.mounted)return;
    query+='&from=${isoDate(range.start)}&to=${isoDate(range.end)}';
  }
  try{
    _notice(context,'Preparando reporte de colecta…');
    final r=await api.get('/api/fund/collections/$id/image-report?$query') as Map;
    if(!context.mounted)return;
    final collection=r['collection'] as Map;
    final members=(r['members'] as List).cast<Map>();
    final expenses=(r['expenses'] as List).cast<Map>();
    final stamp=_when('${r['generatedAt']}');
    final subtitle='${collection['concept']} · Corte $stamp';
    const privacy='Solo aportes verificados y gastos aprobados forman parte del saldo. La imagen sale de la app: comparte solo con la familia.';
    final pages=<FamilyReport>[];
    pages.addAll(_pages(title:'Colecta familiar',subtitle:subtitle,label:'TOTAL RECAUDADO · VERIFICADO',value:pradoMoney(r['verified']),stamp:stamp,privacy:privacy,lines:[
      ReportLine('Meta de la colecta',pradoMoney(r['expected']),emphasis:true),
      ReportLine('Aporte por familiar',pradoMoney(collection['amountPerMember'])),
      ReportLine('Total pendiente de verificar o aportar',pradoMoney(r['pending']),emphasis:true),
      ReportLine('En revisión (incluido en pendiente)',pradoMoney(r['submitted'])),
      const ReportLine('Participantes','Familiares activos al corte y quienes registraron aportes en esta colecta. No existe padrón histórico. '),
    ]));
    final sorted=[...members]..sort((a,b){int rank(Map m)=>(m['pending'] as num)==0?0:(m['verified'] as num)>0?1:2;return rank(a).compareTo(rank(b));});
    pages.addAll(_pages(title:'Estado de aportes',subtitle:subtitle,label:'FAMILIARES',value:'${members.length}',stamp:stamp,privacy:privacy,lines:sorted.map((m)=>ReportLine(
      '${m['name']} · ${(m['pending'] as num)==0?'Completo':(m['verified'] as num)>0?'Parcial':'Pendiente'}',
      'Verificado: ${pradoMoney(m['verified'])} · Falta: ${pradoMoney(m['pending'])}'
      '${(m['submitted'] as num)>0?'\nPor verificar: ${pradoMoney(m['submitted'])}':''}')).toList()));
    final window='${collection['concept']} · ${_when('${r['from']}')} a ${_when('${r['to']}')} (fin exclusivo)';
    pages.addAll(_pages(title:'Movimientos de caja',subtitle:window,label:'SALDO AL CIERRE DEL PERIODO',value:pradoMoney(r['closing']),stamp:stamp,privacy:privacy,lines:[
      ReportLine('Saldo inicial',pradoMoney(r['opening'])),
      ReportLine('Todos los aportes verificados del periodo','+ ${pradoMoney(r['periodIncome'])}'),
      ReportLine('Gastos / deducciones aprobados','− ${pradoMoney(r['periodExpenses'])}'),
      ReportLine('Saldo actual de caja al generar',pradoMoney(r['currentAvailable']),emphasis:true),
      const ReportLine('Criterio contable','El periodo utiliza la fecha de verificación del aporte o aprobación del gasto.'),
    ]));
    pages.addAll(_pages(title:'Detalle de gastos',subtitle:window,label:'TOTAL GASTOS APROBADOS',value:pradoMoney(r['periodExpenses']),stamp:stamp,privacy:privacy,
      lines:expenses.isEmpty?[const ReportLine('Sin gastos','No existen gastos aprobados en el periodo.')]:expenses.map((e)=>ReportLine('${e['concept']} · ${pradoMoney(e['amount'])}',
        'Registrado: ${_when('${e['createdAt']}')}\nAprobado: ${_when('${e['approvedAt']}')}')).toList()));
    await showFamilyReportPages(context,pages);
  }catch(e){_notice(context,'No se pudo preparar el reporte: $e');}
}
