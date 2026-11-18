import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../core/family_alerts.dart';
import '../ui/prado_design.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.displayName,
    required this.role, required this.onNavigate, required this.onAlerts,
    required this.onCare, required this.alerts, required this.updates});
  final FamilyApi api;
  final String displayName, role;
  final ValueChanged<int> onNavigate;
  final VoidCallback onAlerts, onCare;
  final FamilyAlerts alerts;
  final LiveUpdates updates;
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> data;
  @override void initState() {
    super.initState();
    _load();
    widget.updates.addListener(_onUpdate);
  }
  @override void dispose() {
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }
  void _onUpdate() { if (mounted) setState(_load); }
  void _load() {
    data = Future.wait([
      widget.api.get('/api/turns?from=${isoDate(firstMonday(peruToday()))}&weeks=1'),
      widget.api.get('/api/fund/summary'),
      widget.api.get('/api/appointments/summary'),
      widget.api.get('/api/members'),
    ]);
  }

  Widget _accessCard({required String title, required String value,
    required String detail, required IconData icon, required Color tint,
    required VoidCallback onTap, Widget? badge}) {
    return PradoPanel(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(height: 43, width: 43, decoration: BoxDecoration(
          color: tint, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: PradoColors.navy)),
        const SizedBox(width: 11),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
        const Icon(Icons.chevron_right_rounded, color: PradoColors.ocean),
      ]),
      const SizedBox(height: 10),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(detail, style: const TextStyle(fontSize: 14, color: PradoColors.muted)),
      if (badge != null) ...[const SizedBox(height: 10), badge],
    ]));
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async { setState(_load); await data; await widget.alerts.refresh(); },
    child: FutureBuilder<List<dynamic>>(future: data, builder: (context, snap) {
      if (!snap.hasData) return ListView(children: [const SizedBox(height: 180),
        Center(child: snap.hasError ? Padding(padding: const EdgeInsets.all(24),
          child: Text('No se pudieron cargar los datos: ${snap.error}'))
          : const CircularProgressIndicator())]);
      final weeks = snap.data![0] as List;
      final turn = weeks.isEmpty ? <String, dynamic>{} : weeks.first as Map<String, dynamic>;
      final fund = snap.data![1] as Map<String, dynamic>;
      final appointments = snap.data![2] as Map<String, dynamic>;
      final members = snap.data![3] as List;
      final names = {for (final m in members) m['id']: m['name']};
      final next = appointments['next'];
      final nextDesc = next is Map ?
        '${dateSpanish(peruClock(next['appointmentAt'] as String))} · '
        '${names[next['responsibleMemberId']] ?? 'Por asignar'}' :
        'Todavía no hay una cita futura programada';
      return ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(color: PradoColors.navy,
            borderRadius: BorderRadius.circular(25)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.favorite_rounded, color: PradoColors.sand, size: 19),
              const SizedBox(width: 7),
              Text('FAMILIA PRADO', style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 15),
            Text('Hola, ${widget.displayName}',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Nos organizamos para cuidar de Papá Isidro.',
              style: TextStyle(color: Color(0xFFE2EAF1), fontSize: 16)),
            const SizedBox(height: 13),
            Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(15)),
              child: Text(widget.role == 'ADMIN' ? 'Cuenta: Administrador'
                : 'Cuenta: ${widget.displayName}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ])),
        const SizedBox(height: 23),
        const PradoSectionHeading('Lo más importante',
          subtitle: 'Todo lo que necesitas, a un toque.'),
        _accessCard(title: 'Esta semana cocina', value: '${turn['memberName'] ?? 'Por confirmar'}',
          detail: 'Desayuno, almuerzo y cena · Papá Isidro',
          tint: PradoColors.paleSand, icon: Icons.restaurant_menu_rounded,
          onTap: () => widget.onNavigate(1),
          badge: turn['configured'] == true ? null : const PradoPill('Calendario provisional',
            color: PradoColors.coral, tint: PradoColors.peach)),
        const SizedBox(height: 12),
        _accessCard(title: 'Próxima cita médica',
          value: next is Map ? '${next['specialty']}' : 'Sin próximas citas',
          detail: nextDesc, tint: PradoColors.paleBlue,
          icon: Icons.calendar_month_outlined,
          onTap: () => widget.onNavigate(3)),
        const SizedBox(height: 12),
        _accessCard(title: 'Dinero disponible en caja',
          value: pradoMoney(fund['available']),
          detail: 'Solo aportes verificados menos gastos aprobados',
          tint: PradoColors.mint, icon: Icons.account_balance_wallet_outlined,
          onTap: () => widget.onNavigate(2)),
        const SizedBox(height: 12),
        _accessCard(title: 'Cuidado de Papá Isidro', value: 'Su bienestar, en familia',
          detail: 'Medicamentos, salud y documentos con acceso protegido',
          tint: PradoColors.peach, icon: Icons.favorite_border,
          onTap: widget.onCare),
        const SizedBox(height: 12),
        AnimatedBuilder(animation: widget.alerts, builder: (context, _) => _accessCard(
          title: 'Mis avisos',
          value: widget.alerts.unreadCount == 0 ? 'Todo al día' :
            '${widget.alerts.unreadCount} aviso(s) por leer',
          detail: 'Turnos, citas y novedades importantes',
          tint: PradoColors.paleSand, icon: Icons.notifications_active_outlined,
          onTap: widget.onAlerts)),
        const SizedBox(height: 24),
      ]);
    }),
  );
}
