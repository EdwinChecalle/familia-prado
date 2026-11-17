import 'package:flutter/material.dart';
import '../core/api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final FamilyApi api;
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> data;
  @override void initState(){ super.initState(); load(); }
  void load(){ data=Future.wait([
    widget.api.get('/api/turns?from=${isoDate(firstMonday(peruToday()))}&weeks=1'),
    widget.api.get('/api/fund/summary'),
    widget.api.get('/api/appointments'),
  ]); }
  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {setState(load); await data;},
    child: FutureBuilder<List<dynamic>>(
      future: data,
      builder: (context,snap){
        if(!snap.hasData) return ListView(children:[const SizedBox(height:200),
          Center(child: snap.hasError ? Text('No se pudieron cargar los datos: ${snap.error}') : const CircularProgressIndicator())]);
        final turn=(snap.data![0] as List).first as Map<String,dynamic>;
        final fund=snap.data![1] as Map<String,dynamic>;
        final appointments=(snap.data![2] as List);
        return ListView(padding: const EdgeInsets.all(18), children:[
          const Text('Organización de nuestra familia', style: TextStyle(fontSize:19, fontWeight: FontWeight.w700)),
          const SizedBox(height:16),
          _info(context,'Esta semana cocina',turn['memberName'] as String,
            'De lunes a domingo: desayuno, almuerzo y cena',Icons.restaurant_menu),
          if(turn['configured'] != true) const Padding(padding: EdgeInsets.symmetric(vertical:10),
            child: Text('Atención: el calendario es provisional. El administrador debe confirmar el orden real.',
              style: TextStyle(fontWeight: FontWeight.bold,color: Color(0xFF9C5238)))),
          const SizedBox(height:12),
          _info(context,'Dinero disponible en la caja','S/ ${fund['available']}',
            'Solo incluye aportes verificados y gastos aprobados',Icons.wallet),
          const SizedBox(height:12),
          _info(context,'Próximas citas', '${appointments.length} citas registradas',
            'Consulta el responsable y los detalles en Citas médicas',Icons.event),
          const SizedBox(height:16),
          const Text('Desliza hacia abajo para actualizar la información.',textAlign:TextAlign.center),
        ]);
      },
    ),
  );
  Widget _info(BuildContext context,String title,String value,String explanation,IconData icon) =>
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,children:[
        Row(children:[Icon(icon,color:const Color(0xFF2F5678)),const SizedBox(width:10),
          Expanded(child: Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w600)))]),
        const SizedBox(height:10),Text(value,style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:6),Text(explanation),
      ])));
}
