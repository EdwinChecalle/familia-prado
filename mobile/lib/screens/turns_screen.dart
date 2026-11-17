import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';

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
  String? _loadedMonday;
  String? _checksError;
  bool _loadingChecks = false;
  int _checksRequestId = 0;
  @override void initState(){
    super.initState();
    refresh();
    widget.updates.addListener(_onUpdate);
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

  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future:data,builder:(context,snap){
    if(!snap.hasData)return Center(child:snap.hasError?Text('Error: ${snap.error}'):
      const CircularProgressIndicator());
    final weeks=snap.data![0] as List, members=snap.data![1] as List,
      me=snap.data![2] as Map<String,dynamic>, swaps=snap.data![3] as List;
    final current=weeks[selected] as Map<String,dynamic>;
    final monday=parseDate(current['monday'] as String);
    // Mientras llegan las comidas usamos el total del servidor; después, la lista
    // de la semana seleccionada es la única fuente del contador y los botones.
    final completedMeals = _loadedMonday == current['monday']
        ? checks.where((x) => x['completed'] == true).length
        : ((current['completedMeals'] as num?)?.toInt() ?? 0);
    final canEditChecks = _loadedMonday == current['monday'] && !_loadingChecks && !submitting;
    return RefreshIndicator(onRefresh:()async {reload();await data;},child:ListView(padding:const EdgeInsets.all(16),children:[
      if(current['configured']!=true) Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Calendario pendiente de confirmación',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
          const Text('El orden actual es provisional. No se podrán registrar comidas hasta que se confirme.'),
          if(me['role']=='ADMIN') FilledButton(onPressed:()=>configure(members),child:const Text('Confirmar calendario')),
        ]))),
      const SizedBox(height:8),
      Text('Calendario continuo de comidas',style:Theme.of(context).textTheme.titleMedium),
      Row(children: [
        OutlinedButton.icon(onPressed: submitting ? null : () => _changePage(-1),
          icon: const Icon(Icons.chevron_left), label: const Text('Anterior')),
        const Spacer(),
        OutlinedButton.icon(onPressed: submitting ? null : () => _changePage(1),
          icon: const Icon(Icons.chevron_right), label: const Text('Siguiente')),
      ]),
      Text('Del ${dateSpanish(firstMonday(peruToday()).add(Duration(days:cyclePage*16*7)))} '
        'al ${dateSpanish(firstMonday(peruToday()).add(Duration(days:(cyclePage+1)*16*7-1)))}'),
      const SizedBox(height:8),
      Text('Selecciona una semana',style:Theme.of(context).textTheme.titleMedium),
      SizedBox(height:104,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:weeks.length,
        separatorBuilder:(context,index)=>const SizedBox(width:8),itemBuilder:(ctx,index){
          final w=weeks[index];
          return ChoiceChip(selected:selected==index,showCheckmark:false,
            label:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(mainAxisSize:MainAxisSize.min,
              children:[Text('Semana ${index+1}'),Text(w['memberName'],style:const TextStyle(fontWeight:FontWeight.bold))])),
            onSelected:submitting ? null : (_){
              setState(() => selected=index);
              fetchChecks(w['monday'] as String);
            });
        })),
      const SizedBox(height:14),
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Persona encargada de cocinar',style:TextStyle(fontSize:16)),
          const SizedBox(height:5),
          Text(current['memberName'],style:Theme.of(context).textTheme.titleLarge),
          Text('Desde el lunes ${dateSpanish(monday)} hasta el domingo ${dateSpanish(monday.add(const Duration(days:6)))}'),
          const SizedBox(height:8),
          Text('$completedMeals de 21 comidas registradas'),
          if(current['configured']==true && monday.isAfter(firstMonday(peruToday())) &&
              (me['role']=='ADMIN'||me['memberId']==current['memberId']))
            OutlinedButton.icon(onPressed:()=>swap(current['monday'],weeks),
              icon:const Icon(Icons.swap_horiz),label:const Text('Pedir cambio de semana')),
        ]))),
      const SizedBox(height:8),
      if (_loadingChecks) const LinearProgressIndicator(),
      if (_checksError != null) Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_checksError!),
          TextButton.icon(
            onPressed: () => fetchChecks(current['monday'] as String),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ]),
      )),
      if(me['role']!='ADMIN' && me['memberId']!=current['memberId'])
        const Padding(padding:EdgeInsets.all(12),child:Text('Solo el familiar encargado puede marcar las comidas de esta semana.')),
      ...List.generate(7,(day){
        final date=monday.add(Duration(days:day)),key=isoDate(date);
        return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('${daysSpanish[day]} ${date.day}/${date.month}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
            const SizedBox(height:8),
            ...[('BREAKFAST','Desayuno'),('LUNCH','Almuerzo'),('DINNER','Cena')].map((meal)=>
              Padding(padding:const EdgeInsets.only(bottom:7),child:Row(children:[
                Icon(done(key,meal.$1)?Icons.check_circle:Icons.radio_button_unchecked,
                  color:done(key,meal.$1)?const Color(0xFF2E785B):Colors.grey),
                const SizedBox(width:10),Expanded(child:Text(meal.$2,style:const TextStyle(fontSize:17))),
                OutlinedButton(onPressed:!canEditChecks||current['configured']!=true || date.isAfter(peruToday()) ||
                    (me['role']!='ADMIN'&&me['memberId']!=current['memberId'])?null:
                  ()=>toggle(current['monday'],key,meal.$1),
                  child:Text(done(key,meal.$1)?'Desmarcar':'Marcar')),
              ]))),
          ])));
      }),
      if(swaps.isNotEmpty) ...[
        const SizedBox(height:14),Text('Solicitudes de intercambio',style:Theme.of(context).textTheme.titleMedium),
        ...swaps.where((x)=>x['status']=='PENDING').map((x)=>Card(child:Padding(
          padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Cambiar ${x['weekA']} por ${x['weekB']}'),
          if(me['role']=='ADMIN'||me['memberId']==x['memberB']) Wrap(spacing:8,children:[
            TextButton(onPressed:()=>decision(x['id'],false),child:const Text('Rechazar')),
            FilledButton(onPressed:()=>decision(x['id'],true),child:const Text('Aceptar cambio')),
          ]),
        ])))),
      ],
    ]));
  });
}
