import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../core/month_calendar.dart';
import '../ui/prado_design.dart';
import '../ui/family_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TurnsScreen extends StatefulWidget {
  const TurnsScreen({super.key, required this.api, required this.updates});
  final FamilyApi api;
  final LiveUpdates updates;
  @override State<TurnsScreen> createState() => _TurnsScreenState();
}

class _TurnsScreenState extends State<TurnsScreen> {
  DateTime visibleMonth = DateTime(peruToday().year, peruToday().month);
  bool calendarView = false;
  bool _busy = true;
  bool _writing = false;
  bool _viewChanged = false;
  String? _error;
  String? _selectedMonday;
  int _generation = 0;
  Timer? _pendingRefresh;
  final Map<String, List<dynamic>> _monthCache = {};
  List<dynamic> _weeks = [], _members = [], _swaps = [];
  String? _displayedMonth;
  Map<String, dynamic> _me = {};
  static const _months = ['enero','febrero','marzo','abril','mayo','junio',
    'julio','agosto','septiembre','octubre','noviembre','diciembre'];
  static const _palette = [Color(0xFF367F78), Color(0xFF3E6689),
    Color(0xFF95663C), Color(0xFF785A8D), Color(0xFFA65C4D),
    Color(0xFF486E50), Color(0xFF666D40), Color(0xFF515F91)];

  @override void initState() {
    super.initState();
    widget.updates.addListener(_onUpdate);
    _selectedMonday = isoDate(firstMonday(peruToday()));
    _load();
  }
  @override void dispose() {
    _pendingRefresh?.cancel();
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }
  String get _monthKey => isoDate(visibleMonth);
  String get _monthTitle => '${_months[visibleMonth.month - 1]} ${visibleMonth.year}';
  String get _viewKey => 'prado_turn_calendar_${_me['memberId'] ?? _me['userId'] ?? 'admin'}';
  Future<void> _restoreView() async {
    final key = _viewKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && !_viewChanged && key == _viewKey) {
        setState(() => calendarView = prefs.getBool(key) ?? false);
      }
    } catch (_) { /* preference is optional */ }
  }
  Future<void> _saveView(bool value) async {
    setState(() { calendarView = value; _viewChanged = true; });
    try { final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_viewKey, value);
    } catch (_) { /* preference is optional */ }
  }
  void _onUpdate() {
    if (widget.updates.lastTopic != 'turns' && widget.updates.lastTopic != 'all') return;
    _monthCache.clear();
    _pendingRefresh?.cancel();
    _pendingRefresh = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !_writing) unawaited(_load());
    });
  }
  Future<void> _load() async {
    final request = ++_generation;
    final key = _monthKey;
    final month = visibleMonth;
    final cached = _monthCache[key] ?? (_displayedMonth == key ? _weeks : null);
    setState(() { _busy = true; _error = null; _weeks = cached ?? []; _displayedMonth = key; });
    try {
      final result = await Future.wait<dynamic>([
        widget.api.get('/api/turns?from=${isoDate(firstMonday(month))}&weeks=${weeksInMonth(month.year, month.month).length}'),
        widget.api.get('/api/members'),
        widget.api.get('/api/auth/me'),
        widget.api.get('/api/swaps'),
      ]);
      if (!mounted || request != _generation) return;
      final weeks = List<dynamic>.from(result[0] as List);
      final firstLoad = _me.isEmpty;
      _monthCache[key] = weeks;
      if (_monthCache.length > 8) _monthCache.remove(_monthCache.keys.first);
      setState(() {
        _weeks = weeks;
        _members = result[1] as List;
        _me = Map<String,dynamic>.from(result[2] as Map);
        _swaps = result[3] as List;
        _busy = false;
      });
      if (firstLoad) unawaited(_restoreView());
    } catch (_) {
      if (!mounted || request != _generation) return;
      setState(() { _busy = false; _error = 'No se pudo actualizar el calendario. Comprueba tu conexión.'; });
    }
  }
  void reload() { _monthCache.clear(); unawaited(_load()); }
  void _setMonth(DateTime month, {String? selected}) {
    if (_writing) return;
    setState(() { visibleMonth = DateTime(month.year, month.month); _selectedMonday = selected; });
    unawaited(_load());
  }
  void notice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  String _range(DateTime monday) {
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return '${dateSpanish(monday)} – ${dateSpanish(sunday)}';
  }
  bool _isCurrent(DateTime monday) => isoDate(monday) == isoDate(firstMonday(peruToday()));
  Color _color(Map<String,dynamic> week) {
    final id = '${week['memberId'] ?? week['memberName']}';
    final index = _members.indexWhere((m) => '${m['id']}' == id);
    final stable = id.codeUnits.fold<int>(0, (a,b) => a+b);
    return _palette[(index < 0 ? stable : index) % _palette.length];
  }
  Future<void> configure(List<dynamic> members) async {
    if (members.isEmpty || _writing || _busy || _error != null) return;
    final ordered = members.map((m) => Map<String,dynamic>.from(m as Map)).toList();
    final first=ValueNotifier<String>(ordered.first['id'] as String);
    DateTime date=firstMonday(peruToday());
    try {
      final saved=await showDialog<bool>(context:context,builder:(context) => StatefulBuilder(
        builder:(context,redraw) => AlertDialog(
          title:const Text('Confirmar calendario familiar'),
          content:SizedBox(width:330,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('IMPORTANTE: los nombres están en un orden provisional. Primero confirma con la familia que esa secuencia es correcta. Una vez que haya historial, no podrá reiniciarse desde aquí.'),
            const SizedBox(height:14),
            const Text('Orden de rotación: mantén pulsadas las líneas para reordenar',
              style:TextStyle(fontWeight:FontWeight.bold)),
            SizedBox(height:245,child:ReorderableListView.builder(
              itemCount:ordered.length,buildDefaultDragHandles:false,
              itemBuilder:(ctx,i)=>ListTile(key:ValueKey(ordered[i]['id']),dense:true,
                title:Text('${i+1}. ${ordered[i]['name']}'),
                trailing:ReorderableDragStartListener(index:i,child:const Icon(Icons.drag_handle))),
              onReorderItem:(oldIndex,newIndex)=>redraw((){
                final moved=ordered.removeAt(oldIndex);
                ordered.insert(newIndex,moved);
              }),
            )),
            const SizedBox(height:14),
            Text('Lunes de referencia: ${dateSpanish(date)}'),
            TextButton.icon(onPressed:()async {
              final picked=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2024),lastDate:DateTime(2032));
              if(picked!=null)redraw(()=>date=firstMonday(picked));
            },icon:const Icon(Icons.calendar_today),label:const Text('Elegir fecha')),
            const Text('¿A quién le corresponde esa semana?'),
            DropdownButton<String>(value:first.value,isExpanded:true,
              items:ordered.map((m)=>DropdownMenuItem<String>(value:m['id'] as String,child:Text(m['name'] as String))).toList(),
              onChanged:(v){if(v!=null)redraw(()=>first.value=v);}),
          ]))),
          actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),
            FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Confirmar orden'))]
        )));
      if(saved==true && mounted){
        setState(() => _writing = true);
        await widget.api.put('/api/admin/rotation',{
          'anchorMonday':isoDate(date),'memberIdsInOrder':ordered.map((x)=>x['id']).toList(),
          'memberStarting':first.value,
        });
        if (mounted) { reload(); notice('Calendario confirmado'); }
      }
    }catch(e){notice(e.toString());} finally {first.dispose(); if (mounted) setState(() => _writing = false);}
  }

  Future<void> swap(String first) async {
    if (_writing || _busy || _error != null) return;
    setState(() => _writing = true);
    List<dynamic> weeks;
    try {
      // Preserve a 16-week selection for swaps without querying those weeks on every visit.
      final current = firstMonday(peruToday());
      final start = firstMonday(visibleMonth);
      final from = start.isAfter(current) ? start : current;
      weeks = List<dynamic>.from(await widget.api.get('/api/turns?from=${isoDate(from)}&weeks=16') as List);
    } catch (_) {
      notice('No se pudieron cargar las semanas disponibles. Reintenta.');
      return;
    } finally { if (mounted) setState(() => _writing = false); }
    if (!mounted) return;
    String? other;
    final candidates=weeks.where((w)=>w['monday']!=first && parseDate(w['monday'] as String).isAfter(firstMonday(peruToday()))).toList();
    if(candidates.isEmpty){notice('No hay semanas futuras disponibles');return;}
    other=candidates.first['monday'] as String;
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(
      builder:(ctx,setLocal)=>AlertDialog(title:const Text('Solicitar cambio de semana'),content:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Semana que deseas cambiar: ${dateSpanish(parseDate(first))}'),const SizedBox(height:12),
          DropdownButton<String>(value:other,isExpanded:true,
            items:candidates.map((w)=>DropdownMenuItem<String>(value:w['monday'] as String,
              child:Text('${w['memberName']} — ${dateSpanish(parseDate(w['monday'] as String))}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged:(v)=>setLocal(()=>other=v)),
          const Text('El otro familiar deberá aceptar antes de realizar el intercambio.'),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Solicitar'))])));
    if(accepted==true&&other!=null&&mounted){
      setState(() => _writing = true);
      try{await widget.api.post('/api/swaps',{'firstMonday':first,'secondMonday':other});if (mounted) { reload(); notice('Solicitud enviada'); }}
      catch(e){notice(e.toString());} finally {if (mounted) setState(() => _writing = false);}
    }
  }

  Future<void> decision(String id,bool accept) async {
    if (_writing || _busy || _error != null) return;
    setState(() => _writing = true);
    try{await widget.api.post('/api/swaps/$id/decision',{'accept':accept});if (mounted) { reload(); notice(accept?'Intercambio aceptado':'Solicitud rechazada'); }}
    catch(e){notice(e.toString());} finally {if (mounted) setState(() => _writing = false);}
  }

  Future<void> _shareWeek(Map<String, dynamic> week) async {
    final monday = parseDate(week['monday'] as String);
    final sunday = monday.add(const Duration(days: 6));
    await showFamilyReport(context, FamilyReport(
      title: 'Semana de comidas',
      subtitle: 'Organización de Papá Isidro',
      mainLabel: 'RESPONSABLE ASIGNADO',
      mainValue: '${week['memberName']}',
      lines: [
        ReportLine('Desde', dateSpanish(monday)),
        ReportLine('Hasta', dateSpanish(sunday)),
        ReportLine('Responsabilidad', 'Desayuno, almuerzo y cena'),
        ReportLine('Calendario', week['configured'] == true
            ? 'Confirmado' : 'Provisional; sujeto a confirmación'),
      ],
      generatedLabel: peruReportStamp(),
      privacy: 'Para intercambios o cambios, consulta siempre la versión '
          'más reciente en Familia Prado.',
    ));
  }


  Widget _weekRow(Map<String,dynamic> week, bool selected) {
    final monday = parseDate(week['monday'] as String);
    final color = _color(week);
    final current = _isCurrent(monday);
    final name = '${week['memberName']}';
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: PradoPanel(
      tint: selected ? PradoColors.paleBlue : PradoColors.paper,
      padding: const EdgeInsets.all(14),
      onTap: () => setState(() => _selectedMonday = week['monday'] as String),
      child: Row(children: [
        Container(width: 44, height: 48, decoration: BoxDecoration(color: color,
          borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.person_outline, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (current) const Text('SEMANA ACTUAL', style: TextStyle(color: PradoColors.teal,
            fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: .7)),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          Text(_range(monday), style: const TextStyle(color: PradoColors.muted, fontSize: 14)),
        ])),
        Icon(selected ? Icons.check_circle : Icons.chevron_right, color: selected ? color : PradoColors.muted),
      ])));
  }
  Widget _calendar(List<Map<String,dynamic>> weeks, Map<String,dynamic>? selected) {
    final today = peruToday();
    final byMonday = {for (final w in weeks) w['monday']: w};
    return PradoPanel(padding: const EdgeInsets.all(10), child: Column(children: [
      Row(children: [for (final day in const ['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'])
        Expanded(child: Text(day, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: PradoColors.muted, fontWeight: FontWeight.w700)))]),
      const SizedBox(height: 8),
      for (final monday in weeksInMonth(visibleMonth.year, visibleMonth.month)) ...[
        Builder(builder: (context) {
          final week = byMonday[isoDate(monday)];
          final color = week == null ? PradoColors.muted : _color(week);
          final isSelected = week != null && week['monday'] == selected?['monday'];
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(
            color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(12),
            child: InkWell(borderRadius: BorderRadius.circular(12),
              onTap: week == null ? null : () => setState(() => _selectedMonday = week['monday'] as String),
              child: Padding(padding: const EdgeInsets.all(5), child: Column(children: [
                Row(children: List.generate(7, (i) {
                  final day = DateTime(monday.year, monday.month, monday.day+i);
                  final current = isoDate(day) == isoDate(today);
                  return Expanded(child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                    decoration: current ? BoxDecoration(color: PradoColors.navy, borderRadius: BorderRadius.circular(8)) : null,
                    child: Text('${day.day}', style: TextStyle(fontSize: 14,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                      color: current ? Colors.white : day.month == visibleMonth.month ? PradoColors.ink : PradoColors.muted)))));
                })),
                const SizedBox(height: 4),
                Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
                  child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(week == null ? 'Sin turno disponible' : '${week['memberName']}',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(_range(monday), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ])), if (isSelected) const Icon(Icons.check_circle_outline, color: Colors.white, size: 20)])),
              ])))),
          );
        }),
      ],
    ]));
  }
  @override Widget build(BuildContext context) {
    final weeks = _weeks.map((w) => Map<String,dynamic>.from(w as Map)).where((w) =>
      weekIntersectsMonth(parseDate(w['monday'] as String), visibleMonth.year, visibleMonth.month)).toList()
      ..sort((a,b) => ('${a['monday']}').compareTo('${b['monday']}'));
    Map<String,dynamic>? selected;
    for (final w in weeks) { if (w['monday'] == _selectedMonday) { selected = w; break; } }
    selected ??= weeks.isEmpty ? null : weeks.first;
    final current = selected;
    final fresh = !_busy && !_writing && _error == null;
    return RefreshIndicator(onRefresh: () async { if (!_writing) { _monthCache.remove(_monthKey); await _load(); } },
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const PradoIntro(eyebrow: 'Nos cuidamos en familia', title: 'Turnos de comida',
          subtitle: 'Organización semanal de Papá Isidro.', icon: Icons.restaurant_outlined, tint: PradoColors.paleSand),
        if (current != null) ...[
          PradoPanel(tint: PradoColors.mint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isCurrent(parseDate(current['monday'] as String)) ? 'RESPONSABLE ESTA SEMANA' : 'TURNO SELECCIONADO',
              style: const TextStyle(color: PradoColors.teal, letterSpacing: 1, fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 8), Text('${current['memberName']}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6), Text(_range(parseDate(current['monday'] as String))),
            const Divider(height: 22), const PradoInfoRow(icon: Icons.restaurant_outlined, text: 'Desayuno, almuerzo y cena'),
          ])), const SizedBox(height: 12),
        ],
        if (weeks.any((w) => w['configured'] != true)) ...[
          PradoPanel(tint: PradoColors.peach, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Calendario provisional. Confirma el orden familiar.'),
            if (_me['role'] == 'ADMIN') FilledButton(onPressed: fresh ? () => configure(_members) : null,
              child: const Text('Confirmar calendario')),
          ])), const SizedBox(height: 12),
        ],
        SizedBox(width: double.infinity, child: SegmentedButton<bool>(showSelectedIcon: false,
          segments: const [ButtonSegment(value: false, label: Text('Lista'), icon: Icon(Icons.view_agenda_outlined)),
            ButtonSegment(value: true, label: Text('Calendario'), icon: Icon(Icons.calendar_month_outlined))],
          selected: {calendarView}, onSelectionChanged: (v) => _saveView(v.first))),
        const SizedBox(height: 10),
        Row(children: [IconButton(tooltip: 'Mes anterior', onPressed: _writing ? null : () => _setMonth(DateTime(visibleMonth.year, visibleMonth.month-1)), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(_monthTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(tooltip: 'Mes siguiente', onPressed: _writing ? null : () => _setMonth(DateTime(visibleMonth.year, visibleMonth.month+1)), icon: const Icon(Icons.chevron_right)),
        ]),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _writing ? null : () {
          final today = peruToday(); _setMonth(today, selected: isoDate(firstMonday(today)));
        }, icon: const Icon(Icons.today_outlined), label: const Text('Hoy'))),
        if (_busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8),
          Text(weeks.isEmpty ? 'Conectando con Familia Prado… Si el servidor estaba en reposo, puede tardar.' : 'Actualizando turnos…')],
        if (_error != null) PradoPanel(tint: PradoColors.peach, child: Column(children: [Text(_error!),
          if (weeks.isNotEmpty) const Text('Mostramos la última consulta de este mes.'),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar'))])),
        if (weeks.isNotEmpty) ...[
          if (calendarView) _calendar(weeks, current) else for (final w in weeks) _weekRow(w, w['monday'] == current?['monday']),
        ] else if (!_busy && _error == null) const PradoEmpty(title: 'Sin turnos', detail: 'No hay semanas disponibles en este mes.'),
        if (current != null) ...[
          const SizedBox(height: 12), OutlinedButton.icon(onPressed: fresh ? () => _shareWeek(current) : null,
            icon: const Icon(Icons.ios_share_outlined), label: const Text('Compartir esta semana en imagen')),
          if (current['configured'] == true && parseDate(current['monday'] as String).isAfter(firstMonday(peruToday())) &&
              (_me['role'] == 'ADMIN' || _me['memberId'] == current['memberId']))
            OutlinedButton.icon(onPressed: fresh ? () => swap(current['monday'] as String) : null,
              icon: const Icon(Icons.swap_horiz), label: const Text('Solicitar intercambio')),
        ],
        if (_swaps.any((s) => s['status'] == 'PENDING')) ...[
          const SizedBox(height: 12), const PradoSectionHeading('Solicitudes de intercambio'),
          for (final s in _swaps.where((s) => s['status'] == 'PENDING')) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: PradoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cambiar ${dateSpanish(parseDate(s['weekA'] as String))} por ${dateSpanish(parseDate(s['weekB'] as String))}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_me['role'] == 'ADMIN' || _me['memberId'] == s['memberB']) Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: fresh ? () => decision(s['id'] as String, false) : null, child: const Text('Rechazar')),
                FilledButton(onPressed: fresh ? () => decision(s['id'] as String, true) : null, child: const Text('Aceptar cambio')),
              ]),
            ]))),
        ], const SizedBox(height: 24),
      ]));
  }
}
