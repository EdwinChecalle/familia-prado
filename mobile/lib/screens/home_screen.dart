import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../core/family_alerts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.displayName,
    required this.role, required this.onNavigate, required this.onAlerts, required this.alerts,
    required this.updates});
  final FamilyApi api;
  final String displayName;
  final String role;
  final ValueChanged<int> onNavigate;
  final VoidCallback onAlerts;
  final FamilyAlerts alerts;
  final LiveUpdates updates;
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> data;
  @override void initState() {
    super.initState();
    load();
    widget.updates.addListener(_onUpdate);
  }
  @override void dispose() {
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }
  void _onUpdate() {
    if (mounted) setState(load);
  }
  void load() { data = Future.wait([
    widget.api.get('/api/turns?from=${isoDate(firstMonday(peruToday()))}&weeks=1'),
    widget.api.get('/api/fund/summary'), widget.api.get('/api/appointments'),
  ]); }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async { setState(load); await data; await widget.alerts.refresh(); },
    child: FutureBuilder<List<dynamic>>(
      future: data,
      builder: (context, snap) {
        if (!snap.hasData) return ListView(children: [const SizedBox(height: 200),
          Center(child: snap.hasError ? Text('No se pudieron cargar los datos: ${snap.error}')
            : const CircularProgressIndicator())]);
        final turn = (snap.data![0] as List).first as Map<String, dynamic>;
        final fund = snap.data![1] as Map<String, dynamic>;
        final appointments = snap.data![2] as List;
        return ListView(padding: const EdgeInsets.all(18), children: [
          Text('Hola, ${widget.displayName}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(widget.role == 'ADMIN' ? 'Estás usando la cuenta de Administrador'
            : 'Estás usando la cuenta de ${widget.displayName}',
            style: const TextStyle(fontSize: 15, color: Color(0xFF4B5A69))),
          const SizedBox(height: 18),
          _info('Esta semana cocina', '${turn['memberName']}',
            'Desayuno, almuerzo y cena de Papá Isidro', Icons.restaurant_menu, 1),
          if (turn['configured'] != true) const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('El calendario es provisional. El administrador debe confirmar el orden.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF9C5238)))),
          const SizedBox(height: 10),
          _info('Dinero disponible en la caja', 'S/ ${fund['available']}',
            'Aportes verificados y gastos aprobados', Icons.wallet_outlined, 2),
          const SizedBox(height: 10),
          _info('Citas médicas', '${appointments.length} citas registradas',
            'Ver responsables, fechas y detalles', Icons.event_outlined, 3),
          const SizedBox(height: 10),
          AnimatedBuilder(animation: widget.alerts, builder: (context, _) => Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: widget.onAlerts, child: Padding(
              padding: const EdgeInsets.all(18), child: Row(children: [
                const Icon(Icons.notifications_active_outlined, color: Color(0xFF2F5678)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Mis avisos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(widget.alerts.unreadCount == 0 ? 'No tienes avisos sin leer'
                    : '${widget.alerts.unreadCount} aviso(s) sin leer'),
                ])),
                const Icon(Icons.chevron_right),
              ]),
            )),
          )),
          const SizedBox(height: 12),
          const Text('Toca una tarjeta para entrar directamente. Desliza hacia abajo para actualizar.',
            textAlign: TextAlign.center),
        ]);
      },
    ),
  );

  Widget _info(String title, String value, String explanation, IconData icon, int destination) =>
    Card(clipBehavior: Clip.antiAlias, child: InkWell(
      onTap: () => widget.onNavigate(destination),
      child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: const Color(0xFF2F5678)), const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right),
          ]),
          const SizedBox(height: 10),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6), Text(explanation),
        ],
      )),
    ));
}
