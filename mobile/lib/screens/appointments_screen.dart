import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../core/appointment_filters.dart';
import '../ui/prado_design.dart';
import '../ui/family_report.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, required this.api, required this.updates});
  final FamilyApi api;
  final LiveUpdates updates;
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

  @override void initState() {
    super.initState();
    widget.updates.addListener(_onUpdate);
    _refresh();
  }

  void _onUpdate() {
    if (widget.updates.lastTopic == 'appointments' ||
        widget.updates.lastTopic == 'all') {
      _refresh();
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

  Future<void> _create() async {
    final hospital = TextEditingController();
    final specialty = TextEditingController();
    final prep = TextEditingController();
    DateTime day = peruToday();
    TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
    String? responsible = members.isEmpty ? null : members.first['id'] as String;
    try {
      final accepted = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Nueva cita médica'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: specialty, maxLength: 120,
              decoration: const InputDecoration(labelText: 'Especialidad o consulta')),
            const SizedBox(height: 10),
            TextField(controller: hospital, maxLength: 160,
              decoration: const InputDecoration(labelText: 'Centro médico o lugar')),
            const SizedBox(height: 12),
            PradoInfoRow(icon: Icons.calendar_today_outlined, text: dateSpanish(day)),
            OutlinedButton.icon(onPressed: () async {
              final value = await showDatePicker(context: ctx, initialDate: day,
                firstDate: DateTime(2025), lastDate: DateTime(2035));
              if (value != null) update(() => day = value);
            }, icon: const Icon(Icons.calendar_month), label: const Text('Elegir fecha')),
            PradoInfoRow(icon: Icons.schedule, text: 'Hora: ${time.format(ctx)}'),
            OutlinedButton.icon(onPressed: () async {
              final value = await showTimePicker(context: ctx, initialTime: time);
              if (value != null) update(() => time = value);
            }, icon: const Icon(Icons.access_time), label: const Text('Elegir hora')),
            if (members.isNotEmpty) DropdownButtonFormField<String>(
              initialValue: responsible, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Acompañante'),
              items: members.map((m) => DropdownMenuItem<String>(
                value: m['id'] as String, child: Text('${m['name']}'))).toList(),
              onChanged: (v) => update(() => responsible = v)),
            const SizedBox(height: 10),
            TextField(controller: prep, maxLength: 500, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Preparación (opcional)')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar cita')),
          ],
        ),
      ));
      if (accepted == true) {
        if (hospital.text.trim().isEmpty || specialty.text.trim().isEmpty) {
          _notice('Completa la consulta y el centro médico.');
          return;
        }
        await widget.api.post('/api/appointments', {
          'appointmentAt': peruToUtcIso(day, time.hour, time.minute),
          'hospital': hospital.text.trim(), 'specialty': specialty.text.trim(),
          'responsibleMemberId': responsible, 'preparation': prep.text.trim(),
        });
        await _refresh();
        _notice('Cita guardada correctamente');
      }
    } catch (e) { _notice('$e'); }
    finally { hospital.dispose(); specialty.dispose(); prep.dispose(); }
  }

  Future<void> _changeStatus(String id, String status) async {
    if (status == 'COMPLETED' || status == 'CANCELLED') {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(status == 'CANCELLED' ? '¿Cancelar esta cita?' : '¿Confirmar que se realizó?'),
        content: Text(status == 'CANCELLED'
          ? 'La cita quedará en el historial de canceladas y no generará futuros recordatorios.'
          : 'Se registrará como realizada. Este cambio no se puede deshacer.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar'))],
      ));
      if (ok != true) return;
    }
    try {
      await widget.api.patch('/api/appointments/$id/status', {'status': status});
      await _refresh();
      _notice('Estado actualizado');
    } catch (e) { _notice('$e'); }
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
    final day = peruClock('${next['appointmentAt']}');
    final hour = '${day.hour.toString().padLeft(2, '0')}:${day.minute.toString().padLeft(2, '0')}';
    await showFamilyReport(context, FamilyReport(
      title: 'Próxima cita de Papá Isidro',
      subtitle: 'Información de organización familiar',
      mainLabel: 'FECHA Y HORA · PERÚ',
      mainValue: '${dateSpanish(day)} · $hour',
      lines: [
        ReportLine('Consulta', '${next['specialty']}'),
        ReportLine('Lugar', '${next['hospital']}'),
        ReportLine('Acompañante',
          '${names[next['responsibleMemberId']] ?? 'Por asignar'}'),
        ReportLine('Estado', next['status'] == 'CONFIRMED'
          ? 'Confirmada' : 'Programada'),
      ],
      generatedLabel: peruReportStamp(),
      privacy: 'No incluye diagnósticos, medicamentos ni indicaciones médicas. '
          'Comparte solo con quienes deben conocer la cita.',
    ));
  }

  Widget _appointmentCard(Map<String, dynamic> a, Map<dynamic, dynamic> names) {
    final day = peruClock(a['appointmentAt'] as String);
    final hour = '${day.hour.toString().padLeft(2, '0')}:${day.minute.toString().padLeft(2, '0')}';
    final status = a['status'];
    final open = status == 'PLANNED' || status == 'CONFIRMED';
    final canChange = me['role'] == 'ADMIN' || me['memberId'] == a['responsibleMemberId'];
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
        PradoInfoRow(icon: Icons.person_outline, text: 'Acompaña: $name'),
        if ('${a['preparation'] ?? ''}'.trim().isNotEmpty)
          PradoInfoRow(icon: Icons.assignment_outlined, text: 'Preparación: ${a['preparation']}'),
        if (canChange && open) ...[
          const Divider(height: 22, color: PradoColors.line),
          Wrap(spacing: 8, runSpacing: 5, children: [
            if (status == 'PLANNED') OutlinedButton.icon(
              onPressed: () => _changeStatus('${a['id']}', 'CONFIRMED'),
              icon: const Icon(Icons.verified_outlined, size: 18), label: const Text('Confirmar')),
            OutlinedButton.icon(onPressed: () => _changeStatus('${a['id']}', 'COMPLETED'),
              icon: const Icon(Icons.done_all, size: 18), label: const Text('Realizada')),
            TextButton(onPressed: () => _changeStatus('${a['id']}', 'CANCELLED'),
              child: const Text('Cancelar cita')),
          ]),
        ],
      ]),
    ));
  }

  @override Widget build(BuildContext context) {
    final names = {for (final m in members) m['id']: m['name']};
    final next = summary['next'];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
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
        if (me['role'] == 'ADMIN') ...[
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_circle_outline),
            label: const Text('Registrar nueva cita')),
          const SizedBox(height: 14),
        ],
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
        const SizedBox(height: 24),
      ]),
    );
  }
}
