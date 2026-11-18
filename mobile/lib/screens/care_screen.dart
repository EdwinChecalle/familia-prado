import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../core/api.dart';

/// Área privada; toda operación vuelve a comprobar permisos en Spring Boot.
class CareScreen extends StatefulWidget {
  const CareScreen({super.key, required this.api});
  final FamilyApi api;
  @override
  State<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends State<CareScreen> {
  bool loading = true, allowed = false, admin = false, busy = false;
  bool hasLoaded = false, refreshing = false;
  String? error;
  List<Map<String, dynamic>> medications = [],
      records = [],
      observations = [],
      documents = [],
      grants = [];
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted || refreshing) return;
    refreshing = true;
    // A refresh after a save must not remove and recreate the tab tree.
    if (!hasLoaded) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final access = Map<String, dynamic>.from(
        await widget.api.get('/api/care/access/me') as Map,
      );
      final canRead = access['allowed'] == true;
      final isAdmin = access['admin'] == true;
      final results = canRead
          ? await Future.wait<dynamic>([
              widget.api.get('/api/care/medications'),
              widget.api.get('/api/care/medication-records'),
              widget.api.get('/api/care/observations'),
              widget.api.get('/api/care/documents'),
              if (isAdmin) widget.api.get('/api/care/access'),
            ])
          : <dynamic>[];
      if (!mounted) return;
      setState(() {
        allowed = canRead;
        admin = isAdmin;
        if (canRead) {
          medications = _maps(results[0]);
          records = _maps(results[1]);
          observations = _maps(results[2]);
          documents = _maps(results[3]);
          grants = isAdmin ? _maps(results[4]) : [];
        } else {
          medications = [];
          records = [];
          observations = [];
          documents = [];
          grants = [];
        }
        hasLoaded = true;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        // Never leave sensitive data visible after authorization is lost.
        setState(() {
          allowed = false;
          admin = false;
          medications = [];
          records = [];
          observations = [];
          documents = [];
          grants = [];
          loading = false;
          hasLoaded = false;
          error = e.toString();
        });
      } else if (!hasLoaded) {
        setState(() {
          error = '$e';
          loading = false;
        });
      } else {
        _message(
            'El cambio puede haberse guardado, pero no se pudieron actualizar los datos. Vuelve a consultar.');
      }
    } finally {
      refreshing = false;
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) =>
      (value as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _perform(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
      await _refresh();
    } catch (e) {
      _message('No se guardó el cambio: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, String>?> _fields(
    String title,
    List<String> labels, {
    Map<String, String>? defaults,
  }) {
    // The dialog owns and disposes its controllers AFTER its route is removed.
    return showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _CareFieldsDialog(
        title: title,
        labels: labels,
        defaults: defaults,
      ),
    );
  }

  Future<void> _createMedication() async {
    final data = await _fields('Registrar indicación del profesional', [
      'Medicamento',
      'Indicación exacta',
      'Profesional (opcional)',
      'Horarios (08:00,20:00)',
      'Fecha inicio (AAAA-MM-DD)',
      'Fecha fin (opcional)'
    ], defaults: {
      'Fecha inicio (AAAA-MM-DD)': isoDate(peruToday())
    });
    if (data == null) return;
    await _perform(() async {
      await widget.api.post('/api/care/medications', {
        'name': data['Medicamento'],
        'instructions': data['Indicación exacta'],
        'prescriber': data['Profesional (opcional)'],
        'scheduleTimes': data['Horarios (08:00,20:00)'],
        'startsOn': data['Fecha inicio (AAAA-MM-DD)'],
        'endsOn': data['Fecha fin (opcional)']!.isEmpty
            ? null
            : data['Fecha fin (opcional)'],
      });
    });
  }

  Future<void> _markMedication(
      Map<String, dynamic> med, String time, String status) async {
    final given = status == 'REPORTED_GIVEN';
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(given
                  ? 'Confirmar administración'
                  : 'Confirmar que NO se administró'),
              content: Text(
                  '¿Confirmas el registro de ${med['name']} a las $time para hoy? '
                  'Esto documenta un hecho; no indica que debas administrar otra dosis.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Volver')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirmar'))
              ],
            ));
    if (confirm != true) return;
    await _perform(() async {
      await widget.api.post('/api/care/medications/${med['id']}/records', {
        'scheduledDate': isoDate(peruToday()),
        'scheduledTime': time,
        'status': status,
        'comment': null,
      });
    });
  }

  Future<void> _observe(String kind) async {
    final noteOnly = kind == 'NOTE';
    final pressure = kind == 'BLOOD_PRESSURE';
    final fields = noteOnly
        ? ['Observación']
        : [
            'Valor principal',
            if (pressure) 'Presión diastólica',
            'Observación (opcional)'
          ];
    final data = await _fields('Nuevo registro', fields);
    if (data == null) return;
    await _perform(() async {
      await widget.api.post('/api/care/observations', {
        'kind': kind,
        'valuePrimary': noteOnly
            ? null
            : num.tryParse(data['Valor principal']!.replaceAll(',', '.')),
        'valueSecondary': pressure
            ? num.tryParse(data['Presión diastólica']!.replaceAll(',', '.'))
            : null,
        'notes':
            noteOnly ? data['Observación'] : data['Observación (opcional)'],
        'observedAt': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> _upload() async {
    final data = await _fields('Guardar documento', ['Título']);
    if (data == null) return;
    final category = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
              title: const Text('Tipo de documento'),
              children: [
                for (final option in const [
                  ('RECIPE', 'Receta médica'),
                  ('EXAM', 'Resultado de examen'),
                  ('ORDER', 'Orden médica'),
                  ('OTHER', 'Otro documento')
                ])
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, option.$1),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(option.$2))),
              ],
            ));
    if (category == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;

    await _perform(() async {
      final bytes = file.bytes;

      if (bytes == null) {
        throw StateError(
          'No se pudo leer el documento seleccionado.',
        );
      }

      await widget.api.uploadCareDocument(
        data['Título']!,
        category,
        file.name,
        bytes,
      );
    });
  }

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    final okay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Abrir documento privado'),
              content: const Text('Se abrirá con un visor externo del celular. '
                  'Ese visor podría conservar una copia. ¿Deseas continuar?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Abrir'))
              ],
            ));
    if (okay != true) return;
    await _perform(() async {
      final bytes = await widget.api.downloadCareDocument('${doc['id']}');
      final mime = '${doc['mimeType']}';
      final ext = mime == 'application/pdf'
          ? '.pdf'
          : mime == 'image/png'
              ? '.png'
              : '.jpg';
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/prado-${doc['id']}$ext');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        // Keep the inherited tab controller mounted during background refreshes.
        length: admin ? 4 : 3,
        child: Scaffold(
          appBar: AppBar(title: const Text('Cuidado de Papá Isidro')),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('No se pudo consultar el área privada: $error'),
                          TextButton(
                              onPressed: _refresh,
                              child: const Text('Reintentar')),
                        ],
                      ),
                    )
                  : !allowed
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                                'Tu cuenta todavía no tiene autorización para consultar información médica. Solicita acceso al administrador familiar.'),
                          ),
                        )
                      : Column(
                          children: [
                            TabBar(
                              isScrollable: true,
                              tabs: [
                                const Tab(text: 'Medicamentos'),
                                const Tab(text: 'Salud'),
                                const Tab(text: 'Documentos'),
                                if (admin) const Tab(text: 'Accesos'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _medicines(),
                                  _health(),
                                  _documents(),
                                  if (admin) _accesses(),
                                ],
                              ),
                            ),
                          ],
                        ),
        ),
      );

  Widget _medicines() {
    final now = isoDate(peruToday());
    return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          const Text(
              'Solo registra indicaciones entregadas por un profesional. '
              'Sin marca = estado desconocido. No repitas dosis basándote en esta pantalla.'),
          if (admin)
            FilledButton.icon(
                onPressed: busy ? null : _createMedication,
                icon: const Icon(Icons.add),
                label: const Text('Agregar indicación médica')),
          for (final med in medications)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${med['name']}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('Indicaciones: ${med['instructions']}'),
                          Text(
                              'Horario: ${med['scheduleTimes']} · Desde: ${med['startsOn']}'),
                          if (med['endsOn'] != null)
                            Text('Hasta: ${med['endsOn']}'),
                          Text(med['active'] == true ? 'Vigente' : 'Inactiva'),
                          if (med['active'] == true &&
                              now.compareTo('${med['startsOn']}') >= 0 &&
                              (med['endsOn'] == null ||
                                  now.compareTo('${med['endsOn']}') <= 0))
                            for (final time in '${med['scheduleTimes']}'
                                .split(',')
                                .map((s) => s.trim())) ...[
                              const Divider(),
                              Text('Hoy, $time'),
                              Builder(builder: (context) {
                                final found = records.where((rec) =>
                                    rec['medicationId'] == '${med['id']}' &&
                                    rec['scheduledDate'] == now &&
                                    '${rec['scheduledTime']}'.startsWith(time));
                                if (found.isNotEmpty) {
                                  final rec = found.first;
                                  return Text(
                                      rec['status'] == 'REPORTED_GIVEN'
                                          ? 'Registrado como administrado por ${rec['registeredBy']}'
                                          : 'Registrado como NO administrado por ${rec['registeredBy']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold));
                                }
                                return Wrap(spacing: 8, children: [
                                  FilledButton.tonal(
                                      onPressed: busy
                                          ? null
                                          : () => _markMedication(
                                              med, time, 'REPORTED_GIVEN'),
                                      child: const Text('Se administró')),
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _markMedication(
                                              med, time, 'REPORTED_NOT_GIVEN'),
                                      child: const Text('No se administró')),
                                ]);
                              }),
                            ],
                          if (admin && med['active'] == true)
                            TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _perform(() async {
                                          await widget.api.patch(
                                              '/api/care/medications/${med['id']}/stop',
                                              {});
                                        }),
                                child: const Text('Desactivar indicación')),
                        ]))),
          const SizedBox(height: 14),
          Text('Últimas constancias',
              style: Theme.of(context).textTheme.titleMedium),
          for (final rec in records.take(35))
            ListTile(
                title: Text(
                    '${rec['medicationName']} · ${rec['scheduledDate']} ${rec['scheduledTime']}'),
                subtitle: Text(
                    '${rec['status'] == 'REPORTED_GIVEN' ? 'Administrado' : 'NO administrado'} · ${rec['registeredBy']}'),
                trailing: admin
                    ? PopupMenuButton<String>(
                        onSelected: (newStatus) => _correct(rec, newStatus),
                        itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'REPORTED_GIVEN',
                                  child: Text('Corregir: administrado')),
                              PopupMenuItem(
                                  value: 'REPORTED_NOT_GIVEN',
                                  child: Text('Corregir: NO administrado'))
                            ])
                    : null),
          if (medications.isEmpty)
            const Text('Todavía no hay indicaciones registradas.'),
        ]));
  }

  Future<void> _correct(Map<String, dynamic> rec, String newStatus) async {
    final data = await _fields('Corrección auditable', ['Motivo obligatorio']);
    if (data == null) return;
    await _perform(() async {
      await widget.api.patch(
          '/api/care/medication-records/${rec['id']}/correct',
          {'status': newStatus, 'reason': data['Motivo obligatorio']});
    });
  }

  Widget _health() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const Text(
            'Anota medidas tal como fueron obtenidas. La app no diagnostica ni recomienda tratamientos.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: busy ? null : () => _observe('GLUCOSE'),
              child: const Text('Glucosa (mg/dL)')),
          OutlinedButton(
              onPressed: busy ? null : () => _observe('BLOOD_PRESSURE'),
              child: const Text('Presión (mmHg)')),
          OutlinedButton(
              onPressed: busy ? null : () => _observe('TEMPERATURE'),
              child: const Text('Temperatura (°C)')),
          FilledButton.tonal(
              onPressed: busy ? null : () => _observe('NOTE'),
              child: const Text('Observación')),
        ]),
        for (final r in observations)
          Card(
              child: ListTile(
            title: Text(switch ('${r['kind']}') {
              'GLUCOSE' => 'Glucosa: ${r['valuePrimary']} mg/dL',
              'BLOOD_PRESSURE' =>
                'Presión: ${r['valuePrimary']}/${r['valueSecondary']} mmHg',
              'TEMPERATURE' => 'Temperatura: ${r['valuePrimary']} °C',
              _ => 'Observación',
            }),
            subtitle: Text(
                '${r['observedAt']} · ${r['registeredBy']}\n${r['notes'] ?? ''}'),
          )),
        if (observations.isEmpty)
          const Text('No hay observaciones registradas.'),
      ]));
  Widget _documents() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const Text(
            'Recetas, órdenes y resultados con acceso restringido. Máximo 5 MB por documento.'),
        if (admin)
          FilledButton.icon(
              onPressed: busy ? null : _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Subir documento privado')),
        for (final doc in documents)
          Card(
              child: ListTile(
            title: Text('${doc['title']}'),
            subtitle: Text(
                '${doc['category']} · ${doc['originalName']}\nSubió: ${doc['uploadedBy']}'),
            trailing: IconButton(
                tooltip: 'Abrir documento',
                icon: const Icon(Icons.file_open),
                onPressed: busy ? null : () => _openDocument(doc)),
          )),
        if (documents.isEmpty) const Text('Aún no hay documentos.'),
      ]));
  Widget _accesses() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const Text(
            'El administrador decide expresamente quién puede consultar registros médicos. '
            'No todos los familiares tienen acceso automáticamente.'),
        for (final g in grants)
          SwitchListTile(
            title: Text('${g['displayName']}'),
            subtitle: const Text('Acceso a salud, medicamentos y documentos'),
            value: g['allowed'] == true,
            onChanged: busy
                ? null
                : (val) => _perform(() async {
                      await widget.api.put('/api/care/access/${g['memberId']}',
                          {'allowed': val});
                    }),
          ),
      ]));
}

/// Controllers belong to the dialog route, not the async caller.
/// showDialog can resolve before the reverse transition has fully unmounted its text fields.
class _CareFieldsDialog extends StatefulWidget {
  const _CareFieldsDialog({
    required this.title,
    required this.labels,
    this.defaults,
  });

  final String title;
  final List<String> labels;
  final Map<String, String>? defaults;

  @override
  State<_CareFieldsDialog> createState() => _CareFieldsDialogState();
}

class _CareFieldsDialogState extends State<_CareFieldsDialog> {
  late final Map<String, TextEditingController> controllers;

  @override
  void initState() {
    super.initState();
    controllers = {
      for (final label in widget.labels)
        label: TextEditingController(text: widget.defaults?[label] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final label in widget.labels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controllers[label],
                      keyboardType: label.contains('Valor') ||
                              label.contains('Presión')
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(labelText: label),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: const Text('Guardar'),
          ),
        ],
      );
}
