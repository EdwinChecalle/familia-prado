import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../ui/prado_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TurnsScreen extends StatefulWidget {
  const TurnsScreen({super.key, required this.api, required this.updates});
  final FamilyApi api;
  final LiveUpdates updates;
  @override State<TurnsScreen> createState() => _TurnsScreenState();
}

class _TurnsScreenState extends State<TurnsScreen> {
  late Future<List<dynamic>> data;
  int selected = 0;
  int cyclePage = 0; // 16-week pages, including earlier cycles.
  List<dynamic> checks = [];
  bool submitting = false;
  bool agendaView = true;
  String? _loadedMonday;
  String? _checksError;
  bool _loadingChecks = false;
  int _checksRequestId = 0;
  @override void initState(){
    super.initState();
    refresh();
    _restoreView();
    widget.updates.addListener(_onUpdate);
  }
  Future<void> _restoreView() async {
    try {
      final me = await widget.api.get('/api/auth/me') as Map<String, dynamic>;
      final preferences = await SharedPreferences.getInstance();
      final key = 'prado_view_${me['memberId'] ?? me['userId'] ?? 'admin'}';
      if (mounted) setState(() => agendaView = preferences.getBool(key) ?? true);
    } catch (_) { /* Safe default to compact agenda. */ }
  }
  Future<void> _saveView(bool agenda) async {
    setState(() => agendaView = agenda);
    try {
      final me = await widget.api.get('/api/auth/me') as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('prado_view_${me['memberId'] ?? me['userId'] ?? 'admin'}', agenda);
    } catch (_) { /* View is still switched for this session. */ }
  }

  void _onUpdate() {
    if (widget.updates.lastTopic == 'turns' || widget.updates.lastTopic == 'all') {
      if (mounted && !submitting) setState(refresh);
    }
  }
  @override void dispose() {
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }
  void refresh() {
    // Descarta resultados antiguos de una carga previa de la pantalla.
    final requestId = ++_checksRequestId;
    data = Future.wait([
      widget.api.get('/api/turns?from=${isoDate(firstMonday(peruToday()).add(Duration(days:cyclePage*16*7)))}&weeks=16'),
      widget.api.get('/api/members'),
      widget.api.get('/api/auth/me'),
      widget.api.get('/api/swaps'),
    ]);
    data.then((result) {
      if (!mounted || requestId != _checksRequestId) return;
      final weeks = result[0] as List;
      if (weeks.isNotEmpty) fetchChecks(weeks[selected]['monday'] as String);
    }).catchError((Object error) {});
  }

  Future<void> fetchChecks(String monday) async {
    final requestId = ++_checksRequestId;
    if (!mounted) return;
    setState(() {
      _loadedMonday = null;
      _loadingChecks = true;
      _checksError = null;
      checks = [];
    });
    try {
      final result = await widget.api.get('/api/turns/$monday/meals');
      if (!mounted || requestId != _checksRequestId) return;
      setState(() {
        checks = List<dynamic>.from(result as List);
        _loadedMonday = monday;
        _loadingChecks = false;
      });
    } catch (_) {
      if (!mounted || requestId != _checksRequestId) return;
      setState(() {
        _loadingChecks = false;
        _checksError = 'No se pudieron cargar las comidas de esta semana.';
      });
    }
  }

  void reload() {
    setState(() {
      selected = 0;
      checks = [];
      _loadedMonday = null;
      _checksError = null;
      _loadingChecks = true;
      refresh();
    });
  }

  void _changePage(int direction) {
    setState(() {
      cyclePage += direction;
      selected = 0;
      checks = [];
      _loadedMonday = null;
      _loadingChecks = true;
      refresh();
    });
  }

  void notice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool done(String date, String type) => checks.any((x) =>
    x['date'] == date && x['meal'] == type && x['completed'] == true);

  Future<void> toggle(String monday, String date, String type) async {
    if (submitting || _loadingChecks || _loadedMonday != monday) return;

    // El contador y los botones utilizan la MISMA lista local de comidas.
    final before = checks.map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final updated = before.map((x) => Map<String, dynamic>.from(x)).toList();
    final nextValue = !done(date, type);
    final index = updated.indexWhere((x) => x['date'] == date && x['meal'] == type);
    if (index == -1) {
      updated.add({'date': date, 'meal': type, 'completed': nextValue});
    } else {
      updated[index]['completed'] = nextValue;
    }
    setState(() {
      submitting = true;
      checks = updated; // Cambio inmediato, incluso sin respuesta del servidor.
    });

    try {
      await widget.api.put('/api/turns/$monday/meals', {
        'date': date, 'meal': type, 'completed': nextValue,
      });
      // Reconciliar con PostgreSQL. Si falla esta consulta, no se revierte un PUT exitoso.
      try {
        final server = await widget.api.get('/api/turns/$monday/meals');
        if (mounted && _loadedMonday == monday) {
          setState(() => checks = List<dynamic>.from(server as List));
        }
      } catch (_) {
        notice('Comida guardada, pero no se pudo comprobar el estado actualizado.');
      }
    } catch (e) {
      // El PUT fue rechazado: recuperar el estado anterior en la semana correcta.
      if (mounted && _loadedMonday == monday) {
        setState(() => checks = before);
      }
      notice('No se pudo guardar la comida. Se revirtió el cambio: $e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> configure(List<dynamic> members) async {
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
      if(saved==true){
        await widget.api.put('/api/admin/rotation',{
          'anchorMonday':isoDate(date),'memberIdsInOrder':ordered.map((x)=>x['id']).toList(),
          'memberStarting':first.value,
        });
        reload();notice('Calendario confirmado');
      }
    }catch(e){notice(e.toString());} finally {first.dispose();}
  }

  Future<void> swap(String first, List<dynamic> weeks) async {
    String? other;
    final candidates=weeks.where((w)=>w['monday']!=first && DateTime.parse(w['monday']).isAfter(DateTime.now())).toList();
    if(candidates.isEmpty){notice('No hay semanas futuras disponibles');return;}
    other=candidates.first['monday'] as String;
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(
      builder:(ctx,setLocal)=>AlertDialog(title:const Text('Solicitar cambio de semana'),content:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Semana que deseas cambiar: $first'),const SizedBox(height:12),
          DropdownButton<String>(value:other,isExpanded:true,
            items:candidates.map((w)=>DropdownMenuItem<String>(value:w['monday'] as String,
              child:Text('${w['memberName']} — ${w['monday']}'))).toList(),
            onChanged:(v)=>setLocal(()=>other=v)),
          const Text('El otro familiar deberá aceptar antes de realizar el intercambio.'),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Solicitar'))])));
    if(accepted==true&&other!=null){
      try{await widget.api.post('/api/swaps',{'firstMonday':first,'secondMonday':other});reload();notice('Solicitud enviada');}
      catch(e){notice(e.toString());}
    }
  }

  Future<void> decision(String id,bool accept) async {
    try{await widget.api.post('/api/swaps/$id/decision',{'accept':accept});reload();notice(accept?'Intercambio aceptado':'Solicitud rechazada');}
    catch(e){notice(e.toString());}
  }

  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: data, builder: (context, snap) {
      if (!snap.hasData) return Center(child: snap.hasError
        ? Text('No se pudieron cargar los turnos: ${snap.error}')
        : const CircularProgressIndicator());
      final weeks = snap.data![0] as List;
      final members = snap.data![1] as List;
      final me = snap.data![2] as Map<String, dynamic>;
      final swaps = snap.data![3] as List;
      if (weeks.isEmpty) return const PradoEmpty(title: 'Sin turnos',
        detail: 'No se encontraron semanas disponibles.');
      final current = weeks[selected] as Map<String, dynamic>;
      final monday = parseDate(current['monday'] as String);
      final completedMeals = _loadedMonday == current['monday']
        ? checks.where((x) => x['completed'] == true).length
        : ((current['completedMeals'] as num?)?.toInt() ?? 0);
      final canEditChecks = _loadedMonday == current['monday'] && !_loadingChecks && !submitting;
      final isResponsible = me['role'] == 'ADMIN' || me['memberId'] == current['memberId'];
      return RefreshIndicator(onRefresh: () async { reload(); await data; },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const PradoIntro(eyebrow: 'Nos cuidamos en familia',
            title: 'Turnos de comida',
            subtitle: 'Cada semana, una persona acompaña con cariño.',
            icon: Icons.restaurant_outlined, tint: PradoColors.paleSand),
          if (current['configured'] != true) ...[
            PradoPanel(tint: PradoColors.peach, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const PradoPill('Calendario provisional',
                  color: PradoColors.coral, tint: PradoColors.peach),
                const SizedBox(height: 8),
                const Text('Confirma el orden real antes de registrar comidas.'),
                if (me['role'] == 'ADMIN') FilledButton(
                  onPressed: () => configure(members),
                  child: const Text('Confirmar calendario')),
              ])),
            const SizedBox(height: 14),
          ],
          PradoSectionHeading('Calendario continuo',
            subtitle: 'Consulta semanas anteriores o futuras.'),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: submitting ? null : () => _changePage(-1),
              icon: const Icon(Icons.chevron_left), label: const Text('Anterior'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: submitting ? null : () => _changePage(1),
              icon: const Icon(Icons.chevron_right), label: const Text('Siguiente'))),
          ]),
          const SizedBox(height: 12),
          SizedBox(height: 82, child: ListView.separated(
            scrollDirection: Axis.horizontal, itemCount: weeks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final week = weeks[index];
              final chosen = selected == index;
              return InkWell(onTap: submitting ? null : () {
                setState(() => selected = index);
                fetchChecks(week['monday'] as String);
              }, borderRadius: BorderRadius.circular(17),
                child: Container(width: 126, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: chosen ? PradoColors.navy : PradoColors.paper,
                    border: Border.all(color: chosen ? PradoColors.navy : PradoColors.line),
                    borderRadius: BorderRadius.circular(17)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${dateSpanish(parseDate(week['monday'] as String))}',
                      style: TextStyle(fontSize: 13,
                        color: chosen ? Colors.white70 : PradoColors.muted)),
                    const SizedBox(height: 5),
                    Text('${week['memberName']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                        color: chosen ? Colors.white : PradoColors.navy)),
                  ])));
            })),
          const SizedBox(height: 16),
          PradoPanel(tint: PradoColors.paleBlue,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RESPONSABLE DE LA SEMANA', style: TextStyle(
                letterSpacing: 1.1, fontSize: 12, color: PradoColors.ocean,
                fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('${current['memberName']}', style: Theme.of(context).textTheme.titleLarge),
              Text('${dateSpanish(monday)} al ${dateSpanish(monday.add(const Duration(days: 6)))}',
                style: const TextStyle(color: PradoColors.muted, fontSize: 15)),
              const SizedBox(height: 13),
              Row(children: [
                Expanded(child: Text('$completedMeals de 21 comidas registradas',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                PradoPill('${(completedMeals / 21 * 100).round()}%'),
              ]),
              const SizedBox(height: 7),
              LinearProgressIndicator(value: completedMeals / 21,
                minHeight: 8, borderRadius: BorderRadius.circular(10),
                color: PradoColors.teal, backgroundColor: Colors.white),
              if (current['configured'] == true &&
                  monday.isAfter(firstMonday(peruToday())) && isResponsible) ...[
                const SizedBox(height: 9),
                OutlinedButton.icon(onPressed: () => swap(current['monday'], weeks),
                  icon: const Icon(Icons.swap_horiz), label: const Text('Solicitar intercambio')),
              ],
            ])),
          const SizedBox(height: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ver semana como', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: SegmentedButton<bool>(showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Agenda'), icon: Icon(Icons.view_agenda_outlined)),
                ButtonSegment(value: false, label: Text('Detalle'), icon: Icon(Icons.checklist_outlined)),
              ],
              selected: {agendaView}, onSelectionChanged: (v) => _saveView(v.first))),
          ]),
          const SizedBox(height: 8),
          if (_loadingChecks) const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator()),
          if (_checksError != null) PradoPanel(tint: PradoColors.peach,
            child: Column(children: [
              Text(_checksError!),
              TextButton.icon(onPressed: () => fetchChecks(current['monday'] as String),
                icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
            ])),
          if (!isResponsible) const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Solo el responsable de esta semana puede marcar las comidas.',
              style: TextStyle(color: PradoColors.muted, fontSize: 14))),
          if (agendaView) ...List.generate(7, (day) {
            final date = monday.add(Duration(days: day));
            final key = isoDate(date);
            final count = ['BREAKFAST', 'LUNCH', 'DINNER']
              .where((type) => done(key, type)).length;
            return Padding(padding: const EdgeInsets.only(bottom: 10),
              child: PradoPanel(child: Row(children: [
                Container(width: 52, height: 54,
                  decoration: BoxDecoration(color: count == 3
                    ? PradoColors.mint : PradoColors.paleSand,
                    borderRadius: BorderRadius.circular(15)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${date.day}', style: const TextStyle(
                      color: PradoColors.navy, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('${date.month}/${date.year.toString().substring(2)}',
                      style: const TextStyle(fontSize: 10, color: PradoColors.muted)),
                  ])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(daysSpanish[day], style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(count == 3 ? 'Día completo' : count == 0 ? 'Sin registros'
                    : '$count de 3 comidas registradas',
                    style: const TextStyle(color: PradoColors.muted, fontSize: 14)),
                ])),
                PradoPill('$count/3', color: count == 3 ? PradoColors.teal : PradoColors.ocean,
                  tint: count == 3 ? PradoColors.mint : PradoColors.paleBlue,
                  icon: count == 3 ? Icons.check_circle : Icons.timelapse),
              ])));
          }) else ...List.generate(7, (day) {
            final date = monday.add(Duration(days: day));
            final key = isoDate(date);
            return Padding(padding: const EdgeInsets.only(bottom: 11),
              child: PradoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PradoSectionHeading('${daysSpanish[day]} · ${date.day}/${date.month}'),
                  for (final meal in const [
                    ('BREAKFAST', 'Desayuno'), ('LUNCH', 'Almuerzo'), ('DINNER', 'Cena'),
                  ]) Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(done(key, meal.$1) ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                        color: done(key, meal.$1) ? PradoColors.teal : PradoColors.muted,
                        size: 25),
                      const SizedBox(width: 10),
                      Expanded(child: Text(meal.$2, style: const TextStyle(fontSize: 16))),
                      done(key, meal.$1)
                        ? OutlinedButton(onPressed: !canEditChecks ||
                            current['configured'] != true || date.isAfter(peruToday()) || !isResponsible
                            ? null : () => toggle(current['monday'], key, meal.$1),
                            child: const Text('Desmarcar'))
                        : FilledButton.tonal(onPressed: !canEditChecks ||
                            current['configured'] != true || date.isAfter(peruToday()) || !isResponsible
                            ? null : () => toggle(current['monday'], key, meal.$1),
                            child: const Text('Marcar')),
                    ])),
                ])));
          }),
          if (swaps.any((s) => s['status'] == 'PENDING')) ...[
            const SizedBox(height: 10),
            const PradoSectionHeading('Solicitudes de intercambio'),
            for (final s in swaps.where((s) => s['status'] == 'PENDING'))
              Padding(padding: const EdgeInsets.only(bottom: 10),
                child: PradoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cambiar ${s['weekA']} por ${s['weekB']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (me['role'] == 'ADMIN' || me['memberId'] == s['memberB'])
                      Wrap(spacing: 8, children: [
                        OutlinedButton(onPressed: () => decision(s['id'], false),
                          child: const Text('Rechazar')),
                        FilledButton(onPressed: () => decision(s['id'], true),
                          child: const Text('Aceptar cambio')),
                      ]),
                  ]))),
          ],
          const SizedBox(height: 24),
        ]));
    });
}
