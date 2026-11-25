import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../core/appointment_filters.dart';
import '../core/month_calendar.dart';
import '../ui/prado_design.dart';
import '../ui/period_reports.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, required this.api, required this.updates, this.initialBucket = 'UPCOMING'});
  final FamilyApi api;
  final LiveUpdates updates;
  final String initialBucket;
  @override State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  static const int pageSize = 20;
  static const tabs = <String, String>{
    'UPCOMING': 'Próximas', 'TODAY': 'Hoy',
    'HISTORY': 'Historial', 'CANCELLED': 'Canceladas',
  };
  String bucket = 'UPCOMING';
  String? responsibleFilter;
  String? statusFilter;
  DateTimeRange? dateRange;
  List<Map<String, dynamic>> entries = [];
  List<dynamic> members = [];
  Map<String, dynamic> me = {};
  Map<String, dynamic> summary = {};
  bool busy = true;
  bool loadingMore = false;
  bool hasMore = false;
  int total = 0;
  int generation = 0;
  String? error;
  bool calendarView = false;
  bool rotationView = false;
  Map<String,dynamic>? rotation;
  bool rotationBusy = false;
  String? rotationError;
  int rotationGeneration = 0;
  List<Map<String,dynamic>> get rotationOrder => ((rotation?['order'] as List?) ?? const []).map((m)=>Map<String,dynamic>.from(m as Map)).toList();
  DateTime calendarMonth = DateTime(peruToday().year, peruToday().month);
  String? calendarDay;
  List<Map<String,dynamic>> calendarEntries = [];
  bool calendarBusy = false;
  String? calendarError;
  int calendarGeneration = 0;
  static const monthNames = ['enero','febrero','marzo','abril','mayo','junio',
    'julio','agosto','septiembre','octubre','noviembre','diciembre'];

  @override void initState() {
    super.initState();
    if (tabs.containsKey(widget.initialBucket)) bucket = widget.initialBucket;
    widget.updates.addListener(_onUpdate);
    _refresh();
    _refreshRotation();
  }

  void _onUpdate() {
    if (widget.updates.lastTopic == 'appointments' ||
        widget.updates.lastTopic == 'all') {
      _refresh();
      if (calendarView) _refreshCalendar();
      _refreshRotation();
    }
  }

  @override void dispose() {
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }

  String _query(int offset) => appointmentSearchPath(
    bucket: bucket, limit: pageSize, offset: offset,
    responsibleMemberId: responsibleFilter,
    status: statusFilter,
    from: dateRange == null ? null : isoDate(dateRange!.start),
    to: dateRange == null ? null : isoDate(dateRange!.end),
  );

  Future<void> _refreshVisible() async {
    await Future.wait<void>([_refresh(), _refreshRotation(), if (calendarView) _refreshCalendar()]);
  }
  Future<void> _refreshCalendar({bool clear = false}) async {
    final request = ++calendarGeneration;
    final month = calendarMonth;
    setState(() { calendarBusy = true; calendarError = null; if (clear) calendarEntries = []; });
    try {
      final response = await widget.api.get('/api/appointments/calendar?month=${isoDate(month)}') as List;
      if (!mounted || request != calendarGeneration) return;
      final sorted = response.map((item) => Map<String,dynamic>.from(item as Map)).toList()
        ..sort((a,b) => DateTime.parse(a['appointmentAt'] as String).compareTo(DateTime.parse(b['appointmentAt'] as String)));
      setState(() { calendarEntries = sorted; calendarBusy = false; });
    } catch (_) {
      if (!mounted || request != calendarGeneration) return;
      setState(() { calendarBusy = false; calendarError = 'No se pudo actualizar el calendario.'; });
    }
  }
  void _changeCalendarMonth(DateTime date) {
    setState(() { calendarMonth = DateTime(date.year,date.month); calendarDay = null; });
    _refreshCalendar(clear: true);
  }
  Future<void> _refreshRotation() async {
    if(!mounted)return;
    final request=++rotationGeneration;
    setState(() { rotationBusy=true;rotationError=null; });
    try {
      final result=await widget.api.get('/api/appointments/rotation') as Map;
      if(!mounted || request!=rotationGeneration)return;
      setState(() {rotation=Map<String,dynamic>.from(result);rotationBusy=false;});
    } catch(e) {
      if(!mounted || request!=rotationGeneration)return;
      setState(() {rotationBusy=false;rotationError='$e';});
    }
  }
  void _setView(String value) {
    if ((rotationView?'rotation':calendarView?'calendar':'list')==value)return;
    setState(() {calendarView=value=='calendar';rotationView=value=='rotation';});
    if(calendarView) { _refreshCalendar(); } else { ++calendarGeneration; }
    if(rotationView)_refreshRotation();
  }
  Future<void> _configureRotation() async {
    if(rotationBusy || rotationError!=null || rotation==null || _mutationBusy)return;
    final current=rotation!;
    final order=rotationOrder;
    final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>_RotationEditor(api:widget.api,order:order,revision:(current['revision'] as num).toInt(),initialNext:(current['regularNextMemberId'] ?? current['nextMemberId']) as String?)));
    if(!mounted || saved!=true)return;
    await _refreshRotation();_notice('Orden de acompañamiento actualizado');
  }
  Future<void> _skipRotation() async {
    if(rotationBusy || rotationError!=null || rotation==null || _mutationBusy)return;
    final current=rotation!;
    String reason='';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('¿Pasar este turno?'),content:TextField(maxLength:300,maxLines:3,decoration:const InputDecoration(labelText:'Motivo del cambio'),onChanged:(v)=>reason=v),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar'))]));
    if(!mounted || ok!=true || _mutationBusy)return;
    if(reason.trim().isEmpty){_notice('Indica el motivo para pasar el turno');return;}
    setState(()=>_mutationBusy=true);
    try {
      await widget.api.post('/api/appointments/rotation/skip',{'revision':current['revision'],'reason':reason.trim()});
      if(mounted){await _refreshRotation();_notice('Turno actualizado');}
    } catch(e){_notice('$e');await _refreshRotation();}
    finally{if(mounted)setState(()=>_mutationBusy=false);}
  }
  Widget _rotationPanel(){
    final order=rotationOrder;
    final names={for(final m in order)m['id']:m['name']};
    final next=rotation?['nextMemberId'];
    final admin=me['role']=='ADMIN';
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(rotationBusy)const LinearProgressIndicator(),
      if(rotationError!=null)PradoPanel(tint:PradoColors.peach,child:Column(children:[const Text('No se pudo actualizar el orden.'),TextButton(onPressed:_refreshRotation,child:const Text('Reintentar'))])),
      if(rotation!=null)...[
        PradoPanel(tint:PradoColors.mint,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const PradoPill('Siguiente acompañante sugerido',color:PradoColors.teal,tint:Color(0xFFDCECE3),icon:Icons.people_outline),
          const SizedBox(height:10),Text('${names[next]??'Sin familiares activos'}',style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:8),const Text('El turno avanza al guardar una cita con el responsable sugerido. Puedes elegir a otro sin consumir el turno. La asistencia se registra por separado.'),
        ])),const SizedBox(height:12),
        if(admin)Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:rotationBusy||rotationError!=null||_mutationBusy?null:_configureRotation,icon:const Icon(Icons.tune),label:const Text('Configurar orden')),
          TextButton.icon(onPressed:next==null||rotationBusy||rotationError!=null||_mutationBusy?null:_skipRotation,icon:const Icon(Icons.skip_next),label:const Text('Pasar turno'))]),
        const SizedBox(height:12),const PradoSectionHeading('Secuencia de acompañamiento',subtitle:'Independiente de Comidas'),
        for(final m in order)Padding(padding:const EdgeInsets.only(bottom:8),child:PradoPanel(tint:m['id']==next?PradoColors.mint:PradoColors.paper,child:Row(children:[
          CircleAvatar(child:Text('${m['position']}')),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${m['name']}',style:Theme.of(context).textTheme.titleMedium),Text(m['active']!=true?'Inactivo':m['id']==next?'Siguiente turno':'En rotación')])),
          if(m['id']==next)const Icon(Icons.arrow_forward,color:PradoColors.teal),
        ]))),
        const SizedBox(height:12),const PradoSectionHeading('Historial de acompañamiento',subtitle:'Últimos 50 movimientos desde la activación'),
        if((rotation!['history'] as List).isEmpty)const Text('Aún no se han confirmado asistencias en esta rotación.'),
        for(final event in rotation!['history'] as List)Padding(padding:const EdgeInsets.only(bottom:8),child:PradoPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(event['kind']=='ATTENDED'?'Acompañó: ${names[event['actualMemberId']]??'Familiar'}':event['kind']=='SKIPPED'?'Turno pasado: ${names[event['suggestedMemberId']]??'Familiar'}':'Orden actualizado',style:Theme.of(context).textTheme.titleSmall),
          if(event['kind']=='ATTENDED' && event['advanced']==true)const Text('Turno avanzado con la regla anterior.'),
          if(event['reason']!=null)Text('${event['reason']}'),
          Text('Registrado: ${dateSpanish(peruClock(event['occurredAt'] as String))}'),
        ]))),
      ],
    ]);
  }
  Future<void> _refresh() async {
    final request = ++generation;
    setState(() { busy = true; loadingMore = false; error = null; entries = []; hasMore = false; });
    try {
      final response = await Future.wait<dynamic>([
        widget.api.get('/api/appointments/summary'),
        widget.api.get('/api/members'),
        widget.api.get('/api/auth/me'),
        widget.api.get(_query(0)),
      ]);
      if (!mounted || request != generation) return;
      final page = response[3] as Map<String, dynamic>;
      setState(() {
        summary = response[0] as Map<String, dynamic>;
        members = response[1] as List<dynamic>;
        me = response[2] as Map<String, dynamic>;
        entries = (page['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        total = (page['total'] as num).toInt();
        hasMore = page['hasMore'] == true;
        busy = false;
      });
    } catch (e) {
      if (!mounted || request != generation) return;
      setState(() { busy = false; error = '$e'; });
    }
  }

  Future<void> _more() async {
    if (busy || loadingMore || !hasMore) return;
    final request = generation;
    final offset = entries.length;
    setState(() => loadingMore = true);
    try {
      final page = await widget.api.get(_query(offset)) as Map<String, dynamic>;
      if (!mounted || request != generation) return;
      setState(() {
        final next = (page['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final existing = entries.map((e) => e['id']).toSet();
        entries.addAll(next.where((e) => !existing.contains(e['id'])));
        total = (page['total'] as num).toInt();
        hasMore = page['hasMore'] == true;
      });
    } catch (e) {
      if (mounted) _notice('No se pudo cargar otra página: $e');
    } finally {
      if (mounted && request == generation) setState(() => loadingMore = false);
    }
  }

  void _notice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setBucket(String value) {
    if (bucket == value) return;
    setState(() { bucket = value; dateRange = null; statusFilter = null; responsibleFilter = null; });
    _refresh();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020), lastDate: DateTime(2035),
      initialDateRange: dateRange,
      helpText: 'Filtrar citas por fecha (hora de Perú)',
    );
    if (!mounted || picked == null) return;
    setState(() => dateRange = picked);
    _refresh();
  }

  bool _mutationBusy = false;
  Future<void> _create() => _openEditor();
  Future<void> _openEditor([Map<String,dynamic>? entry]) async {
    if (_mutationBusy || me['role'] != 'ADMIN') return;
    if(entry==null){await _refreshRotation();if(!mounted)return;}
    final suggested = rotationError == null && !rotationBusy ? (rotation?['nextMemberId'] as String?) : null;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
      AppointmentEditor(api: widget.api, members: members, entry: entry, suggested:suggested,rotationRevision:(rotation?['revision'] as num?)?.toInt())));
    if (!mounted || saved != true) return;
    await _refreshVisible();
    _notice(entry == null ? 'Cita guardada correctamente' : 'Cita actualizada correctamente');
  }
  Future<void> _archive(Map<String,dynamic> entry) async {
    if (_mutationBusy || me['role'] != 'ADMIN') return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('¿Eliminar esta cita?'),
      content: const Text('Dejará de aparecer en Inicio, Lista y Calendario. El registro se conserva en la base de datos. Si está abierta, se cancelarán los recordatorios pendientes.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Eliminar'))],
    ));
    if (!mounted || ok != true || _mutationBusy) return;
    setState(() => _mutationBusy = true);
    try {
      await widget.api.patch('/api/appointments/${entry['id']}/archive', <String,dynamic>{});
      if (!mounted) return;
      await _refreshVisible();
      _notice('Cita eliminada de las vistas');
    } catch(e) { _notice('$e'); }
    finally { if (mounted) setState(() => _mutationBusy = false); }
  }

  Future<void> _changeStatus(String id, String status, {String? assigned}) async {
    if (_mutationBusy) return;
    String? actual=assigned;
    if(status=='COMPLETED' && me['role']=='ADMIN'){
      final choices=rotationOrder.isNotEmpty?rotationOrder:members;
      if(!choices.any((m)=>m['id']==actual))actual=null;
      String? picked=actual;
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,change)=>AlertDialog(
        title:const Text('Confirmar asistencia'),content:Column(mainAxisSize:MainAxisSize.min,children:[const Text('¿Quién acompañó realmente a Papá Isidro?'),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:picked,isExpanded:true,decoration:const InputDecoration(labelText:'Familiar acompañante'),items:[for(final m in choices)DropdownMenuItem(value:m['id'] as String,child:Text('${m['name']}'))],onChanged:(v)=>change(()=>picked=v))]),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Volver')),FilledButton(onPressed:picked==null?null:()=>Navigator.pop(ctx,true),child:const Text('Confirmar'))])));
      if(!mounted||ok!=true)return;actual=picked;
    } else if (status == 'COMPLETED' || status == 'CANCELLED') {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(status == 'CANCELLED' ? '¿Cancelar esta cita?' : '¿Confirmar que se realizó?'),
        content: Text(status == 'CANCELLED'
          ? 'La cita quedará en el historial de canceladas y no generará futuros recordatorios.'
          : 'Se registrará como realizada. Este cambio no se puede deshacer.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar'))],
      ));
      if (ok != true || !mounted) return;
    }
    if (!mounted || _mutationBusy) return;
    setState(() => _mutationBusy = true);
    try {
      await widget.api.patch('/api/appointments/$id/status', {'status': status, if(status=='COMPLETED' && actual!=null) 'actualMemberId':actual});
      await _refreshVisible();
      _notice('Estado actualizado');
    } catch (e) { _notice('$e'); }
    finally { if (mounted) setState(() => _mutationBusy = false); }
  }

  String _statusText(Map<String, dynamic> entry) {
    final status = entry['status'];
    if (status == 'COMPLETED') return 'Realizada';
    if (status == 'CANCELLED') return 'Cancelada';
    if (status == 'CONFIRMED') return 'Confirmada';
    if (DateTime.parse(entry['appointmentAt'] as String).isBefore(DateTime.now())) {
      return 'Pendiente de actualizar';
    }
    return 'Programada';
  }

  Future<void> _shareNextAppointment() async {
    final next = summary['next'];
    if (next is! Map) { _notice('No hay una próxima cita programada.'); return; }
    final names = {for (final m in members) m['id']: m['name']};
    await shareSingleAppointment(context, next, names, next: true);
  }

  Future<void> _shareAgenda() async {
    await shareAppointmentPeriod(context, widget.api, members);
  }

  Widget _appointmentCard(Map<String, dynamic> a, Map<dynamic, dynamic> names, {bool allowChanges = true}) {
    final day = peruClock(a['appointmentAt'] as String);
    final hour = '${day.hour.toString().padLeft(2, '0')}:${day.minute.toString().padLeft(2, '0')}';
    final status = a['status'];
    final open = status == 'PLANNED' || status == 'CONFIRMED';
    final admin = me['role'] == 'ADMIN';
    final canChange = admin || (me['memberId'] != null && me['memberId'] == a['responsibleMemberId']);
    final statusLabel = _statusText(a);
    final isCancelled = status == 'CANCELLED';
    final warning = statusLabel == 'Pendiente de actualizar';
    final name = '${names[a['responsibleMemberId']] ?? 'Por asignar'}';
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: PradoPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 46, width: 46, decoration: BoxDecoration(
            color: isCancelled ? PradoColors.peach : PradoColors.paleBlue,
            borderRadius: BorderRadius.circular(15)),
            child: Icon(isCancelled ? Icons.event_busy_outlined : Icons.medical_services_outlined,
              color: isCancelled ? PradoColors.coral : PradoColors.ocean)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['specialty']}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            PradoPill(statusLabel,
              color: isCancelled || warning ? PradoColors.coral : PradoColors.teal,
              tint: isCancelled || warning ? PradoColors.peach : PradoColors.mint,
              icon: isCancelled ? Icons.close : warning ? Icons.info_outline : Icons.check_circle_outline),
          ])),
        ]),
        const SizedBox(height: 14),
        PradoInfoRow(icon: Icons.calendar_month_outlined,
          text: '${dateSpanish(day)} · $hour (hora de Perú)'),
        PradoInfoRow(icon: Icons.location_on_outlined, text: '${a['hospital']}'),
        PradoInfoRow(icon: Icons.person_outline, text: 'Asignado: $name'),
        if(status=='COMPLETED' && a['actualMemberId']!=null) PradoInfoRow(icon:Icons.check_circle_outline,text:'Acompañó: ${names[a['actualMemberId']] ?? 'Familiar'}'),
        if ('${a['preparation'] ?? ''}'.trim().isNotEmpty)
          PradoInfoRow(icon: Icons.assignment_outlined, text: 'Preparación: ${a['preparation']}'),
        TextButton.icon(onPressed: allowChanges ? () => shareSingleAppointment(context,a,names) : null,
          icon: const Icon(Icons.ios_share_outlined), label: const Text('Compartir cita')),
        if ((admin || (canChange && open)) && allowChanges) ...[
          const Divider(height: 22, color: PradoColors.line),
          Wrap(spacing: 8, runSpacing: 5, children: [
            if (admin && open) OutlinedButton.icon(onPressed: _mutationBusy ? null : () => _openEditor(a), icon: const Icon(Icons.edit_calendar_outlined), label: const Text('Editar / reprogramar')),
            if (canChange && status == 'PLANNED') OutlinedButton.icon(
              onPressed: _mutationBusy ? null : () => _changeStatus('${a['id']}', 'CONFIRMED'),
              icon: const Icon(Icons.verified_outlined, size: 18), label: const Text('Confirmar')),
            if (canChange && open) OutlinedButton.icon(onPressed: _mutationBusy ? null : () => _changeStatus('${a['id']}', 'COMPLETED', assigned:a['responsibleMemberId'] as String?),
              icon: const Icon(Icons.done_all, size: 18), label: const Text('Realizada')),
            if (canChange && open) TextButton(onPressed: _mutationBusy ? null : () => _changeStatus('${a['id']}', 'CANCELLED'),
              child: const Text('Cancelar cita')),
            if (admin) TextButton.icon(onPressed: _mutationBusy ? null : () => _archive(a), icon: const Icon(Icons.delete_outline, color: PradoColors.coral), label: const Text('Eliminar', style: TextStyle(color: PradoColors.coral))),
          ]),
        ],
      ]),
    ));
  }

  Widget _calendarPanel(Map<dynamic,dynamic> names) {
    final today = isoDate(peruToday());
    final grouped = <String,List<Map<String,dynamic>>>{};
    for (final a in calendarEntries) {
      final key = isoDate(peruClock(a['appointmentAt'] as String));
      (grouped[key] ??= []).add(a);
    }
    final days = grouped.keys.toList()..sort();
    final shown = calendarDay == null ? days : days.where((day) => day == calendarDay).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(tooltip: 'Mes anterior', onPressed: () => _changeCalendarMonth(DateTime(calendarMonth.year,calendarMonth.month-1)), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('${monthNames[calendarMonth.month-1]} ${calendarMonth.year}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(tooltip: 'Mes siguiente', onPressed: () => _changeCalendarMonth(DateTime(calendarMonth.year,calendarMonth.month+1)), icon: const Icon(Icons.chevron_right)),
      ]),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _changeCalendarMonth(peruToday()), icon: const Icon(Icons.today_outlined), label: const Text('Hoy'))),
      PradoPanel(padding: const EdgeInsets.all(8), child: Column(children: [
        Row(children: [for (final name in const ['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'])
          Expanded(child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PradoColors.muted)))]),
        const SizedBox(height: 7),
        for (final monday in weeksInMonth(calendarMonth.year, calendarMonth.month))
          Row(children: List.generate(7, (i) {
            final date = DateTime(monday.year,monday.month,monday.day+i);
            final key = isoDate(date);
            final inMonth = date.month == calendarMonth.month;
            final count = inMonth ? grouped[key]?.length ?? 0 : 0;
            final selected = calendarDay == key;
            return Expanded(child: Padding(padding: const EdgeInsets.all(2), child: Semantics(
              button: inMonth, selected: selected, label: '${dateSpanish(date)}, $count citas',
              child: Material(color: selected ? PradoColors.navy : count > 0 ? PradoColors.mint : Colors.transparent,
                borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10),
                  onTap: !inMonth ? null : () => setState(() => calendarDay = selected ? null : key),
                  child: Container(constraints: const BoxConstraints(minHeight: 52),
                    decoration: key == today ? BoxDecoration(border: Border.all(color: PradoColors.teal, width: 1.5), borderRadius: BorderRadius.circular(10)) : null,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${date.day}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                        color: selected ? Colors.white : inMonth ? PradoColors.ink : PradoColors.muted)),
                      if (count > 0) Text('$count', style: TextStyle(fontSize: 11, color: selected ? Colors.white : PradoColors.teal)),
                    ])))))));
          })),
      ])),
      const SizedBox(height: 12),
      if (calendarBusy) ...[const LinearProgressIndicator(), const SizedBox(height: 8), const Text('Actualizando calendario…')],
      if (calendarError != null) PradoPanel(tint: PradoColors.peach, child: Column(children: [
        Text(calendarError!), if (calendarEntries.isNotEmpty) const Text('Mostramos la última consulta de este mes.'),
        TextButton.icon(onPressed: () => _refreshCalendar(), icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      ])),
      if (calendarDay != null) TextButton.icon(onPressed: () => setState(() => calendarDay = null), icon: const Icon(Icons.calendar_view_month), label: const Text('Ver todas las citas del mes')),
      PradoSectionHeading(calendarDay == null ? 'Citas del mes' : 'Citas del ${dateSpanish(parseDate(calendarDay!))}',
        subtitle: 'Hora de Perú'),
      if (!calendarBusy && calendarError == null && shown.isEmpty) const PradoEmpty(title: 'Sin citas', detail: 'No hay citas registradas para esta selección.', icon: Icons.event_available_outlined),
      for (final day in shown) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(dateSpanish(parseDate(day)), style: const TextStyle(fontWeight: FontWeight.w800, color: PradoColors.navy))),
        for (final a in grouped[day]!) _appointmentCard(a, names, allowChanges: !calendarBusy && calendarError == null),
      ],
    ]);
  }

  @override Widget build(BuildContext context) {
    final names = {for (final m in members) m['id']: m['name']};
    final next = summary['next'];
    final rotationNames={for(final m in rotationOrder)m['id']:m['name']};
    return RefreshIndicator(
      onRefresh: _refreshVisible,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const PradoIntro(eyebrow: 'Cuidado de Papá Isidro',
          title: 'Citas médicas',
          subtitle: 'Cada visita, clara y a tiempo.', icon: Icons.event_note_outlined,
          tint: PradoColors.paleSand),
        if (next is Map) ...[
          PradoPanel(tint: PradoColors.paleBlue, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const PradoPill('Siguiente cita', color: PradoColors.ocean,
                tint: Color(0xFFDCEAF8), icon: Icons.upcoming_outlined),
              const SizedBox(height: 10),
              Text('${next['specialty']}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text('${dateSpanish(peruClock(next['appointmentAt'] as String))} · '
                '${peruClock(next['appointmentAt'] as String).hour.toString().padLeft(2, '0')}:'
                '${peruClock(next['appointmentAt'] as String).minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text('${next['hospital']} · ${names[next['responsibleMemberId']] ?? 'Por asignar'}',
                style: const TextStyle(color: PradoColors.muted, fontSize: 15)),
            ])),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _shareNextAppointment,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Compartir próxima cita en imagen')),
          const SizedBox(height: 14),
        ],
        OutlinedButton.icon(onPressed: busy || error != null ? null : _shareAgenda,
          icon: const Icon(Icons.calendar_month_outlined), label: const Text('Compartir agenda por periodo')),
        const SizedBox(height: 12),
        if (me['role'] == 'ADMIN') ...[
          FilledButton.icon(onPressed: _mutationBusy ? null : _create, icon: const Icon(Icons.add_circle_outline),
            label: const Text('Registrar nueva cita')),
          const SizedBox(height: 14),
        ],
        if (!rotationView && rotation != null && rotationError == null) ...[
          PradoPanel(tint:PradoColors.mint,onTap:()=>_setView('rotation'),child:Row(children:[
            const Icon(Icons.people_outline,color:PradoColors.teal),const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('Siguiente turno de acompañamiento',style:TextStyle(color:PradoColors.muted,fontWeight:FontWeight.w600)),
              Text('${rotationNames[rotation?['nextMemberId']] ?? 'Sin familiares activos'}',style:Theme.of(context).textTheme.titleMedium),
            ])),const Icon(Icons.chevron_right),
          ])),const SizedBox(height:12),
        ],
        SizedBox(width: double.infinity, child: SegmentedButton<String>(showSelectedIcon:false,
          segments:const [ButtonSegment(value:'list',label:Text('Lista')),
            ButtonSegment(value:'calendar',label:Text('Calendario')),
            ButtonSegment(value:'rotation',label:Text('Turnos'))],
          selected:{rotationView?'rotation':calendarView?'calendar':'list'},onSelectionChanged:(v)=>_setView(v.first))),
        const SizedBox(height: 12),
        if(rotationView) _rotationPanel() else if (calendarView) _calendarPanel(names) else ...[
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final entry in tabs.entries) Padding(padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text('${entry.value}  ${summary[entry.key.toLowerCase()] ?? ''}'),
              selected: bucket == entry.key, showCheckmark: false,
              onSelected: (_) => _setBucket(entry.key))),
        ])),
        const SizedBox(height: 15),
        if (bucket == 'HISTORY' || bucket == 'CANCELLED') ...[
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: _pickRange, icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(dateRange == null ? 'Filtrar por fecha'
                : '${dateSpanish(dateRange!.start)} – ${dateSpanish(dateRange!.end)}')),
            if (dateRange != null) TextButton(onPressed: () { setState(() => dateRange = null); _refresh(); },
              child: const Text('Quitar fechas')),
          ]),
          if (bucket == 'HISTORY') const SizedBox(height: 8),
        ],
        if (bucket == 'HISTORY') DropdownButtonFormField<String>(
          key: ValueKey('state-$bucket-$statusFilter'),
          initialValue: statusFilter,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Estado de la cita'),
          items: const [
            DropdownMenuItem(value: 'COMPLETED', child: Text('Realizadas')),
            DropdownMenuItem(value: 'PLANNED', child: Text('Sin confirmar')),
            DropdownMenuItem(value: 'CONFIRMED', child: Text('Confirmadas')),
          ],
          onChanged: (value) { setState(() => statusFilter = value); _refresh(); },
        ),
        if ((bucket == 'HISTORY' || bucket == 'CANCELLED') && members.isNotEmpty) ...[
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(
            key: ValueKey('responsible-$bucket-$responsibleFilter'),
            initialValue: responsibleFilter, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Familiar acompañante'),
            items: members.map((m) => DropdownMenuItem<String>(
              value: m['id'] as String, child: Text('${m['name']}'))).toList(),
            onChanged: (value) { setState(() => responsibleFilter = value); _refresh(); },
          ),
          if (responsibleFilter != null || statusFilter != null) TextButton.icon(
            onPressed: () { setState(() { responsibleFilter = null; statusFilter = null; }); _refresh(); },
            icon: const Icon(Icons.filter_alt_off), label: const Text('Quitar filtros')),
        ],
        PradoSectionHeading(tabs[bucket]!, subtitle: busy ? 'Consultando citas…' : '$total registros'),
        if (busy) const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
        else if (error != null) PradoEmpty(title: 'No se pudieron cargar las citas', detail: error!,
          icon: Icons.wifi_off_outlined,
          action: FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh),
            label: const Text('Volver a intentar')))
        else if (entries.isEmpty) PradoEmpty(
          title: 'No hay citas en esta sección',
          detail: bucket == 'UPCOMING' ? 'Las nuevas citas futuras aparecerán aquí.' :
            'Prueba con otra fecha o consulta las demás secciones.',
          icon: Icons.event_available_outlined)
        else ...[
          for (final a in entries) _appointmentCard(a, names),
          if (hasMore) Center(child: OutlinedButton.icon(
            onPressed: loadingMore ? null : _more,
            icon: const Icon(Icons.expand_more),
            label: Text(loadingMore ? 'Cargando…' : 'Cargar 20 citas más'))),
          if (!hasMore) Padding(padding: const EdgeInsets.all(14),
            child: Text('Has llegado al final de los $total registros.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: PradoColors.muted, fontSize: 14))),
        ],
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Formulario de página completa, compartido por creación y edición.
class AppointmentEditor extends StatefulWidget {
  const AppointmentEditor({super.key, required this.api, required this.members, this.entry,this.suggested,this.rotationRevision});
  final FamilyApi api;
  final List<dynamic> members;
  final Map<String,dynamic>? entry;
  final String? suggested;
  final int? rotationRevision;
  @override State<AppointmentEditor> createState() => _AppointmentEditorState();
}
class _AppointmentEditorState extends State<AppointmentEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController specialty, hospital, prep;
  late DateTime day;
  late TimeOfDay time;
  String? responsible;
  bool saving = false;
  String? problem;
  bool get editing => widget.entry != null;
  List<dynamic> get members => widget.members.where((m) => m['active'] != false).toList();
  @override void initState() {
    super.initState();
    final e = widget.entry;
    specialty = TextEditingController(text: e?['specialty'] as String? ?? '');
    hospital = TextEditingController(text: e?['hospital'] as String? ?? '');
    prep = TextEditingController(text: e?['preparation'] as String? ?? '');
    final at = editing ? peruClock(e!['appointmentAt'] as String) : peruToday();
    day = DateTime(at.year, at.month, at.day);
    time = editing ? TimeOfDay(hour: at.hour, minute: at.minute) : const TimeOfDay(hour:9,minute:0);
    responsible = editing ? e!['responsibleMemberId'] as String? : widget.suggested;
    if (!members.any((m) => m['id'] == responsible)) responsible = null;
  }
  @override void dispose() { specialty.dispose(); hospital.dispose(); prep.dispose(); super.dispose(); }
  String? requiredText(String? text) => (text ?? '').trim().isEmpty ? 'Completa este campo' : null;
  Future<void> chooseDate() async {
    final result = await showDatePicker(context: context, initialDate:day,
      firstDate: DateTime(day.year < 2020 ? day.year : 2020),
      lastDate: DateTime(day.year > 2100 ? day.year : 2100,12,31), helpText:'Fecha de la cita');
    if (mounted && result != null) setState(() => day = result);
  }
  Future<void> chooseTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: time,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (mounted && result != null) setState(() => time = result);
  }
  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (editing) {
      final confirmed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title: const Text('¿Guardar cambios?'), content:const Text('La familia recibirá un aviso si hay cambios. Si cambias fecha, hora o acompañante, se actualizarán los recordatorios y la cita volverá a estar pendiente de confirmar.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Revisar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Guardar cambios'))]));
      if (!mounted || confirmed != true || saving) return;
    }
    setState(() { saving=true; problem=null; });
    try {
      final payload = <String,dynamic>{'appointmentAt':peruToUtcIso(day,time.hour,time.minute),
        'hospital':hospital.text.trim(),'specialty':specialty.text.trim(),
        'responsibleMemberId':responsible,'preparation':prep.text.trim(),
        if(!editing && responsible!=null && responsible==widget.suggested && widget.rotationRevision!=null)
          'rotationRevision':widget.rotationRevision};
      if(editing) { await widget.api.patch('/api/appointments/${widget.entry!['id']}',payload); }
      else { await widget.api.post('/api/appointments',payload); }
      if (mounted) { setState(() => saving=false); Navigator.pop(context,true); }
    } catch(e) { if (mounted) setState(() { saving=false;problem='$e'; }); }
  }
  InputDecoration decoration(String label, IconData icon) => InputDecoration(labelText:label,
    prefixIcon:Icon(icon), contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:20),
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(16)));
  @override Widget build(BuildContext context) => PopScope(canPop:!saving, child: Scaffold(
    backgroundColor: const Color(0xFFFCF7EF),
    appBar:AppBar(title:Text(editing?'Editar cita':'Nueva cita médica')),
    body:SafeArea(child: Form(key:form, child: ListView(padding:const EdgeInsets.all(18),children:[
      PradoIntro(eyebrow:'Cuidado de Papá Isidro',title:editing?'Actualizar cita':'Agendar una visita',
        subtitle:'Completa los datos para organizar el acompañamiento.',icon:Icons.medical_services_outlined,tint:PradoColors.paleSand),
      const SizedBox(height:16),
      PradoPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('Información de la visita',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:16),
        TextFormField(controller:specialty,enabled:!saving,maxLength:120,validator:requiredText,style:const TextStyle(fontSize:17),decoration:decoration('Especialidad o consulta',Icons.medical_services_outlined)),
        const SizedBox(height:12),
        TextFormField(controller:hospital,enabled:!saving,maxLength:160,validator:requiredText,style:const TextStyle(fontSize:17),decoration:decoration('Centro médico o lugar',Icons.location_on_outlined)),
      ])),const SizedBox(height:14),
      PradoPanel(tint:PradoColors.paleBlue,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('Fecha y hora · Perú',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:12),
        OutlinedButton.icon(style:OutlinedButton.styleFrom(minimumSize:const Size(0,58)),onPressed:saving?null:chooseDate,icon:const Icon(Icons.calendar_month),label:Text(dateSpanish(day),style:const TextStyle(fontSize:17))),const SizedBox(height:10),
        OutlinedButton.icon(style:OutlinedButton.styleFrom(minimumSize:const Size(0,58)),onPressed:saving?null:chooseTime,icon:const Icon(Icons.schedule),label:Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} (hora de Perú)',style:const TextStyle(fontSize:17))),
      ])),const SizedBox(height:14),
      PradoPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('Acompañamiento y preparación',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:14),
        if(!editing && widget.suggested!=null)...[
          Text('Sugerido: ${members.where((m)=>m['id']==widget.suggested).map((m)=>m['name']).join()}',style:const TextStyle(fontWeight:FontWeight.bold,color:PradoColors.teal)),
          const Text('Puedes elegir a otro familiar. Si guardas con el sugerido, se reserva su turno y avanza la secuencia.'),const SizedBox(height:12),
        ],
        DropdownButtonFormField<String>(initialValue:responsible??'',isExpanded:true,decoration:decoration('Familiar acompañante',Icons.person_outline),
          items:[const DropdownMenuItem(value:'',child:Text('Por asignar')),for(final m in members) DropdownMenuItem(value:m['id'] as String,child:Text('${m['name']}'))],onChanged:saving?null:(v)=>setState(()=>responsible=v==''?null:v)),
        const SizedBox(height:16),TextFormField(controller:prep,enabled:!saving,maxLength:500,minLines:3,maxLines:5,decoration:decoration('Preparación u observaciones',Icons.assignment_outlined)),
      ])),if(problem!=null)...[const SizedBox(height:12),Text(problem!,style:const TextStyle(color:PradoColors.coral))],const SizedBox(height:18),
      FilledButton.icon(style:FilledButton.styleFrom(minimumSize:const Size(0,58)),onPressed:saving?null:save,icon:saving?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check),label:Text(saving?'Guardando…':editing?'Guardar cambios':'Guardar cita',style:const TextStyle(fontSize:17))),
      const SizedBox(height:10),TextButton(onPressed:saving?null:()=>Navigator.pop(context),child:const Text('Volver sin guardar')),
    ]))),
  ));
}

/// Orden independiente de Comidas. Se valida también en el servidor.
class _RotationEditor extends StatefulWidget {
  const _RotationEditor({required this.api,required this.order,required this.revision,required this.initialNext});
  final FamilyApi api;final List<Map<String,dynamic>> order;final int revision;final String? initialNext;
  @override State<_RotationEditor> createState()=>_RotationEditorState();
}
class _RotationEditorState extends State<_RotationEditor>{
  late List<Map<String,dynamic>> order;String? next;bool saving=false;String? error;
  @override void initState(){super.initState();order=List.of(widget.order);next=widget.initialNext;}
  void move(int i,int j){if(j<0||j>=order.length)return;setState((){final m=order.removeAt(i);order.insert(j,m);});}
  Future<void> save()async{
    if(saving||next==null)return;setState((){saving=true;error=null;});
    try{await widget.api.patch('/api/appointments/rotation',{'memberIds':[for(final m in order)m['id']],'nextMemberId':next,'revision':widget.revision});if(mounted)Navigator.pop(context,true);}
    catch(e){if(mounted)setState((){saving=false;error='$e';});}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Orden de acompañamiento')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Ordena los hermanos con las flechas. Los turnos recuperados conservan su prioridad; las citas ya asignadas no cambian. No modifica Comidas.'),const SizedBox(height:12),
    for(int i=0;i<order.length;i++)ListTile(key:ValueKey(order[i]['id']),leading:CircleAvatar(child:Text('${i+1}')),title:Text('${order[i]['name']}'),subtitle:order[i]['active']==true?null:const Text('Inactivo'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'Subir',onPressed:saving||i==0?null:()=>move(i,i-1),icon:const Icon(Icons.arrow_upward)),IconButton(tooltip:'Bajar',onPressed:saving||i==order.length-1?null:()=>move(i,i+1),icon:const Icon(Icons.arrow_downward))])),
    const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:next,isExpanded:true,decoration:const InputDecoration(labelText:'Siguiente acompañante'),items:[for(final m in order.where((m)=>m['active']==true))DropdownMenuItem(value:m['id'] as String,child:Text('${m['name']}'))],onChanged:saving?null:(v)=>setState(()=>next=v)),
    if(error!=null)Text(error!,style:const TextStyle(color:PradoColors.coral)),const SizedBox(height:18),FilledButton(onPressed:saving||next==null?null:save,child:Text(saving?'Guardando…':'Guardar orden')),
  ])));
}
